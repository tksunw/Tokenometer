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
        // organizationType is "claude_max" / "claude_pro" / "claude_team" / "claude_enterprise". An older
        // cache may have only subscriptionType ("max"), which names the same thing.
        let orgType = account.string("organizationType") ?? account.string("subscriptionType").map { "claude_" + $0 } ?? ""
        if orgType.contains("enterprise") { return AccountInfo(kind: .metered, planName: "Enterprise") }
        // The seat's own tier first: a Team organization has its own tier ("default_raven" on a live
        // Team Premium seat) while the seat's sits in userRateLimitTier. Max logins leave it null.
        let tier = account.string("userRateLimitTier") ?? account.string("organizationRateLimitTier")
        return AccountInfo(kind: .plan, planName: claudePlanName(orgType: orgType, tier: tier))
    }

    /// The seat behind the login. A Team Premium seat carries Max 5x's rate tier, so the tier tells the two
    /// Team seats apart; Max is 5x unless its tier says 20x.
    static func claudePlanName(orgType: String, tier: String?) -> String {
        switch orgType {
        case "claude_team": tier == "default_claude_max_5x" ? "Team Premium" : "Team Standard"
        case "claude_max": tier == "default_claude_max_20x" ? "Max 20x" : "Max 5x"
        case "claude_pro": "Pro"
        default: "Free"
        }
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
