import Foundation

struct FactoryUsageClient: Sendable {
    static let workOSAuthURL = URL(string: "https://api.workos.com/user_management/authenticate")!
    static let usageURL = URL(string: "https://api.factory.ai/api/organization/subscription/usage")!
    static let workOSClientID = "client_01HNM792M5G5G1A2THWPXKFMXB"

    var http: any HTTPClient

    init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    func refreshToken(_ refreshToken: String) async throws -> FactoryRefreshResponse? {
        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken.urlFormEncoded)",
            "client_id=\(Self.workOSClientID.urlFormEncoded)"
        ].joined(separator: "&")
        let response = try await http.send(HTTPRequest(
            method: "POST",
            url: Self.workOSAuthURL,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(body.utf8),
            timeout: 15
        ))
        if response.statusCode == 400 || response.statusCode == 401 {
            throw FactoryAuthError.sessionExpired
        }
        guard (200..<300).contains(response.statusCode) else { return nil }
        return try? JSONDecoder().decode(FactoryRefreshResponse.self, from: response.body)
    }

    func fetchUsage(accessToken: String) async throws -> HTTPResponse {
        let post = try await http.send(HTTPRequest(
            method: "POST",
            url: Self.usageURL,
            headers: headers(accessToken: accessToken, contentType: true),
            body: Data(#"{"useCache":true}"#.utf8),
            timeout: 10
        ))
        guard post.statusCode == 405 else { return post }
        return try await http.send(HTTPRequest(
            method: "GET",
            url: Self.usageURL,
            headers: headers(accessToken: accessToken, contentType: false),
            timeout: 10
        ))
    }

    private func headers(accessToken: String, contentType: Bool) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(accessToken)",
            "Accept": "application/json",
            "User-Agent": "OpenUsage"
        ]
        if contentType {
            headers["Content-Type"] = "application/json"
        }
        return headers
    }
}

struct FactoryRefreshResponse: Decodable, Sendable {
    var accessToken: String?
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
