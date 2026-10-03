import Foundation

/// Plan or metered, per provider, read from what each CLI leaves on disk. Overridable in settings.
public struct AccountInfo: Codable, Sendable, Equatable {
    public var kind: AccountKind
    public var planName: String?

    public init(kind: AccountKind, planName: String? = nil) {
        self.kind = kind
        self.planName = planName
    }
}

public enum AccountDetector {
    /// Claude: a login stores `oauthAccount` in `~/.claude.json`; API-key use leaves it absent.
    public static func claude(configURL: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> AccountInfo {
        if environment["ANTHROPIC_API_KEY"]?.isEmpty == false { return AccountInfo(kind: .metered) }
        guard let config = try? JSONLines.object(in: configURL),
              let account = config.dict("oauthAccount")
        else { return AccountInfo(kind: .metered) }
        // organizationType looks like "claude_max" / "claude_pro" / "claude_team" / "claude_enterprise".
        let orgType = account.string("organizationType") ?? ""
        if orgType.contains("enterprise") { return AccountInfo(kind: .metered, planName: "Enterprise") }
        let plan = account.string("subscriptionType")
            ?? (orgType.isEmpty ? nil : orgType.replacingOccurrences(of: "claude_", with: ""))
        return AccountInfo(kind: .plan, planName: claudePlanName(subscription: plan, tier: account.string("organizationRateLimitTier")))
    }

    /// "max" + "default_claude_max_20x" -> "Max 20x"; "pro" -> "Pro".
    static func claudePlanName(subscription: String?, tier: String?) -> String? {
        var name = subscription?.capitalized
        if let tier, let multiplier = tier.split(separator: "_").last, multiplier.hasSuffix("x"), multiplier.first?.isNumber == true {
            name = (name ?? "Max") + " \(multiplier)"
        }
        return name
    }

    /// Codex: rollouts carry `plan_type` next to the rate limits when logged in with ChatGPT.
    public static func codex(rateLimits: CodexRateLimits?) -> AccountInfo {
        guard let rateLimits else { return AccountInfo(kind: .metered) }
        return AccountInfo(kind: .plan, planName: rateLimits.planType)
    }

    /// Gemini CLI: `security.auth.selectedType` in `~/.gemini/settings.json`; `oauth-personal` is a Google login.
    public static func gemini(geminiHome: URL) -> AccountInfo {
        let settings = geminiHome.appendingPathComponent("settings.json")
        guard let config = try? JSONLines.object(in: settings),
              let type = config.dict("security")?.dict("auth")?.string("selectedType")
        else { return AccountInfo(kind: .plan) }
        return AccountInfo(kind: type == "oauth-personal" ? .plan : .metered)
    }
}
