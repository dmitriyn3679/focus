import Foundation

protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum RedirectPolicy {
    static func allows(from original: URL?, to redirect: URL?) -> Bool {
        guard
            let original,
            let redirect,
            redirect.scheme?.lowercased() == "https",
            let originalHost = original.host?.lowercased(),
            let redirectHost = redirect.host?.lowercased()
        else { return false }
        return originalHost == redirectHost
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(RedirectPolicy.allows(from: task.originalRequest?.url, to: request.url) ? request : nil)
    }
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
