import Foundation

enum OpenCodeGoUsageMapper {
    static let sessionPeriodMs = 5 * 60 * 60 * 1000
    static let weekPeriodMs = MetricPeriod.weekMs
    static let limits = (session: 12.0, weekly: 30.0, monthly: 60.0)

    static func map(rows: [OpenCodeGoUsageRow], now: Date) -> [MetricLine] {
        let nowMs = now.timeIntervalSince1970 * 1000
        let sessionStart = nowMs - Double(sessionPeriodMs)
        let weeklyStart = startOfUTCWeek(nowMs: nowMs)
        let weeklyEnd = weeklyStart + Double(weekPeriodMs)
        let earliest = rows.map(\.createdMs).min()
        let monthly = anchoredMonthBounds(nowMs: nowMs, anchorMs: earliest)

        let sessionCost = sum(rows, startMs: sessionStart, endMs: nowMs)
        let weeklyCost = sum(rows, startMs: weeklyStart, endMs: weeklyEnd)
        let monthlyCost = sum(rows, startMs: monthly.startMs, endMs: monthly.endMs)

        return [
            .progress(
                label: "Session",
                used: percent(sessionCost, limits.session),
                limit: 100,
                format: .percent,
                resetsAt: nextRollingReset(rows: rows, nowMs: nowMs),
                periodDurationMs: sessionPeriodMs
            ),
            .progress(
                label: "Weekly",
                used: percent(weeklyCost, limits.weekly),
                limit: 100,
                format: .percent,
                resetsAt: Date(timeIntervalSince1970: weeklyEnd / 1000),
                periodDurationMs: weekPeriodMs
            ),
            .progress(
                label: "Monthly",
                used: percent(monthlyCost, limits.monthly),
                limit: 100,
                format: .percent,
                resetsAt: Date(timeIntervalSince1970: monthly.endMs / 1000),
                periodDurationMs: Int(monthly.endMs - monthly.startMs)
            )
        ]
    }

    private static func percent(_ used: Double, _ limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return (ProviderParse.clampPercent((used / limit) * 100) * 10).rounded() / 10
    }

    private static func sum(_ rows: [OpenCodeGoUsageRow], startMs: Double, endMs: Double) -> Double {
        let total = rows.reduce(0) { partial, row in
            row.createdMs >= startMs && row.createdMs < endMs ? partial + row.cost : partial
        }
        return (total * 10000).rounded() / 10000
    }

    private static func nextRollingReset(rows: [OpenCodeGoUsageRow], nowMs: Double) -> Date {
        let startMs = nowMs - Double(sessionPeriodMs)
        let oldest = rows
            .filter { $0.createdMs >= startMs && $0.createdMs < nowMs }
            .map(\.createdMs)
            .min() ?? nowMs
        return Date(timeIntervalSince1970: (oldest + Double(sessionPeriodMs)) / 1000)
    }

    private static func startOfUTCWeek(nowMs: Double) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: nowMs / 1000)
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2
        return (calendar.date(from: components) ?? date).timeIntervalSince1970 * 1000
    }

    private static func anchoredMonthBounds(nowMs: Double, anchorMs: Double?) -> (startMs: Double, endMs: Double) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: nowMs / 1000)
        guard let anchorMs else {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (start.timeIntervalSince1970 * 1000, end.timeIntervalSince1970 * 1000)
        }

        let anchor = Date(timeIntervalSince1970: anchorMs / 1000)
        let anchorParts = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: anchor)
        var nowParts = calendar.dateComponents([.year, .month], from: now)
        var start = anchorMonth(calendar: calendar, year: nowParts.year!, month: nowParts.month!, anchor: anchorParts)
        if start.timeIntervalSince1970 * 1000 > nowMs {
            let previous = calendar.date(byAdding: .month, value: -1, to: start) ?? start
            nowParts = calendar.dateComponents([.year, .month], from: previous)
            start = anchorMonth(calendar: calendar, year: nowParts.year!, month: nowParts.month!, anchor: anchorParts)
        }
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return (start.timeIntervalSince1970 * 1000, end.timeIntervalSince1970 * 1000)
    }

    private static func anchorMonth(calendar: Calendar, year: Int, month: Int, anchor: DateComponents) -> Date {
        let maxDay = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month))!)?.count ?? 28
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: min(anchor.day ?? 1, maxDay),
            hour: anchor.hour ?? 0,
            minute: anchor.minute ?? 0,
            second: anchor.second ?? 0,
            nanosecond: anchor.nanosecond ?? 0
        ))!
    }
}
