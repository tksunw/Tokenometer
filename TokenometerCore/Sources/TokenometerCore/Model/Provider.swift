import Foundation

/// The account whose usage limits a record counts against. See GLOSSARY.md.
public enum Provider: String, Codable, Sendable, CaseIterable, Identifiable {
    case anthropic
    case openAI
    case google

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .google: "Google"
        }
    }
}

/// A program that talks to a provider and writes logs. Several tools share one provider account.
public enum Tool: String, Codable, Sendable, CaseIterable, Identifiable {
    case claudeCode
    case claudeDesktop
    case codex
    case geminiCLI
    case antigravity

    public var id: String { rawValue }

    public var provider: Provider {
        switch self {
        case .claudeCode, .claudeDesktop: .anthropic
        case .codex: .openAI
        case .geminiCLI, .antigravity: .google
        }
    }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claudeDesktop: "Claude Desktop"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .antigravity: "Antigravity"
        }
    }
}
