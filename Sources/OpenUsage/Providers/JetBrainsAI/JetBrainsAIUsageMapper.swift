import Foundation

struct JetBrainsQuotaState: Equatable, Sendable {
    var path: String
    var used: Double
    var maximum: Double
    var remaining: Double?
    var until: Date?
    var nextRefill: Date?
    var periodDurationMs: Int?
    var scale: Double
}

enum JetBrainsAIUsageMapper {
    static let creditScale = 100_000.0

    static func map(files: [JetBrainsQuotaFile]) throws -> [MetricLine] {
        guard !files.isEmpty else {
            throw JetBrainsAIError.notDetected
        }
        let states = files.compactMap(parse)
        guard let chosen = pickBest(states) else {
            throw JetBrainsAIError.quotaUnavailable
        }

        let usedPercent = ProviderParse.clampPercent((chosen.used / chosen.maximum) * 100)
        var lines: [MetricLine] = [
            .progress(
                label: "Quota",
                used: usedPercent,
                limit: 100,
                format: .percent,
                resetsAt: chosen.nextRefill ?? chosen.until,
                periodDurationMs: chosen.periodDurationMs
            ),
            .text(label: "Used", value: usedValue(chosen))
        ]
        if let remaining = chosen.remaining {
            lines.append(.text(label: "Remaining", value: display(remaining, scale: chosen.scale, suffix: chosen.scale > 1 ? " credits" : "")))
        }
        return lines
    }

    static func parse(_ file: JetBrainsQuotaFile) -> JetBrainsQuotaState? {
        guard let quota = parseOptionJSON(file.text, optionName: "quotaInfo") as? [String: Any] else {
            return nil
        }
        let nextRefill = parseOptionJSON(file.text, optionName: "nextRefill") as? [String: Any]
        guard var normalized = normalizeQuota(quota) else {
            return nil
        }
        let scale = displayScale(quota: normalized, nextRefill: nextRefill)
        let next = (nextRefill?["next"] as? String).flatMap(OpenUsageISO8601.date(from:))
        let duration = ((nextRefill?["tariff"] as? [String: Any])?["duration"] as? String).flatMap(parseISODurationMs)
        normalized.path = file.path
        normalized.nextRefill = next
        normalized.periodDurationMs = duration
        normalized.scale = scale
        return normalized
    }

    private static func normalizeQuota(_ quota: [String: Any]) -> JetBrainsQuotaState? {
        let tariff = quota["tariffQuota"] as? [String: Any]
        let topUp = quota["topUpQuota"] as? [String: Any]
        var maximum = ProviderParse.number(quota["maximum"])
        var used = ProviderParse.number(quota["current"])
        var remaining = ProviderParse.number(quota["available"])

        if maximum == nil {
            let parts = [ProviderParse.number(tariff?["maximum"]), ProviderParse.number(topUp?["maximum"])]
            if parts.contains(where: { $0 != nil }) { maximum = parts.compactMap(\.self).reduce(0, +) }
        }
        if used == nil {
            let parts = [ProviderParse.number(tariff?["current"]), ProviderParse.number(topUp?["current"])]
            if parts.contains(where: { $0 != nil }) { used = parts.compactMap(\.self).reduce(0, +) }
        }
        if remaining == nil {
            let parts = [ProviderParse.number(tariff?["available"]), ProviderParse.number(topUp?["available"])]
            if parts.contains(where: { $0 != nil }) { remaining = parts.compactMap(\.self).reduce(0, +) }
        }
        if remaining == nil, let maximum, let used {
            remaining = maximum - used
        }
        guard let maximum, maximum > 0, var used else { return nil }
        used = min(max(used, 0), maximum)
        if let value = remaining {
            remaining = min(max(value, 0), maximum)
        }
        return JetBrainsQuotaState(
            path: "",
            used: used,
            maximum: maximum,
            remaining: remaining,
            until: (quota["until"] as? String).flatMap(OpenUsageISO8601.date(from:)),
            nextRefill: nil,
            periodDurationMs: nil,
            scale: 1
        )
    }

    private static func pickBest(_ states: [JetBrainsQuotaState]) -> JetBrainsQuotaState? {
        states.max { lhs, rhs in
            let lhsReset = lhs.nextRefill ?? lhs.until ?? .distantPast
            let rhsReset = rhs.nextRefill ?? rhs.until ?? .distantPast
            if lhsReset != rhsReset { return lhsReset < rhsReset }
            let lhsRatio = lhs.maximum > 0 ? lhs.used / lhs.maximum : 0
            let rhsRatio = rhs.maximum > 0 ? rhs.used / rhs.maximum : 0
            if lhsRatio != rhsRatio { return lhsRatio < rhsRatio }
            return lhs.used < rhs.used
        }
    }

    private static func parseOptionJSON(_ xml: String, optionName: String) -> Any? {
        let pattern = #"<option\b[^>]*\bname=""# + NSRegularExpression.escapedPattern(for: optionName) + #""[^>]*/>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range, in: xml)
        else {
            return nil
        }
        let element = String(xml[range])
        guard let valueRange = element.range(of: #"\bvalue="([^"]*)""#, options: .regularExpression),
              let quoteStart = element[valueRange].firstIndex(of: "\"")
        else {
            return nil
        }
        let afterQuote = element.index(after: quoteStart)
        guard let quoteEnd = element[afterQuote...].firstIndex(of: "\"") else { return nil }
        let encoded = String(element[afterQuote..<quoteEnd])
        let decoded = decodeXMLEntities(encoded)
        guard let data = decoded.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func decodeXMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&#13;", with: "\r")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func parseISODurationMs(_ value: String) -> Int? {
        if let hours = captureInt(value, pattern: #"^PT(\d+)H$"#) { return hours * 60 * 60 * 1000 }
        if let days = captureInt(value, pattern: #"^P(\d+)D$"#) { return days * MetricPeriod.dayMs }
        if let weeks = captureInt(value, pattern: #"^P(\d+)W$"#) { return weeks * MetricPeriod.weekMs }
        return nil
    }

    private static func captureInt(_ value: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value)
        else {
            return nil
        }
        return Int(String(value[range]))
    }

    private static func displayScale(quota: JetBrainsQuotaState, nextRefill: [String: Any]?) -> Double {
        var maxAbs = max(abs(quota.maximum), abs(quota.used), abs(quota.remaining ?? 0))
        if let tariffAmount = ProviderParse.number((nextRefill?["tariff"] as? [String: Any])?["amount"]) {
            maxAbs = max(maxAbs, abs(tariffAmount))
        }
        return maxAbs >= creditScale ? creditScale : 1
    }

    private static func usedValue(_ quota: JetBrainsQuotaState) -> String {
        guard quota.scale > 1 else { return display(quota.used, scale: quota.scale, suffix: "") }
        return "\(display(quota.used, scale: quota.scale, suffix: "")) / \(display(quota.maximum, scale: quota.scale, suffix: " credits"))"
    }

    private static func display(_ value: Double, scale: Double, suffix: String) -> String {
        let scaled = value / scale
        let rounded = (scaled * 100).rounded() / 100
        let formatted = String(format: "%.2f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        return formatted + suffix
    }
}
