import Foundation

enum NetworkError: LocalizedError, Equatable {
    case invalidResponse
    case statusCode(Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "服务器响应无效"
        case .statusCode(let code):
            "请求失败，状态码 \(code)"
        case .decodingFailed(let message):
            "数据解析失败：\(message)"
        }
    }
}

final class NetworkClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func get<T: Decodable>(
        _ url: URL,
        as type: T.Type = T.self,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> T {
        let data = try await data(from: url, cachePolicy: cachePolicy)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error.localizedDescription)
        }
    }

    func string(
        from url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> String {
        let data = try await data(from: url, cachePolicy: cachePolicy)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    func data(
        from url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.timeoutInterval = 20
        request.setValue("V2EXClient/0.1 iOS", forHTTPHeaderField: "User-Agent")
        switch cachePolicy {
        case .reloadIgnoringLocalCacheData, .reloadIgnoringLocalAndRemoteCacheData:
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        default:
            break
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw NetworkError.statusCode(httpResponse.statusCode)
        }
        return data
    }
}
