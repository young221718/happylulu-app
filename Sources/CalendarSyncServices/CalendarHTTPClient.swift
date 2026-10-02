import Foundation

public enum CalendarHTTPError: Error, LocalizedError, Sendable {
    case insecureURL
    case responseMissing
    case httpStatus(Int, retryAfter: String?)

    public var errorDescription: String? {
        switch self {
        case .insecureURL: "HTTPS 캘린더 주소가 필요합니다"
        case .responseMissing: "캘린더 서버의 응답을 확인할 수 없습니다"
        case .httpStatus(let status, _): "캘린더 서버 응답 \(status)"
        }
    }
}

public struct CalendarHTTPResult: Sendable {
    public let data: Data
    public let status: Int
    public let etag: String?
    public let finalURL: URL

    public init(data: Data, status: Int, etag: String?, finalURL: URL) {
        self.data = data
        self.status = status
        self.etag = etag
        self.finalURL = finalURL
    }
}

private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let origin = task.originalRequest?.url
        let target = request.url
        guard origin?.scheme == "https", target?.scheme == "https",
              origin?.host?.lowercased() == target?.host?.lowercased(),
              (origin?.port ?? 443) == (target?.port ?? 443) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// Uses an ephemeral session and never follows a redirect to another host.
public actor CalendarHTTPClient {
    private let session: URLSession
    private let redirectDelegate: SameOriginRedirectDelegate

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        let delegate = SameOriginRedirectDelegate()
        redirectDelegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    public func send(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> CalendarHTTPResult {
        guard url.scheme == "https" else { throw CalendarHTTPError.insecureURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
            throw CalendarHTTPError.responseMissing
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CalendarHTTPError.httpStatus(response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        }
        return CalendarHTTPResult(
            data: data,
            status: response.statusCode,
            etag: response.value(forHTTPHeaderField: "ETag"),
            finalURL: finalURL
        )
    }
}
