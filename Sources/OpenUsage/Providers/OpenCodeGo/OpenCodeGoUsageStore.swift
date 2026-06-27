import Foundation

struct OpenCodeGoUsageRow: Equatable, Sendable {
    var createdMs: Double
    var cost: Double
}

struct OpenCodeGoUsageStore: Sendable {
    static let dbPath = "~/.local/share/opencode/opencode.db"

    private static let whereClause = """
    WHERE json_valid(data)
      AND json_extract(data, '$.providerID') = 'opencode-go'
      AND json_extract(data, '$.role') = 'assistant'
      AND json_type(data, '$.cost') IN ('integer', 'real')
    """

    var sqlite: SQLiteAccessing

    init(sqlite: SQLiteAccessing = SQLiteCLIAccessor()) {
        self.sqlite = sqlite
    }

    func hasHistory() -> Bool? {
        let sql = "SELECT 1 FROM message \(Self.whereClause) LIMIT 1"
        do {
            return try sqlite.queryValue(path: Self.dbPath, sql: sql) != nil
        } catch {
            AppLog.warn(LogTag.plugin("opencode-go"), "history presence query failed: \(error.localizedDescription)")
            return nil
        }
    }

    func loadRows() -> [OpenCodeGoUsageRow]? {
        let sql = """
        SELECT json_group_array(json_object('createdMs', createdMs, 'cost', cost))
        FROM (
          SELECT
            CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS createdMs,
            CAST(json_extract(data, '$.cost') AS REAL) AS cost
          FROM message
          \(Self.whereClause)
        )
        """
        do {
            guard let text = try sqlite.queryValue(path: Self.dbPath, sql: sql),
                  let data = text.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                return nil
            }
            return raw.compactMap { item in
                guard let createdMs = ProviderParse.number(item["createdMs"]),
                      createdMs > 0,
                      let cost = ProviderParse.number(item["cost"]),
                      cost >= 0
                else {
                    return nil
                }
                return OpenCodeGoUsageRow(createdMs: createdMs, cost: cost)
            }
        } catch {
            AppLog.warn(LogTag.plugin("opencode-go"), "history query failed: \(error.localizedDescription)")
            return nil
        }
    }
}
