<#
.SYNOPSIS
    Collects and displays AI usage costs across local development tools.

.DESCRIPTION
    Scans known data directories for Claude Code, Claude Desktop, Cursor, Windsurf,
    Cline, Roo Code, Aider, Continue.dev, and Codex. Parses JSONL/JSON usage
    files, calculates costs using model-specific pricing, and displays a
    box-drawing table with flexible grouping via -GroupBy
    (Date, Model, Tool, Project, Provider).

.PARAMETER Days
    Number of recent days to display. Default: 30. Use 0 for all time.
    Ignored when StartDate or EndDate is specified.

.PARAMETER StartDate
    Include usage on or after this date. Supports yyyy-MM-dd, yyyyMMdd,
    or any PowerShell-parseable date.

.PARAMETER EndDate
    Include usage on or before this date. Supports yyyy-MM-dd, yyyyMMdd,
    or any PowerShell-parseable date.

.PARAMETER Source
    Filter to a specific tool (e.g., 'Claude Code', 'Cursor', 'Codex').
    Supports wildcards.

.PARAMETER MinCost
    Minimum usage bucket cost to include (filters out near-zero noise). Default: 0.001.

.PARAMETER GroupBy
    One or more dimensions to group results by: Date, Model, Tool, Project, Provider.
    Non-specified dimensions are aggregated. Default: Date.

.PARAMETER Top
    Limit output to the N most expensive rows (after grouping).

.PARAMETER Raw
    Output raw usage bucket objects instead of formatted table (for piping).

.PARAMETER EstimateAttribution
    Experimental: estimate token/cost attribution within Claude local-agent sessions
    using turn-level audit logs. This is heuristic, not authoritative billing.

.PARAMETER AttributionBy
    Dimension for experimental attribution mode: Tool, McpServer, or Skill.
    Default: Tool.

.EXAMPLE
    ./Get-ClaudeUsage.ps1
    ./Get-ClaudeUsage.ps1 -Days 7
    ./Get-ClaudeUsage.ps1 -GroupBy Date,Model
    ./Get-ClaudeUsage.ps1 -GroupBy Project -Top 5
    ./Get-ClaudeUsage.ps1 -GroupBy Tool -Days 0
    ./Get-ClaudeUsage.ps1 -GroupBy Date,Provider
    ./Get-ClaudeUsage.ps1 -StartDate 2026-03-01 -EndDate 2026-03-31
    ./Get-ClaudeUsage.ps1 -Source 'Claude Code' -Days 0 -Raw | Export-Csv usage.csv
    ./Get-ClaudeUsage.ps1 -EstimateAttribution -AttributionBy McpServer -Days 7
#>

[CmdletBinding()]
param(
    [int]$Days = 30,
    [string]$StartDate,
    [string]$EndDate,
    [string]$Source,
    [ValidateSet('Date','Model','Tool','Project','Provider')]
    [string[]]$GroupBy = @('Date'),
    [int]$Top,
    [double]$MinCost = 0.001,
    [ValidateSet('Tool','McpServer','Skill')]
    [string]$AttributionBy = 'Tool',
    [switch]$EstimateAttribution,
    [switch]$Raw
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ─── Platform Detection ──────────────────────────────────

$IsWindows_ = $IsWindows -or ($env:OS -eq 'Windows_NT')
$IsMacOS_   = $IsMacOS -or ($PSVersionTable.OS -like '*Darwin*')
$Home_      = if ($IsWindows_) { $env:USERPROFILE } else { $env:HOME }

# ─── Pricing ─────────────────────────────────────────────

function Get-Pricing([string]$Model) {
    # Built-in pricing ($/MTok) — matches Anthropic published rates
    if (-not $Model) {
        return @{ Input = 3; Output = 15; CacheWrite = 3.75; CacheRead = 0.30 }
    }
    $m = $Model.ToLower()
    if ($m -eq 'gpt-5.4') {
        return @{ Input = 2.50; Output = 15.00; CacheWrite = 2.50; CacheRead = 0.25 }
    }
    if ($m -eq 'gpt-5.4-mini') {
        return @{ Input = 0.75; Output = 4.50; CacheWrite = 0.75; CacheRead = 0.075 }
    }
    if ($m -eq 'gpt-5.4-nano') {
        return @{ Input = 0.20; Output = 1.25; CacheWrite = 0.20; CacheRead = 0.02 }
    }
    if ($m -eq 'gpt-5') {
        return @{ Input = 1.25; Output = 10.00; CacheWrite = 1.25; CacheRead = 0.125 }
    }
    if ($m -eq 'gpt-5-mini') {
        return @{ Input = 0.25; Output = 2.00; CacheWrite = 0.25; CacheRead = 0.025 }
    }
    if ($m -eq 'gpt-5-nano') {
        return @{ Input = 0.05; Output = 0.40; CacheWrite = 0.05; CacheRead = 0.005 }
    }
    if ($m -match 'opus-4[-.]([56])') {
        return @{ Input = 5; Output = 25; CacheWrite = 6.25; CacheRead = 0.50 }
    }
    if ($m -match 'opus-4[-.]1') {
        return @{ Input = 15; Output = 75; CacheWrite = 18.75; CacheRead = 1.50 }
    }
    if ($m -match 'opus') {
        return @{ Input = 15; Output = 75; CacheWrite = 18.75; CacheRead = 1.50 }
    }
    if ($m -match 'sonnet') {
        return @{ Input = 3; Output = 15; CacheWrite = 3.75; CacheRead = 0.30 }
    }
    if ($m -match 'haiku-4[-.]5') {
        return @{ Input = 1; Output = 5; CacheWrite = 1.25; CacheRead = 0.10 }
    }
    if ($m -match 'haiku') {
        return @{ Input = 0.25; Output = 1.25; CacheWrite = 0.30; CacheRead = 0.03 }
    }
    return @{ Input = 3; Output = 15; CacheWrite = 3.75; CacheRead = 0.30 }
}

function Get-ShortModel([string]$Model) {
    if (-not $Model -or $Model -eq 'unknown') { return 'unknown' }
    $m = $Model -replace '^claude-', '' -replace '-\d{8}$', ''
    # Flip old-style "3-5-sonnet" → "sonnet-3-5"
    if ($m -match '^(\d+)-(\d+)-(.+)$') {
        $m = "$($Matches[3])-$($Matches[1])-$($Matches[2])"
    }
    return $m
}

# ─── Helpers ─────────────────────────────────────────────

function Find-JsonlFiles([string]$Dir, [int]$MaxDepth = 10) {
    if ($MaxDepth -le 0 -or -not (Test-Path $Dir)) { return @() }
    $results = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($item in Get-ChildItem -Path $Dir -Force -ErrorAction SilentlyContinue) {
            if ($item.PSIsContainer) {
                if ($item.Name -notlike '.git*' -and $item.Name -ne 'subagents') {
                    $sub = Find-JsonlFiles $item.FullName ($MaxDepth - 1)
                    foreach ($f in $sub) { $results.Add($f) }
                }
            }
            elseif ($item.Extension -eq '.jsonl' -and $item.Name -notlike '*audit*') {
                $results.Add($item.FullName)
            }
        }
    } catch {}
    return $results
}

