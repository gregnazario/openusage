import Foundation

struct FactoryMappedUsage: Equatable, Sendable {
    var plan: String?
    var lines: [MetricLine]
}

enum FactoryUsageMapper {
    static func map(_ response: HTTPResponse) throws -> FactoryMappedUsage {
        guard let object = ProviderParse.jsonObject(response.body),
              let usage = object["usage"] as? [String: Any]
        else {
            throw FactoryUsageError.invalidResponse
        }

        let start = ProviderParse.number(usage["startDate"])
        let end = ProviderParse.number(usage["endDate"])
        let resetsAt = end.map { Date(timeIntervalSince1970: $0 / 1000) }
        let period = start.flatMap { start in end.map { Int($0 - start) } }

        var lines: [MetricLine] = []
        let standard = usage["standard"] as? [String: Any]
        let premium = usage["premium"] as? [String: Any]

        if let allowance = ProviderParse.number(standard?["totalAllowance"]) {
            lines.append(.progress(
                label: "Standard",
                used: ProviderParse.number(standard?["orgTotalTokensUsed"]) ?? 0,
                limit: allowance,
                format: .count(suffix: "tokens"),
                resetsAt: resetsAt,
                periodDurationMs: period
            ))
        }

        if let allowance = ProviderParse.number(premium?["totalAllowance"]), allowance > 0 {
            lines.append(.progress(
                label: "Premium",
                used: ProviderParse.number(premium?["orgTotalTokensUsed"]) ?? 0,
                limit: allowance,
                format: .count(suffix: "tokens"),
                resetsAt: resetsAt,
                periodDurationMs: period
            ))
        }

        let plan = ProviderParse.number(standard?["totalAllowance"]).flatMap(planName)
        MetricLine.appendNoDataIfNeeded(&lines)
        return FactoryMappedUsage(plan: plan, lines: lines)
    }

    private static func planName(_ allowance: Double) -> String? {
        if allowance >= 200_000_000 { return "Max" }
        if allowance >= 20_000_000 { return "Pro" }
        if allowance > 0 { return "Basic" }
        return nil
    }
}

enum FactoryUsageError: Error, LocalizedError, Equatable {
    case connectionFailed
    case invalidResponse
    case requestFailed(Int)
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return ProviderUsageErrorText.connectionFailed
        case .invalidResponse:
            return ProviderUsageErrorText.invalidResponse
        case .requestFailed(let status):
            return ProviderUsageErrorText.requestFailed(statusCode: status)
        case .tokenExpired:
            return "Token expired. Run `droid` to log in again."
        }
    }
}
