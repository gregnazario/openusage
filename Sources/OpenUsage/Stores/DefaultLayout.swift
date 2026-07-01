import Foundation

/// Metrics enabled on first launch. Core quota meters and trends stay visible above the fold, while
/// balances, reset details, and spend-history rows are enabled but tucked behind each provider's caret.
/// `LayoutStore` filters this to whatever the active registry actually knows, so registries that don't
/// define an ID (e.g. the test fixtures) silently ignore it. The provider-section order isn't seeded
/// here: an empty saved order reconciles to plain registry order in `LayoutStore`.
enum DefaultLayout {
    static let metricIDs: [String] = [
        "antigravity.geminiPro", "antigravity.geminiFlash", "antigravity.claude",

        "claude.session", "claude.weekly", "claude.trend",
        "claude.extra", "claude.today", "claude.yesterday", "claude.last30",

        "codex.session", "codex.weekly", "codex.spark", "codex.sparkWeekly", "codex.trend",
        "codex.credits", "codex.rateLimitResets", "codex.today", "codex.yesterday", "codex.last30",

        "cursor.usage", "cursor.auto", "cursor.api", "cursor.trend",
        "cursor.onDemand", "cursor.today", "cursor.yesterday", "cursor.last30",

        "copilot.premium", "copilot.extra", "copilot.chat", "copilot.completions",

        "devin.daily", "devin.weekly", "devin.extra",

        "factory.standard", "factory.premium",

        "grok.creditsUsed", "grok.trend",
        "grok.payAsYouGo", "grok.today", "grok.yesterday", "grok.last30",

        "jetbrains-ai-assistant.quota", "jetbrains-ai-assistant.used", "jetbrains-ai-assistant.remaining",

        "opencode-go.session", "opencode-go.weekly", "opencode-go.monthly",

        "openrouter.credits", "openrouter.balance",
        "openrouter.today", "openrouter.week", "openrouter.month", "openrouter.keyLimit",

        "zai.session", "zai.weekly", "zai.webSearches"
    ]

    /// Frozen snapshot of the default-on metrics from the release that introduced default seeding.
    /// Existing users without a seeded-defaults key are treated as if these were already offered, so
    /// past opt-outs stay off while future additions to `metricIDs` can appear automatically once.
    static let migrationBaselineMetricIDs: [String] = [
        "claude.session", "claude.weekly", "claude.trend",
        "claude.extra", "claude.today", "claude.yesterday", "claude.last30",

        "codex.session", "codex.weekly", "codex.trend",
        "codex.credits", "codex.rateLimitResets", "codex.today", "codex.yesterday", "codex.last30",

        "devin.daily", "devin.weekly", "devin.extra",

        "grok.creditsUsed", "grok.trend",
        "grok.payAsYouGo", "grok.today", "grok.yesterday", "grok.last30",

        "cursor.usage", "cursor.auto", "cursor.api", "cursor.trend",
        "cursor.onDemand", "cursor.today", "cursor.yesterday", "cursor.last30"
    ]

    /// Metrics pinned to the menu bar on first launch, so the app shows real numbers out of the box
    /// instead of a lone icon. Filtered to the active registry by `LayoutStore`, like `metricIDs`.
    static let pinnedMetricIDs: [String] = [
        "codex.session",
        "zai.session",
        "opencode-go.session"
    ]

    /// Providers hidden from the menu bar on first launch. Empty by default — the default
    /// `pinnedMetricIDs` set above is what a fresh install shows. Users add to this list from
    /// Settings → Menu Bar; the entry is removed (and the remembered pins restored) when they
    /// re-enable the provider. Filtered to the active registry by `LayoutStore`.
    static let hiddenProviderIDs: [String] = []

    /// Metrics tucked below the per-provider "Shown on expand" divider on a fresh install. This is
    /// membership, not enablement: optional disabled rows like Sonnet or Cursor Requests/Credits are
    /// listed here so if the user enables them later they appear below the caret by default.
    /// Filtered to the active registry by `LayoutStore`, and only seeded on a genuinely fresh launch
    /// (existing layouts keep everything always-shown unless they reset customization).
    static let expandedMetricIDs: [String] = [
        // Antigravity: Gemini Pro + Flash stay above the fold; only the non-Gemini (Claude) pool is secondary.
        "antigravity.claude",
        // Claude's core meters (Session, Weekly, Extra, Usage Trend) stay above the fold; spend-history
        // rows sit below the caret. Matches every other provider's "core above, history below" shape.
        "claude.sonnet", "claude.today", "claude.yesterday", "claude.last30",
        // Codex's core Session/Weekly meters and Usage Trend stay above the fold; Spark (the optional
        // model-specific limits), credits, reset details, and spend rows sit below the caret.
        "codex.spark", "codex.sparkWeekly",
        "codex.credits", "codex.rateLimitResets", "codex.today", "codex.yesterday", "codex.last30",
        "cursor.onDemand", "cursor.requests", "cursor.credits",
        "cursor.today", "cursor.yesterday", "cursor.last30",
        // Copilot: Credits (the metered premium pool) + Extra Usage stay above the fold; Chat +
        // Completions sit below the caret. They carry real counts on free only - on paid they're
        // unlimited (suppressed), so they read "No data" there.
        "copilot.chat", "copilot.completions",
        "devin.extra",
        "factory.premium",
        "grok.payAsYouGo", "grok.today", "grok.yesterday", "grok.last30",
        "jetbrains-ai-assistant.used", "jetbrains-ai-assistant.remaining",
        "opencode-go.monthly",
        // OpenRouter: Credits meter + Balance stay above the fold; period spend and the per-key cap
        // sit below the caret.
        "openrouter.today", "openrouter.week", "openrouter.month", "openrouter.keyLimit",
        // Z.ai: Session meter stays above the fold; Web Searches (monthly count) sits below the caret.
        "zai.webSearches"
    ]
}