function Parse-Timestamp($ts) {
    if ($null -eq $ts) { return $null }
    if ($ts -is [long] -or $ts -is [int] -or $ts -is [double]) { return $ts }
    if ($ts -is [datetime]) {
        return [DateTimeOffset]::new($ts, [TimeSpan]::Zero).ToUnixTimeMilliseconds()
    }
    if ($ts -is [DateTimeOffset]) {
        return $ts.ToUnixTimeMilliseconds()
    }
    if ($ts -is [string]) {
        try {
            $d = [DateTimeOffset]::Parse($ts)
            return $d.ToUnixTimeMilliseconds()
        } catch { return $null }
    }
    return $null
}

function Resolve-DateFilter([string]$Value, [string]$ParameterName) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    foreach ($format in @('yyyy-MM-dd', 'yyyyMMdd')) {
        try {
            return [datetime]::ParseExact($Value, $format, $culture)
        } catch {}
    }

    try {
        return [datetime]::Parse($Value, $culture)
    } catch {}

    throw "Invalid $ParameterName '$Value'. Use yyyy-MM-dd, yyyyMMdd, or another PowerShell-parseable date."
}

function ConvertTo-LocalDate([long]$TimestampMs) {
    return [DateTimeOffset]::FromUnixTimeMilliseconds($TimestampMs).ToLocalTime().ToString('yyyy-MM-dd')
}

function Get-ProjectName([string]$Cwd) {
    if (-not $Cwd) { return '(none)' }
    return Split-Path $Cwd -Leaf
}

function Format-Cost([double]$Cost) {
    if ($Cost -eq 0) { return '$0.00' }
    if ($Cost -lt 0.01) { return '$' + $Cost.ToString('N4') }
    return '$' + $Cost.ToString('N2')
}

function Get-CacheSavings([long]$CacheWriteTokens, [long]$CacheReadTokens, [string]$Model) {
    $pricing = Get-Pricing $Model
    $gross = ($CacheReadTokens * ($pricing.Input - $pricing.CacheRead)) / 1e6
    $net = $gross - (($CacheWriteTokens * ($pricing.CacheWrite - $pricing.Input)) / 1e6)
    return [math]::Round($net, 4)
}

function Normalize-ProviderName([string]$Provider) {
    if (-not $Provider) { return 'Unknown' }
    switch ($Provider.ToLower()) {
        'openai'    { return 'OpenAI' }
        'anthropic' { return 'Anthropic' }
        default     { return $Provider }
    }
}

function Get-ClaudeDesktopLocalAgentDir {
    if ($IsMacOS_) {
        return Join-Path $Home_ 'Library/Application Support/Claude/local-agent-mode-sessions'
    }
    if ($IsWindows_) {
        return Join-Path $env:APPDATA 'Claude/local-agent-mode-sessions'
    }
    return Join-Path $Home_ '.claude/local-agent-mode-sessions'
}

function Get-ClaudeDesktopMode([string]$Cwd) {
    if ($Cwd -and $Cwd -match '^/sessions/[^/]+$') { return 'Cowork' }
    return 'Code'
}

function Get-SessionLabel([string]$Cwd) {
    if (-not $Cwd) { return '(unknown)' }
    if ($Cwd -match '^/sessions/([^/]+)$') { return $Matches[1] }
    return Get-ProjectName $Cwd
}

function Get-McpServerName([string]$ToolName) {
    if (-not $ToolName -or -not $ToolName.StartsWith('mcp__')) { return $null }
    $rest = $ToolName.Substring(5)
    $idx = $rest.IndexOf('__')
    if ($idx -le 0) { return $null }
    return $rest.Substring(0, $idx)
}

function Get-SkillNameFromToolInput($InputObject) {
    if (-not $InputObject) { return $null }

    foreach ($prop in @('skill_name', 'skillName', 'name', 'command', 'path')) {
        if ($InputObject.PSObject.Properties[$prop]) {
            $value = [string]$InputObject.$prop
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            if ($value -match '[\\/](?:skills|Skills)[\\/]+([^\\/]+)[\\/]SKILL\.md') { return $Matches[1] }
            if ($value -match '^[A-Za-z0-9._-]+$') { return $value }
        }
    }

    return '(Skill)'
}

function Get-AttributionValues([string]$Dimension, [System.Collections.Generic.List[object]]$ToolUses) {
    $values = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($toolUse in $ToolUses) {
        $toolName = [string]$toolUse.Name
        switch ($Dimension) {
            'Tool' {
                if ($toolName) { [void]$values.Add($toolName) }
            }
            'McpServer' {
                $serverName = Get-McpServerName $toolName
                if ($serverName) { [void]$values.Add($serverName) }
            }
            'Skill' {
                if ($toolName -eq 'Skill') {
                    $skillName = Get-SkillNameFromToolInput $toolUse.Input
                    if ($skillName) { [void]$values.Add($skillName) }
                }
            }
        }
    }

    if ($values.Count -gt 0) { return @($values) }

    switch ($Dimension) {
        'Tool'      { return @('(No tool calls)') }
        'McpServer' { return @('(No MCP calls)') }
        'Skill'     { return @('(No skill calls)') }
    }
    return @('(Unknown)')
}

