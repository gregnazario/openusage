import XCTest
@testable import OpenUsage

final class AddedProvidersTests: XCTestCase {
    func testZAIAuthPrefersKeychainOverEnvironment() {
        let store = ZAIAuthStore(
            files: FakeFiles(),
            environment: FakeEnvironment(["ZAI_API_KEY": "env-key"]),
            keychain: ServiceKeychain(values: ["OpenUsage-zai": "keychain-key"])
        )

        let auth = store.loadAPIKey()
        XCTAssertEqual(auth?.apiKey, "keychain-key")
        XCTAssertEqual(auth?.source, .keychain)
    }

    func testZAIAuthReadsJSONKeychainPayload() {
        XCTAssertEqual(ZAIAuthStore.apiKey(from: #"{"apiKey":"json-key"}"#), "json-key")
        XCTAssertEqual(ZAIAuthStore.apiKey(from: #"{"token":"token-key"}"#), "token-key")
    }

    func testZAIMapsSessionWeeklyAndWebSearches() throws {
        let quota = jsonResponse([
            "data": [
                "limits": [
                    ["type": "TOKENS_LIMIT", "unit": 6, "percentage": 75, "nextResetTime": 1_738_972_800_000],
                    ["type": "TOKENS_LIMIT", "unit": 3, "percentage": 10, "nextResetTime": 1_738_368_000_000],
                    ["type": "TIME_LIMIT", "usage": 4000, "currentValue": 1095]
                ]
            ]
        ])
        let subscription = ZAISubscriptionResponse(statusCode: 200, body: jsonData(["data": [["productName": "GLM Coding Max"]]]))

        let mapped = try ZAIUsageMapper.map(
            subscription: subscription,
            quota: quota,
            now: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(mapped.plan, "GLM Coding Max")
        XCTAssertEqual(mapped.lines.progressUsed("Session"), 10)
        XCTAssertEqual(mapped.lines.progressUsed("Weekly"), 75)
        XCTAssertEqual(mapped.lines.progressUsed("Web Searches"), 1095)
    }

    func testOpenCodeGoUsesRollingWeeklyAndAnchoredMonthlyWindows() {
        let now = iso("2026-03-06T12:00:00.000Z")
        let rows = [
            OpenCodeGoUsageRow(createdMs: iso("2026-02-25T07:53:16.000Z").millisecondsSince1970, cost: 2.181),
            OpenCodeGoUsageRow(createdMs: iso("2026-03-02T00:00:00.000Z").millisecondsSince1970, cost: 6),
            OpenCodeGoUsageRow(createdMs: iso("2026-03-06T10:00:00.000Z").millisecondsSince1970, cost: 1.2)
        ]

        let lines = OpenCodeGoUsageMapper.map(rows: rows, now: now)

        XCTAssertEqual(lines.progressUsed("Session"), 10)
        XCTAssertEqual(lines.progressUsed("Weekly"), 24)
        XCTAssertEqual(lines.progressUsed("Monthly"), 15.6)
        XCTAssertEqual(lines.progressReset("Monthly"), iso("2026-03-25T07:53:16.000Z"))
    }

    func testJetBrainsMapsQuotaCreditsAndRemaining() throws {
        let xml = quotaXML(
            quotaInfo: [
                "current": "1981684.92",
                "maximum": "2367648.941",
                "tariffQuota": ["current": "1981684.92", "maximum": "2367648.941", "available": "385964.21"],
                "topUpQuota": ["current": "0", "maximum": "0", "available": "0"],
                "until": "2026-04-30T21:00:00Z"
            ],
            nextRefill: [
                "next": "2026-03-14T06:00:54.020Z",
                "tariff": ["amount": "2000000", "duration": "PT720H"]
            ]
        )

        let lines = try JetBrainsAIUsageMapper.map(files: [JetBrainsQuotaFile(path: "quota.xml", text: xml)])

        XCTAssertEqual(lines.progressUsed("Quota") ?? 0, 83.7, accuracy: 0.1)
        XCTAssertEqual(lines.textValue("Used"), "19.82 / 23.68 credits")
        XCTAssertEqual(lines.textValue("Remaining"), "3.86 credits")
        XCTAssertEqual(lines.progressPeriod("Quota"), 30 * MetricPeriod.dayMs)
    }

    func testFactoryMapsStandardAndPremiumTokenMeters() throws {
        let response = jsonResponse([
            "usage": [
                "startDate": 1_770_623_326_000,
                "endDate": 1_772_956_800_000,
                "standard": ["orgTotalTokensUsed": 5_000_000, "totalAllowance": 20_000_000],
                "premium": ["orgTotalTokensUsed": 1_000_000, "totalAllowance": 50_000_000]
            ]
        ])

        let mapped = try FactoryUsageMapper.map(response)

        XCTAssertEqual(mapped.plan, "Pro")
        XCTAssertEqual(mapped.lines.progressUsed("Standard"), 5_000_000)
        XCTAssertEqual(mapped.lines.progressLimit("Premium"), 50_000_000)
    }

    func testCopilotMapsPaidAndFreeQuotaShapes() throws {
        let paid = jsonResponse([
            "copilot_plan": "business plus",
            "quota_reset_date": "2099-01-15T00:00:00Z",
            "quota_snapshots": [
                "premium_interactions": ["percent_remaining": 80],
                "chat": ["percent_remaining": 95]
            ]
        ])
        let paidMapped = try CopilotUsageMapper.map(paid)
        XCTAssertEqual(paidMapped.plan, "Business Plus")
        XCTAssertEqual(paidMapped.lines.progressUsed("Premium"), 20)
        XCTAssertEqual(paidMapped.lines.progressUsed("Chat"), 5)

        let free = jsonResponse([
            "limited_user_quotas": ["chat": 250, "completions": 2000],
            "monthly_quotas": ["chat": 500, "completions": 4000],
            "limited_user_reset_date": "2026-02-15"
        ])
        let freeMapped = try CopilotUsageMapper.map(free)
        XCTAssertEqual(freeMapped.lines.progressUsed("Chat"), 50)
        XCTAssertEqual(freeMapped.lines.progressUsed("Completions"), 50)
    }

    private func jsonResponse(_ object: [String: Any], status: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: [:], body: jsonData(object))
    }

    private func jsonData(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func iso(_ value: String) -> Date {
        OpenUsageISO8601.date(from: value)!
    }

    private func quotaXML(quotaInfo: [String: Any], nextRefill: [String: Any]) -> String {
        """
        <application>
          <component name="AIAssistantQuotaManager2">
            <option name="nextRefill" value="\(xmlEncodedJSON(nextRefill))" />
            <option name="quotaInfo" value="\(xmlEncodedJSON(quotaInfo))" />
          </component>
        </application>
        """
    }

    private func xmlEncodedJSON(_ value: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "&#10;")
    }
}

private extension Date {
    var millisecondsSince1970: Double { timeIntervalSince1970 * 1000 }
}

private extension Array where Element == MetricLine {
    func progressUsed(_ label: String) -> Double? {
        guard case .progress(_, let used, _, _, _, _, _) = first(where: { $0.label == label }) else { return nil }
        return used
    }

    func progressLimit(_ label: String) -> Double? {
        guard case .progress(_, _, let limit, _, _, _, _) = first(where: { $0.label == label }) else { return nil }
        return limit
    }

    func progressReset(_ label: String) -> Date? {
        guard case .progress(_, _, _, _, let reset, _, _) = first(where: { $0.label == label }) else { return nil }
        return reset
    }

    func progressPeriod(_ label: String) -> Int? {
        guard case .progress(_, _, _, _, _, let period, _) = first(where: { $0.label == label }) else { return nil }
        return period
    }

    func textValue(_ label: String) -> String? {
        guard case .text(_, let value, _, _) = first(where: { $0.label == label }) else { return nil }
        return value
    }
}
