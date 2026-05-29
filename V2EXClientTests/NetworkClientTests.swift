import XCTest
@testable import V2EXClient

final class NetworkClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testStatusCodeFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let client = NetworkClient(session: URLSession(configuration: configuration))

        do {
            let _: Data = try await client.data(from: URL(string: "https://example.com")!)
            XCTFail("Expected a status code error")
        } catch NetworkError.statusCode(let code) {
            XCTAssertEqual(code, 500)
        }
    }

    func testNetworkClientAppliesRequestedCachePolicy() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data("ok".utf8)
            )
        }

        let client = NetworkClient(session: URLSession(configuration: configuration))

        let value = try await client.string(
            from: URL(string: "https://example.com")!,
            cachePolicy: .reloadIgnoringLocalCacheData
        )

        XCTAssertEqual(value, "ok")
        XCTAssertEqual(MockURLProtocol.lastRequest?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Pragma"), "no-cache")
    }

    func testCacheStorePersistsValuesAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let writer = CacheStore(directory: directory)
        await writer.set(["id": 42], for: "topic-v3-42")

        let reader = CacheStore(directory: directory)
        let cached: [String: Int]? = await reader.value(for: "topic-v3-42")

        XCTAssertEqual(cached?["id"], 42)

        await reader.clear()
        let cleared: [String: Int]? = await reader.value(for: "topic-v3-42")
        XCTAssertNil(cleared)
    }

    func testTopicDetailRefreshBypassesStoredAndRequestCaches() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]

        var callCount = 0
        MockURLProtocol.handler = { request in
            callCount += 1

            if callCount == 2 {
                XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
                XCTAssertNotNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first { $0.name == "_refresh" })
            }

            let viewsText = callCount == 1 ? "1 views" : "2 views"
            let html = """
            <span class="gray">By alice at 1h ago · \(viewsText)</span>
            <div class="topic_content">正文</div>
            """

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(html.utf8)
            )
        }

        let service = V2EXService(
            client: NetworkClient(session: URLSession(configuration: configuration)),
            cache: CacheStore(directory: directory)
        )
        let topic = Topic(
            id: 123,
            title: "Cache",
            url: URL(string: "https://www.v2ex.com/t/123")!,
            replies: 0,
            member: Member(id: 1, username: "alice", avatarURL: nil, tagline: nil),
            node: Node(id: 1, name: "swift", title: "Swift", topics: nil),
            createdAt: nil,
            lastReplyAt: nil
        )

        let cached = try await service.topicDetail(for: topic)
        let refreshed = try await service.topicDetail(for: topic, refresh: true)

        XCTAssertEqual(cached.viewsText, "1 views")
        XCTAssertEqual(refreshed.viewsText, "2 views")
        XCTAssertEqual(callCount, 2)
    }

    func testTopicDetailBypassesCacheWhenListReplyCountIncreases() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]

        var callCount = 0
        MockURLProtocol.handler = { request in
            callCount += 1
            let replyHTML = callCount == 1
                ? #"<div id="r_1"><div class="reply_content">旧回复</div></div>"#
                : #"<div id="r_1"><div class="reply_content">旧回复</div></div><div id="r_2"><div class="reply_content">新回复</div></div>"#
            let html = """
            <span class="gray">By alice at 1h ago · \(callCount) views</span>
            <div class="topic_content">正文</div>
            \(replyHTML)
            """

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(html.utf8)
            )
        }

        let service = V2EXService(
            client: NetworkClient(session: URLSession(configuration: configuration)),
            cache: CacheStore(directory: directory)
        )
        let staleTopic = Topic(
            id: 124,
            title: "Cache",
            url: URL(string: "https://www.v2ex.com/t/124")!,
            replies: 1,
            member: Member(id: 1, username: "alice", avatarURL: nil, tagline: nil),
            node: Node(id: 1, name: "swift", title: "Swift", topics: nil),
            createdAt: nil,
            lastReplyAt: nil
        )
        let updatedTopic = Topic(
            id: 124,
            title: "Cache",
            url: URL(string: "https://www.v2ex.com/t/124")!,
            replies: 2,
            member: staleTopic.member,
            node: staleTopic.node,
            createdAt: nil,
            lastReplyAt: nil
        )

        let cached = try await service.topicDetail(for: staleTopic)
        let updated = try await service.topicDetail(for: updatedTopic)

        XCTAssertEqual(cached.replies.count, 1)
        XCTAssertEqual(updated.replies.count, 2)
        XCTAssertEqual(callCount, 2)
    }

    func testCategoryTopicsFallbackToLatestWhenWebParsingIsEmpty() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { request in
            let body: String
            if request.url?.path == "/api/topics/latest.json" {
                body = """
                [
                  {
                    "id": 101,
                    "title": "技术主题",
                    "url": "https://www.v2ex.com/t/101",
                    "replies": 3,
                    "member": {"id": 1, "username": "alice"},
                    "node": {"id": 1, "name": "programmer", "title": "程序员", "topics": 10},
                    "created": 1760000000
                  },
                  {
                    "id": 102,
                    "title": "生活主题",
                    "url": "https://www.v2ex.com/t/102",
                    "replies": 1,
                    "member": {"id": 2, "username": "bob"},
                    "node": {"id": 2, "name": "life", "title": "生活", "topics": 8},
                    "created": 1760000001
                  }
                ]
                """
            } else {
                body = """
                <!doctype html>
                <html><body><div class="box">暂时没有匹配当前解析器的列表项</div></body></html>
                """
            }

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(body.utf8)
            )
        }

        let service = V2EXService(
            client: NetworkClient(session: URLSession(configuration: configuration)),
            cache: CacheStore(directory: directory)
        )

        let topics = try await service.categoryTopics(tab: "tech", refresh: true)

        XCTAssertEqual(topics.map(\.id), [101])
        XCTAssertEqual(topics.first?.node.name, "programmer")
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