function Get-EstimatedAttributionRecords([string]$Dimension) {
    $records = [System.Collections.Generic.List[object]]::new()
    $baseDir = Get-ClaudeDesktopLocalAgentDir
    if (-not (Test-Path $baseDir)) { return $records }

    foreach ($file in (Get-ChildItem -Path $baseDir -Recurse -File -Filter 'audit.jsonl' -ErrorAction SilentlyContinue)) {
        $cwd = $null
        $model = 'unknown'
        $pendingToolUses = [System.Collections.Generic.List[object]]::new()

        foreach ($line in (Get-Content -Path $file.FullName -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $entry = $line | ConvertFrom-Json } catch { continue }

            if ($entry.type -eq 'system' -and $entry.subtype -eq 'init') {
                if ($entry.cwd) { $cwd = [string]$entry.cwd }
                if ($entry.model) { $model = [string]$entry.model }
                continue
            }

            if ($entry.type -eq 'assistant' -and $entry.message -and $entry.message.content) {
                if ($entry.message.model) { $model = [string]$entry.message.model }
                foreach ($contentItem in @($entry.message.content)) {
                    if ($contentItem.type -eq 'tool_use') {
                        $pendingToolUses.Add([PSCustomObject]@{
                            Name = [string]$contentItem.name
                            Input = $contentItem.input
                        })
                    }
                }
                continue
            }

            if ($entry.type -ne 'result' -or -not $entry.usage) { continue }

            $usage = $entry.usage
            [double]$turnCost = if ($entry.total_cost_usd) { [double]$entry.total_cost_usd } else { 0.0 }
            [long]$inputTokens = if ($usage.input_tokens) { [long]$usage.input_tokens } else { 0 }
            [long]$outputTokens = if ($usage.output_tokens) { [long]$usage.output_tokens } else { 0 }
            [long]$cacheWriteTokens = if ($usage.cache_creation_input_tokens) { [long]$usage.cache_creation_input_tokens } else { 0 }
            [long]$cacheReadTokens = if ($usage.cache_read_input_tokens) { [long]$usage.cache_read_input_tokens } else { 0 }
            if ($turnCost -eq 0) {
                $pricing = Get-Pricing $model
                $turnCost = ($inputTokens * $pricing.Input + $outputTokens * $pricing.Output + $cacheWriteTokens * $pricing.CacheWrite + $cacheReadTokens * $pricing.CacheRead) / 1e6
            }

            $dateSource = if ($entry._audit_timestamp) { $entry._audit_timestamp } elseif ($entry.timestamp) { $entry.timestamp } else { $null }
            $tsMs = Parse-Timestamp $dateSource
            if (-not $tsMs) { continue }
            $date = ConvertTo-LocalDate $tsMs

            $attributions = @(Get-AttributionValues -Dimension $Dimension -ToolUses $pendingToolUses)
            if ($attributions.Count -eq 0) { $attributions = @('(Unknown)') }
            $share = [double]$attributions.Count

            foreach ($attr in $attributions) {
                $records.Add([PSCustomObject]@{
                    Date = $date
                    Tool = "Claude Desktop ($(Get-ClaudeDesktopMode $cwd))"
                    Session = Get-SessionLabel $cwd
                    AttributionType = $Dimension
                    Attribution = $attr
                    Model = $model
                    SourceFile = $file.FullName
                    Turns = 1
                    InputTokens = [math]::Round($inputTokens / $share, 2)
                    OutputTokens = [math]::Round($outputTokens / $share, 2)
                    CacheWrite = [math]::Round($cacheWriteTokens / $share, 2)
                    CacheRead = [math]::Round($cacheReadTokens / $share, 2)
                    CacheSavings = [math]::Round((Get-CacheSavings -CacheWriteTokens $cacheWriteTokens -CacheReadTokens $cacheReadTokens -Model $model) / $share, 4)
                    Cost = [math]::Round($turnCost / $share, 4)
                })
            }

            $pendingToolUses = [System.Collections.Generic.List[object]]::new()
        }
    }

    return $records
}

# ─── Parsers ─────────────────────────────────────────────
# All parsers bucket by (date, model) within a source file so each
# usage bucket has a specific model for per-model sub-rows.

function Parse-ClaudeCodeFormat([string]$FilePath) {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $fallbackDate = $null
    try { $fallbackDate = (Get-Item $FilePath).LastWriteTime.ToString('yyyy-MM-dd') } catch {}
    $cwd = $null
    $entrypoint = $null
    $lastModel = 'unknown'

    # First pass: deduplicate by message ID (streaming writes multiple entries
    # per message — keep the last one which has final token counts)
    $deduped = [System.Collections.Generic.List[hashtable]]::new()
    $idIndex = @{}  # message ID → index in $deduped

    foreach ($line in [System.IO.File]::ReadLines($FilePath)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json } catch { continue }

        $msg = $entry.message
        $usage = if ($msg -and $msg.usage) { $msg.usage } elseif ($entry.usage) { $entry.usage } else { $null }
        if (-not $cwd -and $entry.cwd) { $cwd = $entry.cwd }
        if (-not $entrypoint -and $entry.entrypoint) { $entrypoint = $entry.entrypoint }
        if (-not $usage) { continue }

        $inputTok   = if ($usage.input_tokens)                { [long]$usage.input_tokens } else { 0 }
        $outputTok  = if ($usage.output_tokens)               { [long]$usage.output_tokens } else { 0 }
        $cacheWrite = if ($usage.cache_creation_input_tokens) { [long]$usage.cache_creation_input_tokens } else { 0 }
        $cacheRead  = if ($usage.cache_read_input_tokens)     { [long]$usage.cache_read_input_tokens } else { 0 }
        if ($inputTok -eq 0 -and $outputTok -eq 0 -and $cacheRead -eq 0 -and $cacheWrite -eq 0) { continue }

        $tsMs = Parse-Timestamp $(if ($entry.timestamp) { $entry.timestamp } elseif ($msg -and $msg.timestamp) { $msg.timestamp } else { $null })
        $date = if ($tsMs) { ConvertTo-LocalDate $tsMs } else { $fallbackDate }
        if (-not $date) { continue }

        $rawModel = if ($msg -and $msg.model) { $msg.model } elseif ($entry.model) { $entry.model } else { '' }
        if ($rawModel) { $lastModel = $rawModel }
        $model = if ($rawModel) { $rawModel } else { $lastModel }

        $rec = @{ Date = $date; Model = $model; In = $inputTok; Out = $outputTok; CW = $cacheWrite; CR = $cacheRead }

        # Deduplicate: if this message ID was seen before, replace it
        $msgId = if ($msg -and $msg.id) { $msg.id } else { $null }
        if ($msgId -and $idIndex.ContainsKey($msgId)) {
            $deduped[$idIndex[$msgId]] = $rec
        } else {
            if ($msgId) { $idIndex[$msgId] = $deduped.Count }
            $deduped.Add($rec)
        }
    }

    # Second pass: aggregate deduped entries into (date, model) buckets
    $buckets = @{}
    foreach ($rec in $deduped) {
        $key = "$($rec.Date)|$($rec.Model)"
        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = @{ Cost = 0.0; In = [long]0; Out = [long]0; CR = [long]0; CW = [long]0 }
        }
        $b = $buckets[$key]
        $pricing = Get-Pricing $rec.Model
        $b.Cost += ($rec.In * $pricing.Input + $rec.Out * $pricing.Output + $rec.CW * $pricing.CacheWrite + $rec.CR * $pricing.CacheRead) / 1e6
        $b.In += $rec.In; $b.Out += $rec.Out; $b.CR += $rec.CR; $b.CW += $rec.CW
    }

    foreach ($key in $buckets.Keys) {
        $b = $buckets[$key]
        if ($b.Cost -lt 0.0001) { continue }
        $parts = $key -split '\|', 2
        $sessions.Add([PSCustomObject]@{
            Date = $parts[0]; Model = $parts[1]; Project = Get-ProjectName $cwd
            Entrypoint = $entrypoint
            WorkingDirectory = $cwd
            SourceFile = $FilePath
            Cost = [math]::Round($b.Cost, 4)
            InputTokens = $b.In; OutputTokens = $b.Out
            CacheRead = $b.CR; CacheWrite = $b.CW
            CacheSavings = Get-CacheSavings -CacheWriteTokens $b.CW -CacheReadTokens $b.CR -Model $parts[1]
        })
    }
    return $sessions
}

