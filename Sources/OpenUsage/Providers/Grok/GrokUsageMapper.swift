import Foundation

struct GrokMappedUsage: Equatable, Sendable {
    var lines: [MetricLine]
    /// Soft header notice carried alongside real lines (e.g. plans with no coding credits) —
    /// rendered as the card's amber triangle without failing the refresh.
    var warning: String? = nil
}

enum GrokUsageMapper {
    static func mapBillingResponse(_ response: HTTPResponse) throws -> GrokMappedUsage {
        try ProviderAuthRetry.requireSuccess(
            response,
            authExpired: GrokAuthError.expired,
            requestFailed: { GrokUsageError.requestFailed($0) }
        )
        guard let body = ProviderParse.jsonObject(response.body),
              let config = body["config"] as? [String: Any],
              let usedUnits = unitsValue(config["used"]),
              let limitUnits = unitsValue(config["monthlyLimit"])
        else {
            throw GrokUsageError.invalidResponse
        }

        // A SuperGrok account with no pay-as-you-go has no `onDemandCap` field at all. Treat a
        // missing/non-numeric cap as 0 → the "Disabled" badge below, instead of failing the whole
        // guard and surfacing a misleading "Grok billing response changed." A present cap of 0
        // already mapped to Disabled and still does.
        let onDemandCapUnits = unitsValue(config["onDemandCap"]) ?? 0

        // A `monthlyLimit` of 0 is a real account state, not a broken payload: plans without
        // included coding credits (e.g. X Premium+ since 2026-08) report 0/0. A percent meter
        // would divide by zero and the old guard mislabeled this "response changed" — instead,
        // warn on the card header and keep only the badge, so the local-log spend rows still
        // render and the menu bar drops the meaningless meter.
        if limitUnits <= 0 {
            return GrokMappedUsage(
                lines: [payAsYouGoBadge(cap: onDemandCapUnits)],
                warning: "No coding credits included on this plan"
            )
        }

        guard let resetsAt = resetDate(config["billingPeriodEnd"]) else {
            throw GrokUsageError.invalidResponse
        }

        let usedPercent = ProviderParse.clampPercent((usedUnits / limitUnits) * 100)
        return GrokMappedUsage(lines: [
            .progress(
                label: "Credits used",
                used: usedPercent,
                limit: 100,
                format: .percent,
                resetsAt: resetsAt
            ),
            payAsYouGoBadge(cap: onDemandCapUnits)
        ])
    }

    static func planName(from response: HTTPResponse) -> String? {
        guard (200..<300).contains(response.statusCode),
              let body = ProviderParse.jsonObject(response.body),
              let plan = body["subscription_tier_display"] as? String
        else {
            return nil
        }
        let trimmed = plan.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unitsValue(_ value: Any?) -> Double? {
        guard let object = value as? [String: Any],
              let number = ProviderParse.number(object["val"])
        else {
            return nil
        }
        return number.isFinite ? number : nil
    }

    private static func payAsYouGoBadge(cap: Double) -> MetricLine {
        .badge(
            label: "Pay as you go",
            text: cap > 0 ? "\(formatUnits(cap)) cap" : "Disabled",
            colorHex: cap > 0 ? "#22c55e" : "#a3a3a3"
        )
    }

    private static func resetDate(_ value: Any?) -> Date? {
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        return OpenUsageISO8601.date(from: raw)
    }

    private static func formatUnits(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}
