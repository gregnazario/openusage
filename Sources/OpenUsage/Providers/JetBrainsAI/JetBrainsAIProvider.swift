import Foundation

@MainActor
final class JetBrainsAIProvider: ProviderRuntime {
    let provider = Provider(
        id: "jetbrains-ai-assistant",
        displayName: "JetBrains AI Assistant",
        icon: .providerMark("jetbrains-ai-assistant"),
        links: [
            ProviderLink(label: "Docs", url: "https://www.jetbrains.com/ai/")
        ]
    )

    let authStore: JetBrainsAIAuthStore
    let now: @Sendable () -> Date

    init(
        authStore: JetBrainsAIAuthStore = JetBrainsAIAuthStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.authStore = authStore
        self.now = now
    }

    var widgetDescriptors: [WidgetDescriptor] {
        let used = rawTextDescriptor(id: "jetbrains-ai-assistant.used", title: "Used")
        let remaining = rawTextDescriptor(id: "jetbrains-ai-assistant.remaining", title: "Remaining")
        return [
            .percent(id: "jetbrains-ai-assistant.quota", provider: provider, title: "Quota"),
            used,
            remaining
        ]
    }

    func refresh() async -> ProviderSnapshot {
        do {
            let files = await loadOffMainActor({ [authStore] in authStore.loadQuotaFiles() })
            let lines = try JetBrainsAIUsageMapper.map(files: files)
            return ProviderSnapshot.make(provider: provider, plan: nil, lines: lines, refreshedAt: now())
        } catch {
            return ProviderSnapshot.error(provider: provider, error: error)
        }
    }

    private func rawTextDescriptor(id: String, title: String) -> WidgetDescriptor {
        var sample = WidgetData(title: title, icon: provider.icon, kind: .count, used: 0, limit: nil)
        sample.preservesRawText = true
        return WidgetDescriptor(id: id, providerID: provider.id, metricLabel: title, sample: sample)
    }
}