function Parse-AiderFormat([string]$FilePath) {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $buckets = @{}
    $fallbackDate = $null
    try { $fallbackDate = (Get-Item $FilePath).LastWriteTime.ToString('yyyy-MM-dd') } catch {}

    foreach ($line in [System.IO.File]::ReadLines($FilePath)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json } catch { continue }

        $usage = if ($entry.usage) { $entry.usage } elseif ($entry.response -and $entry.response.usage) { $entry.response.usage } else { $null }
        if (-not $usage) { continue }

        $inputTok   = if ($usage.prompt_tokens)    { [long]$usage.prompt_tokens }
                      elseif ($usage.input_tokens)  { [long]$usage.input_tokens } else { 0 }
        $outputTok  = if ($usage.completion_tokens) { [long]$usage.completion_tokens }
                      elseif ($usage.output_tokens)  { [long]$usage.output_tokens } else { 0 }
        $cacheRead  = if ($usage.cache_read_input_tokens)     { [long]$usage.cache_read_input_tokens } else { 0 }
        $cacheWrite = if ($usage.cache_creation_input_tokens) { [long]$usage.cache_creation_input_tokens } else { 0 }
        if ($inputTok -eq 0 -and $outputTok -eq 0) { continue }

        $tsRaw = if ($entry.timestamp) { $entry.timestamp } elseif ($entry.created) { $entry.created } else { $null }
        if ($tsRaw -is [long] -or $tsRaw -is [int] -or $tsRaw -is [double]) {
            if ($tsRaw -lt 2000000000) { $tsRaw = $tsRaw * 1000 }
        }
        $tsMs = Parse-Timestamp $tsRaw
        $date = if ($tsMs) { ConvertTo-LocalDate $tsMs } else { $fallbackDate }
        if (-not $date) { continue }

        $model = if ($entry.model) { $entry.model } else { 'unknown' }

        $key = "${date}|${model}"
        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = @{ Cost = 0.0; In = 0; Out = 0; CR = 0; CW = 0 }
        }
        $b = $buckets[$key]
        $pricing = Get-Pricing $model
        $b.Cost += ($inputTok * $pricing.Input + $outputTok * $pricing.Output + $cacheWrite * $pricing.CacheWrite + $cacheRead * $pricing.CacheRead) / 1e6
        $b.In += $inputTok; $b.Out += $outputTok; $b.CR += $cacheRead; $b.CW += $cacheWrite
    }

    foreach ($key in $buckets.Keys) {
        $b = $buckets[$key]
        if ($b.Cost -lt 0.0001) { continue }
        $parts = $key -split '\|', 2
        $sessions.Add([PSCustomObject]@{
            Date = $parts[0]; Model = $parts[1]; Project = '(none)'
            SourceFile = $FilePath
            Cost = [math]::Round($b.Cost, 4)
            InputTokens = $b.In; OutputTokens = $b.Out
            CacheRead = $b.CR; CacheWrite = $b.CW
            CacheSavings = Get-CacheSavings -CacheWriteTokens $b.CW -CacheReadTokens $b.CR -Model $parts[1]
        })
    }
    return $sessions
}

function Parse-ContinueFormat([string]$FilePath) {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $buckets = @{}
    try { $data = Get-Content $FilePath -Raw | ConvertFrom-Json } catch { return $sessions }

    $steps = if ($data.steps) { $data.steps } elseif ($data.history) { $data.history } else { @() }
    $fallbackDate = $null
    try { $fallbackDate = (Get-Item $FilePath).LastWriteTime.ToString('yyyy-MM-dd') } catch {}

    foreach ($step in $steps) {
        $inputTok  = if ($step.promptTokens)     { [long]$step.promptTokens } else { 0 }
        $outputTok = if ($step.completionTokens) { [long]$step.completionTokens } else { 0 }
        if ($step.usage) {
            if ($step.usage.input_tokens)  { $inputTok  = [long]$step.usage.input_tokens }
            if ($step.usage.output_tokens) { $outputTok = [long]$step.usage.output_tokens }
        }
        if ($inputTok -eq 0 -and $outputTok -eq 0) { continue }

        $tsMs = Parse-Timestamp $(if ($step.timestamp) { $step.timestamp } elseif ($data.dateCreated) { $data.dateCreated } else { $null })
        $date = if ($tsMs) { ConvertTo-LocalDate $tsMs } else { $fallbackDate }
        if (-not $date) { continue }

        $model = if ($step.model) { $step.model } elseif ($data.model) { $data.model } else { 'unknown' }

        $key = "${date}|${model}"
        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = @{ Cost = 0.0; In = 0; Out = 0; CR = 0; CW = 0 }
        }
        $b = $buckets[$key]
        $pricing = Get-Pricing $model
        $b.Cost += ($inputTok * $pricing.Input + $outputTok * $pricing.Output) / 1e6
        $b.In += $inputTok; $b.Out += $outputTok
    }

    foreach ($key in $buckets.Keys) {
        $b = $buckets[$key]
        if ($b.Cost -lt 0.0001) { continue }
        $parts = $key -split '\|', 2
        $sessions.Add([PSCustomObject]@{
            Date = $parts[0]; Model = $parts[1]; Project = '(none)'
            SourceFile = $FilePath
            Cost = [math]::Round($b.Cost, 4)
            InputTokens = $b.In; OutputTokens = $b.Out
            CacheRead = $b.CR; CacheWrite = $b.CW
            CacheSavings = Get-CacheSavings -CacheWriteTokens $b.CW -CacheReadTokens $b.CR -Model $parts[1]
        })
    }
    return $sessions
}

