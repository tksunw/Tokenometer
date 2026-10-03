import Foundation

/// Published API rates in USD per million tokens. On plan accounts this yields API-equivalent cost
/// (see GLOSSARY.md), not a bill. Unknown models return nil and the UI shows "?" rather than guessing.
public struct ModelRate: Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheWrite: Double
    public var cacheRead: Double

    public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public func cost(of tokens: TokenCounts) -> Double {
        (Double(tokens.input) * input
            + Double(tokens.output) * output
            + Double(tokens.cacheWrite) * cacheWrite
            + Double(tokens.cacheRead) * cacheRead) / 1_000_000
    }
}

public enum Pricing {
    /// Longest matching prefix wins, so "claude-opus-5-5" beats "claude-opus-5". Rates as of 2026-09.
    static let table: [(prefix: String, rate: ModelRate)] = [
        // Anthropic
        ("claude-fable-5", ModelRate(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 0.25)),
        ("claude-mythos-5", ModelRate(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 0.25)),
        ("claude-opus-5-5", ModelRate(input: 4, output: 20, cacheWrite: 5, cacheRead: 0.20)),
        ("claude-opus-5", ModelRate(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50)),
        ("claude-opus-4-8", ModelRate(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50)),
        ("claude-opus-4-7", ModelRate(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50)),
        ("claude-opus-4-6", ModelRate(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50)),
        ("claude-opus-4-5", ModelRate(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50)),
        ("claude-opus-4", ModelRate(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.50)),
        ("claude-sonnet-5", ModelRate(input: 2, output: 10, cacheWrite: 2.5, cacheRead: 0.20)),
        ("claude-sonnet-4", ModelRate(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.30)),
        ("claude-haiku-4-5", ModelRate(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.10)),
        ("claude-haiku", ModelRate(input: 0.25, output: 1.25, cacheWrite: 0.30, cacheRead: 0.03)),
        // OpenAI. Codex model ids share the GPT prefixes. GPT-6 cache rates are not published alongside
        // the standard rates; cached input assumed at 10% of input, writes at input.
        ("gpt-6-astra", ModelRate(input: 10, output: 50, cacheWrite: 10, cacheRead: 1)),
        ("gpt-6-sol", ModelRate(input: 2, output: 10, cacheWrite: 2, cacheRead: 0.2)),
        ("gpt-6-luna", ModelRate(input: 0.10, output: 0.50, cacheWrite: 0.10, cacheRead: 0.01)),
        // Codex's built-in reviewer: 20 to 50 reviews per window are included in the plan, overage bills
        // at GPT-6 Luna rates. The logs do not mark overage, so it counts as included.
        ("codex-auto-review", ModelRate(input: 0, output: 0, cacheWrite: 0, cacheRead: 0)),
        ("gpt-5.4-nano", ModelRate(input: 0.20, output: 1.25, cacheWrite: 0.20, cacheRead: 0.02)),
        ("gpt-5.4-mini", ModelRate(input: 0.75, output: 4.50, cacheWrite: 0.75, cacheRead: 0.075)),
        ("gpt-5.4", ModelRate(input: 2.50, output: 15, cacheWrite: 2.50, cacheRead: 0.25)),
        ("gpt-5-nano", ModelRate(input: 0.05, output: 0.40, cacheWrite: 0.05, cacheRead: 0.005)),
        ("gpt-5-mini", ModelRate(input: 0.25, output: 2, cacheWrite: 0.25, cacheRead: 0.025)),
        ("gpt-5", ModelRate(input: 1.25, output: 10, cacheWrite: 1.25, cacheRead: 0.125)),
    ]

    public static func rate(for model: String) -> ModelRate? {
        let lower = model.lowercased()
        return table
            .filter { lower.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }?
            .rate
    }

    public static func cost(for model: String, tokens: TokenCounts) -> Double? {
        rate(for: model)?.cost(of: tokens)
    }
}
