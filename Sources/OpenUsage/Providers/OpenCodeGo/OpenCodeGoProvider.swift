import Foundation

@MainActor
final class OpenCodeGoProvider: ProviderRuntime {
    let provider = Provider(
        id: "opencode-go",
        displayName: "OpenCode Go",
        icon: .providerMark("opencode-go"),
        links: [
            ProviderLink(label: "Console", url: "https://opencode.ai/auth"),
            ProviderLink(label: "Docs", url: "https://opencode.ai/docs/go/")
        ]
    )

    let authStore: OpenCodeGoAuthStore
    let usageStore: OpenCodeGoUsageStore
    let now: @Sendable () -> Date

    init(
        authStore: OpenCodeGoAuthStore = OpenCodeGoAuthStore(),
        usageStore: OpenCodeGoUsageStore = OpenCodeGoUsageStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.authStore = authStore
        self.usageStore = usageStore
        self.now = now
    }

    var widgetDescriptors: [WidgetDescriptor] {
        [
            .percent(id: "opencode-go.session", provider: provider, title: "Session"),
            .percent(id: "opencode-go.weekly", provider: provider, title: "Weekly"),
            .percent(id: "opencode-go.monthly", provider: provider, title: "Monthly")
        ]
    }

    func refresh() async -> ProviderSnapshot {
        let auth = authStore.loadAuth()
        let history = await loadOffMainActor({ [usageStore] in usageStore.hasHistory() })
        guard auth != nil || history == true else {
            return ProviderSnapshot.error(provider: provider, error: OpenCodeGoError.notDetected)
        }

        guard let rows = await loadOffMainActor({ [usageStore] in usageStore.loadRows() }) else {
            return ProviderSnapshot.make(provider: provider, plan: "Go", lines: [.noUsageData], refreshedAt: now())
        }

        return ProviderSnapshot.make(
            provider: provider,
            plan: "Go",
            lines: OpenCodeGoUsageMapper.map(rows: rows, now: now()),
            refreshedAt: now()
        )
    }
}