function Parse-CodexFormat([string]$FilePath) {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $fallbackDate = $null
    try { $fallbackDate = (Get-Item $FilePath).LastWriteTime.ToString('yyyy-MM-dd') } catch {}

    $cwd = $null
    $originator = $null
    $source = $null
    $provider = 'OpenAI'
    $model = 'unknown'
    $sessionDate = $null
    $latestUsage = $null

    foreach ($line in (Get-Content -Path $FilePath -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json } catch { continue }

        switch ($entry.type) {
            'session_meta' {
                $payload = $entry.payload
                if (-not $cwd -and $payload.cwd) { $cwd = $payload.cwd }
                if (-not $originator -and $payload.originator) { $originator = $payload.originator }
                if (-not $source -and $payload.source) { $source = $payload.source }
                if ($payload.model_provider) { $provider = $payload.model_provider }
                if ($payload.timestamp) {
                    $tsMs = Parse-Timestamp $payload.timestamp
                    if ($tsMs) { $sessionDate = ConvertTo-LocalDate $tsMs }
                }
            }
            'turn_context' {
                $payload = $entry.payload
                if (-not $cwd -and $payload.cwd) { $cwd = $payload.cwd }
                if ($payload.model) { $model = $payload.model }
            }
            'event_msg' {
                $payload = $entry.payload
                if ($payload.type -eq 'token_count' -and $payload.info -and $payload.info.total_token_usage) {
                    $latestUsage = $payload.info.total_token_usage
                }
            }
        }
    }

    if (-not $latestUsage) { return $sessions }

    [long]$inputTotal = if ($latestUsage.input_tokens) { $latestUsage.input_tokens } else { 0 }
    [long]$cachedInput = if ($latestUsage.cached_input_tokens) { $latestUsage.cached_input_tokens } else { 0 }
    [long]$outputTok = if ($latestUsage.output_tokens) { $latestUsage.output_tokens } else { 0 }
    [long]$inputTok = [Math]::Max(0, $inputTotal - $cachedInput)

    if ($inputTok -eq 0 -and $cachedInput -eq 0 -and $outputTok -eq 0) { return $sessions }

    $date = if ($sessionDate) { $sessionDate } else { $fallbackDate }
    if (-not $date) { return $sessions }

    $pricing = Get-Pricing $model
    $cost = ($inputTok * $pricing.Input + $outputTok * $pricing.Output + $cachedInput * $pricing.CacheRead) / 1e6
    $cacheSavings = Get-CacheSavings -CacheWriteTokens 0 -CacheReadTokens $cachedInput -Model $model

    $sessions.Add([PSCustomObject]@{
        Date = $date
        Model = $model
        Project = Get-ProjectName $cwd
        Tool = if ($originator -eq 'codex-tui' -or $source -eq 'cli') { 'Codex' } else { 'Codex' }
        Provider = Normalize-ProviderName $provider
        SourceFile = $FilePath
        Cost = [math]::Round($cost, 4)
        InputTokens = $inputTok
        OutputTokens = $outputTok
        CacheRead = $cachedInput
        CacheWrite = [long]0
        CacheSavings = $cacheSavings
    })

    return $sessions
}

function Resolve-ToolName([string]$Entrypoint, [string]$Fallback) {
    switch ($Entrypoint) {
        'cli'             { return 'Claude Code (CLI)' }
        'claude-vscode'   { return 'Claude Code (VS Code)' }
        'claude-desktop'  { return 'Claude Desktop' }
        default           { return $Fallback }
    }
}

function Resolve-ClaudeDesktopTool([object]$Session) {
    $cwd = if ($Session.PSObject.Properties['SourceFile']) { $null } else { $null }
    if ($Session.PSObject.Properties['WorkingDirectory']) { $cwd = [string]$Session.WorkingDirectory }
    $project = if ($Session.PSObject.Properties['Project']) { [string]$Session.Project } else { '' }

    if ($cwd -and $cwd -match '^/sessions/[^/]+$') {
        return 'Claude Desktop (Cowork)'
    }

    if ($project -and $project -ne '(none)') {
        return 'Claude Desktop (Code)'
    }

    return 'Claude Desktop'
}

# ─── Source Collectors ───────────────────────────────────

function Collect-ClaudeCode {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $claudeDir = Join-Path $Home_ '.claude/projects'
    if (-not (Test-Path $claudeDir)) { return $sessions }
    foreach ($filePath in (Find-JsonlFiles $claudeDir)) {
        foreach ($s in (Parse-ClaudeCodeFormat $filePath)) {
            if ($s.Entrypoint -eq 'claude-desktop') {
                $toolName = 'Claude Desktop (Code)'
            }
            else {
                $toolName = Resolve-ToolName $s.Entrypoint 'Claude Code'
            }
            $s | Add-Member -NotePropertyName Tool -NotePropertyValue $toolName -Force
            $s | Add-Member -NotePropertyName Provider -NotePropertyValue 'Anthropic' -Force
            $sessions.Add($s)
        }
    }
    return $sessions
}

function Collect-ClaudeDesktop {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $baseDir = if ($IsMacOS_) {
        Join-Path $Home_ 'Library/Application Support/Claude/local-agent-mode-sessions'
    } elseif ($IsWindows_) {
        Join-Path $env:APPDATA 'Claude/local-agent-mode-sessions'
    } else {
        Join-Path $Home_ '.claude/local-agent-mode-sessions'
    }
    if (-not (Test-Path $baseDir)) { return $sessions }
    foreach ($filePath in (Find-JsonlFiles $baseDir)) {
        foreach ($s in (Parse-ClaudeCodeFormat $filePath)) {
            $toolName = Resolve-ClaudeDesktopTool $s
            $s | Add-Member -NotePropertyName Tool -NotePropertyValue $toolName -Force
            $s | Add-Member -NotePropertyName Provider -NotePropertyValue 'Anthropic' -Force
            $sessions.Add($s)
        }
    }
    return $sessions
}

function Collect-Cursor {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $searchDirs = @((Join-Path $Home_ '.cursor/projects'))
    if ($IsMacOS_)   { $searchDirs += Join-Path $Home_ 'Library/Application Support/Cursor/User/workspaceStorage' }
    elseif ($IsWindows_) { $searchDirs += Join-Path $env:APPDATA 'Cursor/User/workspaceStorage' }
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($filePath in (Find-JsonlFiles $dir)) {
            foreach ($s in (Parse-ClaudeCodeFormat $filePath)) {
                $s | Add-Member -NotePropertyName Tool -NotePropertyValue 'Cursor' -Force
                $s | Add-Member -NotePropertyName Provider -NotePropertyValue 'Anthropic' -Force
                $sessions.Add($s)
            }
        }
    }
    return $sessions
}

function Collect-Windsurf {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $searchDirs = @((Join-Path $Home_ '.windsurf/projects'), (Join-Path $Home_ '.windsurf'))
    $seenFiles = @{}
    if ($IsMacOS_)   { $searchDirs += Join-Path $Home_ 'Library/Application Support/Windsurf/User/workspaceStorage' }
    elseif ($IsWindows_) { $searchDirs += Join-Path $env:APPDATA 'Windsurf/User/workspaceStorage' }
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($filePath in (Find-JsonlFiles $dir)) {
            if ($seenFiles.ContainsKey($filePath)) { continue }
            $seenFiles[$filePath] = $true
            foreach ($s in (Parse-ClaudeCodeFormat $filePath)) {
                $s | Add-Member -NotePropertyName Tool -NotePropertyValue 'Windsurf' -Force
                $s | Add-Member -NotePropertyName Provider -NotePropertyValue 'Anthropic' -Force
                $sessions.Add($s)
            }
        }
    }
    return $sessions
}

