import Foundation

@MainActor
final class FactoryProvider: ProviderRuntime {
    let provider = Provider(
        id: "factory",
        displayName: "Factory",
        icon: .providerMark("factory"),
        links: [
            ProviderLink(label: "Dashboard", url: "https://app.factory.ai/")
        ]
    )

    let authStore: FactoryAuthStore
    let usageClient: FactoryUsageClient
    let now: @Sendable () -> Date

    init(
        authStore: FactoryAuthStore = FactoryAuthStore(),
        usageClient: FactoryUsageClient = FactoryUsageClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.authStore = authStore
        self.usageClient = usageClient
        self.now = now
    }

    var widgetDescriptors: [WidgetDescriptor] {
        [
            .boundedCount(id: "factory.standard", provider: provider, title: "Standard", limit: 20_000_000, suffix: "tokens"),
            .boundedCount(id: "factory.premium", provider: provider, title: "Premium", limit: 1_000_000, suffix: "tokens")
        ]
    }

    func refresh() async -> ProviderSnapshot {
        guard var authState = await loadOffMainActor({ [authStore] in authStore.loadAuth() }) else {
            return ProviderSnapshot.error(provider: provider, error: FactoryAuthError.notLoggedIn)
        }
        guard var accessToken = authState.auth.accessToken?.nilIfEmpty else {
            return ProviderSnapshot.error(provider: provider, error: FactoryAuthError.invalidAuthFile)
        }

        do {
            if authStore.needsRefresh(accessToken) {
                try await refreshAccessToken(&authState, accessToken: &accessToken, allowFallback: true)
            }
            var response = try await usageClient.fetchUsage(accessToken: accessToken)
            if response.statusCode == 401 || response.statusCode == 403 {
                try await refreshAccessToken(&authState, accessToken: &accessToken, allowFallback: false)
                response = try await usageClient.fetchUsage(accessToken: accessToken)
            }
            if response.statusCode == 401 || response.statusCode == 403 {
                return ProviderSnapshot.error(provider: provider, error: FactoryUsageError.tokenExpired)
            }
            guard (200..<300).contains(response.statusCode) else {
                return ProviderSnapshot.error(provider: provider, error: FactoryUsageError.requestFailed(response.statusCode))
            }
            let mapped = try FactoryUsageMapper.map(response)
            return ProviderSnapshot.make(provider: provider, plan: mapped.plan, lines: mapped.lines, refreshedAt: now())
        } catch let error as FactoryAuthError {
            return ProviderSnapshot.error(provider: provider, error: error)
        } catch let error as FactoryUsageError {
            return ProviderSnapshot.error(provider: provider, error: error)
        } catch {
            return ProviderSnapshot.error(provider: provider, error: FactoryUsageError.connectionFailed)
        }
    }

    private func refreshAccessToken(
        _ authState: inout FactoryAuthState,
        accessToken: inout String,
        allowFallback: Bool
    ) async throws {
        guard let refreshToken = authState.auth.refreshToken?.nilIfEmpty else { return }
        do {
            guard let refreshed = try await usageClient.refreshToken(refreshToken),
                  let newAccessToken = refreshed.accessToken?.nilIfEmpty
            else {
                return
            }
            authState.auth.accessToken = newAccessToken
            if let newRefreshToken = refreshed.refreshToken?.nilIfEmpty {
                authState.auth.refreshToken = newRefreshToken
            }
            authStore.save(authState)
            accessToken = newAccessToken
        } catch {
            if allowFallback, authStore.canUseExistingToken(accessToken) {
                AppLog.warn(LogTag.auth("factory"), "Factory token refresh failed; using existing unexpired token")
                return
            }
            throw error
        }
    }
}