function Collect-Cline {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $searchDirs = @((Join-Path $Home_ '.cline'))
    if ($IsMacOS_) {
        $searchDirs += Join-Path $Home_ 'Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev'
        $searchDirs += Join-Path $Home_ 'Library/Application Support/Code/User/globalStorage/cline.cline'
    } elseif ($IsWindows_) {
        $searchDirs += Join-Path $env:APPDATA 'Code/User/globalStorage/saoudrizwan.claude-dev'
        $searchDirs += Join-Path $env:APPDATA 'Code/User/globalStorage/cline.cline'
    }
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($filePath in (Find-JsonlFiles $dir)) {
            foreach ($s in (Parse-ClaudeCodeFormat $filePath)) {
                $s | Add-Member -NotePropertyName Tool -NotePropertyValue 'Cline' -Force
                $s | Add-Member -NotePropertyName Provider -NotePropertyValue 'Anthropic' -Force
                $sessions.Add($s)
            }
        }
    }
    return $sessions
}

function Collect-RooCode {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $searchDirs = @((Join-Path $Home_ '.roo-code'))
    if ($IsMacOS_)   { $searchDirs += Join-Path $Home_ 'Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline' }
    elseif ($IsWindows_) { $searchDirs += Join-Path $env:APPDATA 'Code/User/globalStorage/rooveterinaryinc.roo-cline' }
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($filePath in (Find-JsonlFiles $dir)) {
            foreach ($s in (Parse-ClaudeCodeFormat $filePath)) {
                $s | Add-Member -NotePropertyName Tool -NotePropertyValue 'Roo Code' -Force
                $s | Add-Member -NotePropertyName Provider -NotePropertyValue 'Anthropic' -Force
                $sessions.Add($s)
            }
        }
    }
    return $sessions
}

function Collect-Aider {
    $sessions = [System.Collections.Generic.List[object]]::new()
    foreach ($dir in @((Join-Path $Home_ '.aider'), (Join-Path $Home_ '.aider/logs'))) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($file in (Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.jsonl', '.json' })) {
            foreach ($s in (Parse-AiderFormat $file.FullName)) {
                $s | Add-Member -NotePropertyName Tool -NotePropertyValue 'Aider' -Force
                $s | Add-Member -NotePropertyName Provider -NotePropertyValue 'Anthropic' -Force
                $sessions.Add($s)
            }
        }
    }
    return $sessions
}

function Collect-Continue {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $sessDir = Join-Path $Home_ '.continue/sessions'
    if (-not (Test-Path $sessDir)) { return $sessions }
    foreach ($file in (Get-ChildItem -Path $sessDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
        foreach ($s in (Parse-ContinueFormat $file.FullName)) {
            $s | Add-Member -NotePropertyName Tool -NotePropertyValue 'Continue' -Force
            $s | Add-Member -NotePropertyName Provider -NotePropertyValue 'Anthropic' -Force
            $sessions.Add($s)
        }
    }
    return $sessions
}

function Collect-Codex {
    $sessions = [System.Collections.Generic.List[object]]::new()
    $sessDir = Join-Path $Home_ '.codex/sessions'
    if (-not (Test-Path $sessDir)) { return $sessions }
    foreach ($file in (Get-ChildItem -Path $sessDir -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue)) {
        foreach ($s in (Parse-CodexFormat $file.FullName)) {
            $sessions.Add($s)
        }
    }
    return $sessions
}

# ─── Box Table Renderer ─────────────────────────────────

function Write-BoxTable {
    param(
        [string[][]]$Headers,   # Array of header-line arrays (for multi-line headers)
        [string[]]$Aligns,      # 'L' or 'R' per column
        [array]$Rows            # Array of string[] cell arrays (cells may contain `n)
    )

    $nCols = $Aligns.Count
    $w = [int[]]::new($nCols)

    # Calculate column widths from headers
    foreach ($h in $Headers) {
        for ($i = 0; $i -lt $nCols; $i++) {
            if ($h[$i].Length -gt $w[$i]) { $w[$i] = $h[$i].Length }
        }
    }
    # Calculate column widths from data cells
    foreach ($row in $Rows) {
        for ($i = 0; $i -lt $nCols; $i++) {
            foreach ($ln in ($row[$i] -split "`n")) {
                if ($ln.Length -gt $w[$i]) { $w[$i] = $ln.Length }
            }
        }
    }

    # Pre-build the three horizontal line styles
    $segs = @(for ($i = 0; $i -lt $nCols; $i++) { [string]('─' * ($w[$i] + 2)) })
    $topLine = '┌' + ($segs -join '┬') + '┐'
    $midLine = '├' + ($segs -join '┼') + '┤'
    $botLine = '└' + ($segs -join '┴') + '┘'

    # Helper: render one physical line of cells
    function RenderLine([string[]]$cells) {
        $sb = [System.Text.StringBuilder]::new('│')
        for ($ci = 0; $ci -lt $cells.Count; $ci++) {
            $text = $cells[$ci]
            if ($Aligns[$ci] -eq 'R') {
                [void]$sb.Append(' ').Append($text.PadLeft($w[$ci])).Append(' │')
            } else {
                [void]$sb.Append(' ').Append($text.PadRight($w[$ci])).Append(' │')
            }
        }
        Write-Host $sb.ToString()
    }

    # ─ Render table ─
    Write-Host $topLine

    # Header lines
    foreach ($h in $Headers) { RenderLine $h }
    Write-Host $midLine

    # Data rows
    for ($ri = 0; $ri -lt $Rows.Count; $ri++) {
        $row = $Rows[$ri]
        # Split each cell into lines
        $cellLines = [System.Collections.Generic.List[string[]]]::new()
        $maxLn = 1
        for ($i = 0; $i -lt $nCols; $i++) {
            $lines = @($row[$i] -split "`n")
            $cellLines.Add($lines)
            if ($lines.Count -gt $maxLn) { $maxLn = $lines.Count }
        }
        # Render each physical line
        for ($ln = 0; $ln -lt $maxLn; $ln++) {
            $lineCells = @(for ($i = 0; $i -lt $nCols; $i++) {
                if ($ln -lt $cellLines[$i].Count) { $cellLines[$i][$ln] } else { '' }
            })
            RenderLine $lineCells
        }
        # Separator between rows (not after last)
        if ($ri -lt $Rows.Count - 1) { Write-Host $midLine }
    }

    Write-Host $botLine
}

# ─── Main ────────────────────────────────────────────────

$collectors = @(
    @{ Name = 'Claude Code CLI';     Fn = 'Collect-ClaudeCode' }
    @{ Name = 'Claude Desktop';      Fn = 'Collect-ClaudeDesktop' }
    @{ Name = 'Codex';               Fn = 'Collect-Codex' }
    @{ Name = 'Cursor';              Fn = 'Collect-Cursor' }
    @{ Name = 'Windsurf';            Fn = 'Collect-Windsurf' }
    @{ Name = 'Cline';               Fn = 'Collect-Cline' }
    @{ Name = 'Roo Code';            Fn = 'Collect-RooCode' }
    @{ Name = 'Aider';               Fn = 'Collect-Aider' }
    @{ Name = 'Continue.dev';        Fn = 'Collect-Continue' }
)

$allSessions = [System.Collections.Generic.List[object]]::new()

foreach ($c in $collectors) {
    $result = & $c.Fn
    if ($result.Count -gt 0) {
        Write-Host "  $($c.Name): $($result.Count) entries" -ForegroundColor Green
        foreach ($s in $result) { $allSessions.Add($s) }
    } else {
        Write-Host "  $($c.Name): not found" -ForegroundColor DarkGray
    }
}

Write-Host ''

if ($allSessions.Count -eq 0) {
    Write-Host 'No AI usage data found.' -ForegroundColor Yellow
    return
}

if ($EstimateAttribution) {
    $estimated = @(Get-EstimatedAttributionRecords -Dimension $AttributionBy)
    if ($estimated.Count -eq 0) {
        Write-Host "No estimated attribution data found for $AttributionBy." -ForegroundColor Yellow
        return
    }

    $resolvedStartDate = if ($PSBoundParameters.ContainsKey('StartDate')) { Resolve-DateFilter $StartDate 'StartDate' } else { $null }
    $resolvedEndDate   = if ($PSBoundParameters.ContainsKey('EndDate'))   { Resolve-DateFilter $EndDate 'EndDate' }   else { $null }

    if ($PSBoundParameters.ContainsKey('StartDate') -or $PSBoundParameters.ContainsKey('EndDate')) {
        if ($PSBoundParameters.ContainsKey('StartDate')) {
            $startStr = $resolvedStartDate.ToString('yyyy-MM-dd')
            $estimated = @($estimated | Where-Object { $_.Date -ge $startStr })
        }
        if ($PSBoundParameters.ContainsKey('EndDate')) {
            $endStr = $resolvedEndDate.ToString('yyyy-MM-dd')
            $estimated = @($estimated | Where-Object { $_.Date -le $endStr })
        }
    } elseif ($Days -gt 0) {
        $cutoff = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd')
        $estimated = @($estimated | Where-Object { $_.Date -ge $cutoff })
    }

    if ($Source) {
        $estimated = @($estimated | Where-Object { $_.Tool -like $Source })
    }

    if ($Raw) {
        return $estimated | Sort-Object Date, Tool, Session, Attribution
    }

    $agg = @{}
    foreach ($row in $estimated) {
        $key = "$($row.Date)|$($row.Tool)|$($row.Attribution)"
        if (-not $agg.ContainsKey($key)) {
            $agg[$key] = @{
                Date = $row.Date
                Tool = $row.Tool
                Attribution = $row.Attribution
                Turns = 0
                Input = 0.0
                Output = 0.0
                CacheWrite = 0.0
                CacheRead = 0.0
                CacheSavings = 0.0
                Cost = 0.0
            }
        }
        $a = $agg[$key]
        $a.Turns += [int]$row.Turns
        $a.Input += [double]$row.InputTokens
        $a.Output += [double]$row.OutputTokens
        $a.CacheWrite += [double]$row.CacheWrite
        $a.CacheRead += [double]$row.CacheRead
        $a.CacheSavings += [double]$row.CacheSavings
        $a.Cost += [double]$row.Cost
    }

    $aggList = @($agg.Values | Where-Object { $_.Cost -ge $MinCost })
    if ($aggList.Count -eq 0) {
        Write-Host 'No estimated attribution buckets match the current filters.' -ForegroundColor Yellow
        return
    }

    if ($Top -gt 0 -and $aggList.Count -gt $Top) {
        $aggList = @($aggList | Sort-Object { -$_.Cost } | Select-Object -First $Top)
    }

    $sorted = @($aggList | Sort-Object Date, Tool, Attribution)
    $attrLabel = switch ($AttributionBy) {
        'Tool' { 'Attributed Tool' }
        'McpServer' { 'MCP Server' }
        'Skill' { 'Skill' }
        default { $AttributionBy }
    }
    $displayRows = foreach ($row in $sorted) {
        [PSCustomObject]@{
            Date = $row.Date
            Tool = $row.Tool
            $attrLabel = $row.Attribution
            Turns = $row.Turns
            'Est Input' = [math]::Round($row.Input, 2)
            'Est Output' = [math]::Round($row.Output, 2)
            'Est Cache Create' = [math]::Round($row.CacheWrite, 2)
            'Est Cache Read' = [math]::Round($row.CacheRead, 2)
            'Est Cache Savings' = Format-Cost $row.CacheSavings
            'Est Cost (USD)' = Format-Cost $row.Cost
        }
    }

    Write-Host "Experimental Attribution Report - by Date, Tool, $AttributionBy" -ForegroundColor Cyan
    Write-Host ''
    $displayRows | Format-Table -AutoSize | Out-Host
    Write-Host ''
    Write-Host 'Notes:' -ForegroundColor DarkGray
    Write-Host "  This attribution is estimated by splitting each Claude Desktop local-agent turn across the $AttributionBy values used in that turn." -ForegroundColor DarkGray
    Write-Host '  These numbers are useful for directionally understanding usage, not for authoritative billing.' -ForegroundColor DarkGray
    return
}

# ─── Filter ──────────────────────────────────────────────

$filtered = $allSessions
$resolvedStartDate = if ($PSBoundParameters.ContainsKey('StartDate')) { Resolve-DateFilter $StartDate 'StartDate' } else { $null }
$resolvedEndDate   = if ($PSBoundParameters.ContainsKey('EndDate'))   { Resolve-DateFilter $EndDate 'EndDate' }   else { $null }

if ($PSBoundParameters.ContainsKey('StartDate') -or $PSBoundParameters.ContainsKey('EndDate')) {
    if ($PSBoundParameters.ContainsKey('StartDate')) {
        $startStr = $resolvedStartDate.ToString('yyyy-MM-dd')
        $filtered = $filtered | Where-Object { $_.Date -ge $startStr }
    }
    if ($PSBoundParameters.ContainsKey('EndDate')) {
        $endStr = $resolvedEndDate.ToString('yyyy-MM-dd')
        $filtered = $filtered | Where-Object { $_.Date -le $endStr }
    }
} elseif ($Days -gt 0) {
    $cutoff = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd')
    $filtered = $filtered | Where-Object { $_.Date -ge $cutoff }
}

if ($Source) {
    $filtered = $filtered | Where-Object { $_.Tool -like $Source }
}

# ─── Raw mode ────────────────────────────────────────────

if ($Raw) {
    $filtered = @($filtered | Where-Object { $_.Cost -ge $MinCost })
    if ($filtered.Count -eq 0) {
        Write-Host 'No usage buckets match the current filters.' -ForegroundColor Yellow
        return
    }
    return $filtered | Sort-Object Date, Provider, Tool, Model, Project
}

# ─── Build table data ────────────────────────────────────

# Aggregate by GroupBy fields only — non-specified dimensions are collapsed
$agg = @{}
foreach ($s in $filtered) {
    $keyParts = foreach ($g in $GroupBy) {
        switch ($g) {
            'Date'    { $s.Date }
            'Model'   { $s.Model }
            'Tool'    { $s.Tool }
            'Project' { $s.Project }
            'Provider' { $s.Provider }
        }
    }
    $key = $keyParts -join '|'
    if (-not $agg.ContainsKey($key)) {
        $fields = @{}
        foreach ($g in $GroupBy) {
            switch ($g) {
                'Date'    { $fields.Date    = $s.Date }
                'Model'   { $fields.Model   = $s.Model }
                'Tool'    { $fields.Tool    = $s.Tool }
                'Project' { $fields.Project = $s.Project }
                'Provider' { $fields.Provider = $s.Provider }
            }
        }
        $agg[$key] = @{
            Fields = $fields
            Cost = 0.0; In = [long]0; Out = [long]0; CR = [long]0; CW = [long]0
            CacheSavings = 0.0
        }
    }
    $a = $agg[$key]
    $a.Cost += $s.Cost
    $a.In   += $s.InputTokens; $a.Out += $s.OutputTokens
    $a.CR   += $s.CacheRead;   $a.CW  += $s.CacheWrite
    $a.CacheSavings += $s.CacheSavings
}

$aggList = @($agg.Values)

# Apply -MinCost after grouping so small source buckets can still contribute
# to a grouped row when they sum to something meaningful.
$aggList = @($aggList | Where-Object { $_.Cost -ge $MinCost })

if ($aggList.Count -eq 0) {
    Write-Host 'No usage buckets match the current filters.' -ForegroundColor Yellow
    return
}

# Apply -Top: keep only the N most expensive rows
if ($Top -gt 0 -and $aggList.Count -gt $Top) {
    $aggList = @($aggList | Sort-Object { -$_.Cost } | Select-Object -First $Top)
}

# Sort for display: group fields ascending, then cost descending as tiebreaker
$sorted = @($aggList | Sort-Object {
    $f = $_.Fields
    $parts = foreach ($g in $GroupBy) { $f[$g] }
    $parts -join '|'
}, { -$_.Cost })

# ─── Build dynamic headers ───────────────────────────────

$headerRow1 = [System.Collections.Generic.List[string]]::new()
$headerRow2 = [System.Collections.Generic.List[string]]::new()
$aligns     = [System.Collections.Generic.List[string]]::new()

foreach ($g in $GroupBy) {
    $headerRow1.Add($g)
    $headerRow2.Add('')
    $aligns.Add('L')
}
foreach ($h in @('Input', 'Output', 'Cache',   'Cache', 'Cache',   'Cost')) { $headerRow1.Add($h) }
foreach ($h in @('',      '',       'Create',  'Read',  'Savings', '(USD)')) { $headerRow2.Add($h) }
foreach ($a in @('R',     'R',      'R',       'R',     'R',       'R'))     { $aligns.Add($a) }

# ─── Build table rows ───────────────────────────────────

$tableRows = [System.Collections.Generic.List[string[]]]::new()
[long]$gtIn = 0; [long]$gtOut = 0; [long]$gtCW = 0; [long]$gtCR = 0
[double]$gtCacheSavings = 0; [double]$gtCost = 0

foreach ($sr in $sorted) {
    $gtIn += $sr.In; $gtOut += $sr.Out; $gtCW += $sr.CW; $gtCR += $sr.CR
    $gtCacheSavings += $sr.CacheSavings; $gtCost += $sr.Cost
    $cells = [System.Collections.Generic.List[string]]::new()
    foreach ($g in $GroupBy) {
        $val = $sr.Fields[$g]
        if ($g -eq 'Model') { $val = Get-ShortModel $val }
        $cells.Add($val)
    }
    $cells.AddRange([string[]]@(
        $sr.In.ToString('N0'),
        $sr.Out.ToString('N0'),
        $sr.CW.ToString('N0'),
        $sr.CR.ToString('N0'),
        (Format-Cost $sr.CacheSavings),
        (Format-Cost $sr.Cost)
    ))
    $tableRows.Add($cells.ToArray())
}

# Total row
$totalCells = [System.Collections.Generic.List[string]]::new()
$totalCells.Add('Total')
for ($i = 1; $i -lt $GroupBy.Count; $i++) { $totalCells.Add('') }
$totalCells.AddRange([string[]]@(
    $gtIn.ToString('N0'),
    $gtOut.ToString('N0'),
    $gtCW.ToString('N0'),
    $gtCR.ToString('N0'),
    (Format-Cost $gtCacheSavings),
    (Format-Cost $gtCost)
))
$tableRows.Add($totalCells.ToArray())

# ─── Title box ───────────────────────────────────────────

$groupLabel = $GroupBy -join ', '
$title = "AI Usage Report - by $groupLabel"
if ($Top -gt 0) { $title += " (top $Top)" }
$boxW = $title.Length + 4
Write-Host ''
Write-Host (' ╭' + ('─' * $boxW) + '╮')
Write-Host (' │' + (' ' * $boxW) + '│')
Write-Host (' │  ' + $title + '  │')
Write-Host (' │' + (' ' * $boxW) + '│')
Write-Host (' ╰' + ('─' * $boxW) + '╯')
Write-Host ''

# ─── Render table ────────────────────────────────────────

$headers = @(,$headerRow1.ToArray(); ,$headerRow2.ToArray())

Write-BoxTable -Headers $headers -Aligns $aligns.ToArray() -Rows $tableRows.ToArray()

Write-Host ''
Write-Host 'Notes:' -ForegroundColor DarkGray
Write-Host '  Cost (USD) is the estimated billed cost from input, output, cache-write, and cache-read tokens.' -ForegroundColor DarkGray
Write-Host '  Cache Savings is the estimated net avoided cost from cache hits after subtracting cache-write premium.' -ForegroundColor DarkGray
Write-Host '  Codex output tokens include reasoning (thinking) tokens billed by OpenAI.' -ForegroundColor DarkGray

