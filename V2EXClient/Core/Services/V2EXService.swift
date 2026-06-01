import Foundation

final class V2EXService {
    private let client: NetworkClient
    private let cache: CacheStore
    private let parser: TopicDetailParser
    private let nodeTopicListParser = NodeTopicListParser()
    private let nodeCatalog = NodeCatalog.shared
    private let memoryCache = NSCache<NSString, AnyCacheBox>()
    private let baseURL = URL(string: "https://www.v2ex.com")!

    init(
        client: NetworkClient = NetworkClient(),
        cache: CacheStore = .shared,
        parser: TopicDetailParser = TopicDetailParser()
    ) {
        self.client = client
        self.cache = cache
        self.parser = parser
    }

    func topics(feed: TopicFeed, refresh: Bool = false) async throws -> [Topic] {
        let cacheKey = topicsCacheKey(feed: feed)
        if !refresh, let cached: [Topic] = memoryValue(for: cacheKey) {
            return cached
        }

        if !refresh, let cached: [Topic] = await cache.value(for: cacheKey) {
            setMemory(cached, for: cacheKey)
            return cached
        }

        let path = feed == .hot ? "/api/topics/hot.json" : "/api/topics/latest.json"
        let dtos: [LegacyTopicDTO] = try await client.get(
            baseURL.appending(path: path),
            cachePolicy: cachePolicy(refresh: refresh)
        )
        let topics = dtos.compactMap { $0.topic }
        setMemory(topics, for: cacheKey)
        await cache.set(topics, for: cacheKey)
        return topics
    }

    func cachedTopicDetail(for topic: Topic) -> TopicDetail? {
        guard let cached: TopicDetail = memoryValue(for: topicDetailCacheKey(for: topic)) else {
            return nil
        }

        let cachedReplyCount = max(cached.topic.replies, cached.replies.count)
        guard cachedReplyCount >= topic.replies else {
            return nil
        }

        return cached
    }

    func topicDetail(for topic: Topic, refresh: Bool = false) async throws -> TopicDetail {
        let cacheKey = topicDetailCacheKey(for: topic)
        if !refresh, let cached = cachedTopicDetail(for: topic) {
            return cached
        }

        if !refresh, let cached: TopicDetail = await cache.value(for: cacheKey) {
            let cachedReplyCount = max(cached.topic.replies, cached.replies.count)
            if cachedReplyCount >= topic.replies {
                setMemory(cached, for: cacheKey)
                return cached
            }
        }

        let requestURL = topicDetailURL(for: topic.webURL, refresh: refresh)
        let html = try await client.string(
            from: requestURL,
            cachePolicy: cachePolicy(refresh: refresh)
        )
        let detail = await topicDetail(for: topic, html: html, sourceURL: topic.webURL)
        return detail
    }

    func topicDetail(for topic: Topic, html: String, sourceURL: URL? = nil) async -> TopicDetail {
        let cacheKey = topicDetailCacheKey(for: topic)
        let parser = parser
        let detail = await Task.detached(priority: .userInitiated) {
            parser.parse(html: html, topic: topic, sourceURL: sourceURL ?? topic.webURL)
        }.value
        setMemory(detail, for: cacheKey)
        await cache.set(detail, for: cacheKey)
        return detail
    }

    func cachedNode(named name: String) -> Node? {
        guard let cached: Node = memoryValue(for: nodeCacheKey(name: name)) else {
            return nil
        }
        return nodeCatalog.merge(cached)
    }

    func node(named name: String, refresh: Bool = false) async throws -> Node {
        let cacheKey = nodeCacheKey(name: name)
        if !refresh, let cached = cachedNode(named: name) {
            return cached
        }

        if !refresh, let cached: Node = await cache.value(for: cacheKey) {
            let node = nodeCatalog.merge(cached)
            setMemory(node, for: cacheKey)
            return node
        }

        var components = URLComponents(url: baseURL.appending(path: "/api/nodes/show.json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        let dto: LegacyNodeDTO = try await client.get(
            components.url!,
            cachePolicy: cachePolicy(refresh: refresh)
        )
        let node = nodeCatalog.merge(dto.node)
        setMemory(node, for: cacheKey)
        await cache.set(node, for: cacheKey)
        return node
    }

    func bundledNodes() -> [Node] {
        nodeCatalog.nodes
    }

    func allNodes(refresh: Bool = false) async throws -> [Node] {
        let cacheKey = "nodes-all"
        if !refresh, let cached: [Node] = memoryValue(for: cacheKey) {
            return nodeCatalog.merged(cached)
        }

        if !refresh, let cached: [Node] = await cache.value(for: cacheKey) {
            let nodes = nodeCatalog.merged(cached)
            setMemory(nodes, for: cacheKey)
            return nodes
        }

        let dtos: [LegacyNodeDTO] = try await client.get(
            baseURL.appending(path: "/api/nodes/all.json"),
            cachePolicy: cachePolicy(refresh: refresh)
        )
        let nodes = nodeCatalog.merged(dtos.map(\.node))
        setMemory(nodes, for: cacheKey)
        await cache.set(nodes, for: cacheKey)
        return nodes
    }

    func cachedNodeTopics(name: String, page: Int = 1) -> [Topic]? {
        memoryValue(for: nodeTopicsCacheKey(name: name, page: page))
    }

    func nodeTopics(name: String, page: Int = 1, refresh: Bool = false) async throws -> [Topic] {
        let cacheKey = nodeTopicsCacheKey(name: name, page: page)
        if !refresh, let cached: [Topic] = memoryValue(for: cacheKey) {
            if !cached.isEmpty || page > 1 {
                return cached
            }
        }

        if !refresh, let cached: [Topic] = await cache.value(for: cacheKey) {
            if !cached.isEmpty || page > 1 {
                setMemory(cached, for: cacheKey)
                return cached
            }
        }

        do {
            let topics = try await webNodeTopics(name: name, page: page, refresh: refresh)
            if !topics.isEmpty || page > 1 {
                setMemory(topics, for: cacheKey)
                await cache.set(topics, for: cacheKey)
                return topics
            }
        } catch {
            if page > 1 {
                throw error
            }
            // Fall through to legacy first-page sources.
        }

        if page == 1 {
            do {
                var components = URLComponents(url: baseURL.appending(path: "/api/topics/show.json"), resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "node_name", value: name)]
                let topics: [LegacyTopicDTO] = try await client.get(
                    components.url!,
                    cachePolicy: cachePolicy(refresh: refresh)
                )
                let mapped = topics.compactMap(\.topic)
                if !mapped.isEmpty {
                    setMemory(mapped, for: cacheKey)
                    await cache.set(mapped, for: cacheKey)
                    return mapped
                }
            } catch {
                // Fall through to secondary sources.
            }
        }

        let latest = try await topics(feed: .latest, refresh: refresh)
        let filtered = latest.filter { $0.node.name.caseInsensitiveCompare(name) == .orderedSame }
        setMemory(filtered, for: cacheKey)
        await cache.set(filtered, for: cacheKey)
        return filtered
    }

    func cachedCategoryTopics(tab: String, page: Int = 1) -> [Topic]? {
        memoryValue(for: categoryTopicsCacheKey(tab: tab, page: page))
    }

    func categoryTopics(tab: String, page: Int = 1, refresh: Bool = false) async throws -> [Topic] {
        let cacheKey = categoryTopicsCacheKey(tab: tab, page: page)
        if !refresh, let cached: [Topic] = memoryValue(for: cacheKey) {
            if !cached.isEmpty || page > 1 {
                return cached
            }
        }

        if !refresh, let cached: [Topic] = await cache.value(for: cacheKey) {
            if !cached.isEmpty || page > 1 {
                setMemory(cached, for: cacheKey)
                return cached
            }
        }

        do {
            let topics = try await webCategoryTopics(tab: tab, page: page, refresh: refresh)
            if !topics.isEmpty || page > 1 {
                setMemory(topics, for: cacheKey)
                await cache.set(topics, for: cacheKey)
                return topics
            }
        } catch {
            if page > 1 {
                throw error
            }
        }

        if page == 1 {
            let fallbackFeed: TopicFeed? = switch tab {
            case "hot": .hot
            case "all": .latest
            default: nil
            }

            if let fallbackFeed {
                let topics = try await topics(feed: fallbackFeed, refresh: refresh)
                setMemory(topics, for: cacheKey)
                await cache.set(topics, for: cacheKey)
                return topics
            }

            let fallbackTopics = try await categoryFallbackTopics(tab: tab, refresh: refresh)
            if !fallbackTopics.isEmpty {
                setMemory(fallbackTopics, for: cacheKey)
                await cache.set(fallbackTopics, for: cacheKey)
                return fallbackTopics
            }
        }

        setMemory([Topic](), for: cacheKey)
        await cache.set([Topic](), for: cacheKey)
        return []
    }

    func member(username: String, refresh: Bool = false) async throws -> Member {
        let cacheKey = "member-\(username)"
        if !refresh, let cached: Member = await cache.value(for: cacheKey) {
            return cached
        }

        var components = URLComponents(url: baseURL.appending(path: "/api/members/show.json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "username", value: username)]
        let dto: LegacyMemberDTO = try await client.get(
            components.url!,
            cachePolicy: cachePolicy(refresh: refresh)
        )
        let member = dto.member
        await cache.set(member, for: cacheKey)
        return member
    }

    func clearCache() async {
        memoryCache.removeAllObjects()
        await cache.clear()
        URLCache.shared.removeAllCachedResponses()
        await RemoteImageCache.shared.clear()
        await MainActor.run {
            NotificationCenter.default.post(name: .v2exCacheDidClear, object: nil)
        }
    }

    func cacheSizeBytes() async -> Int64 {
        let dataCacheSize = await cache.diskUsage()
        let imageCacheSize = await RemoteImageCache.shared.diskUsage()
        return dataCacheSize
            + Int64(URLCache.shared.currentDiskUsage)
            + imageCacheSize
    }

    private func cachePolicy(refresh: Bool) -> URLRequest.CachePolicy {
        refresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
    }

    private func memoryValue<T>(for key: String, as type: T.Type = T.self) -> T? {
        memoryCache.object(forKey: key as NSString)?.value as? T
    }

    private func setMemory<T>(_ value: T, for key: String) {
        memoryCache.setObject(AnyCacheBox(value), forKey: key as NSString)
    }

    private func topicsCacheKey(feed: TopicFeed) -> String {
        "topics-\(feed.rawValue)"
    }

    private func topicDetailCacheKey(for topic: Topic) -> String {
        "topic-v5-\(topic.id)"
    }

    private func nodeCacheKey(name: String) -> String {
        "node-\(name)"
    }

    private func nodeTopicsCacheKey(name: String, page: Int) -> String {
        "node-topics-web-\(name)-page-\(page)"
    }

    private func categoryTopicsCacheKey(tab: String, page: Int) -> String {
        "category-topics-web-\(tab)-page-\(page)"
    }

    private func topicDetailURL(for url: URL, refresh: Bool) -> URL {
        guard refresh,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "_refresh", value: String(Int(Date().timeIntervalSince1970 * 1000))))
        components.queryItems = queryItems
        return components.url ?? url
    }

    private func webNodeTopics(name: String, page: Int, refresh: Bool) async throws -> [Topic] {
        var components = URLComponents(url: baseURL.appending(path: "/go/\(name)"), resolvingAgainstBaseURL: false)!
        if page > 1 {
            components.queryItems = [URLQueryItem(name: "p", value: String(page))]
        }
        let html = try await client.string(
            from: components.url!,
            cachePolicy: cachePolicy(refresh: refresh)
        )
        return nodeTopicListParser.parse(html: html, fallbackNodeName: name)
    }

    private func webCategoryTopics(tab: String, page: Int, refresh: Bool) async throws -> [Topic] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "tab", value: tab)]
        if page > 1 {
            queryItems.append(URLQueryItem(name: "p", value: String(page)))
        }
        components.queryItems = queryItems

        let html = try await client.string(
            from: components.url!,
            cachePolicy: cachePolicy(refresh: refresh)
        )
        return nodeTopicListParser.parseCells(html: html, fallbackNodeName: tab)
    }

    private func categoryFallbackTopics(tab: String, refresh: Bool) async throws -> [Topic] {
        guard let nodeNames = fallbackNodeNamesByCategory[tab], !nodeNames.isEmpty else {
            return []
        }

        let latestTopics = try await topics(feed: .latest, refresh: refresh)
        return latestTopics.filter { topic in
            nodeNames.contains(topic.node.name.lowercased())
        }
    }

    private var fallbackNodeNamesByCategory: [String: Set<String>] {
        [
            "tech": ["programmer", "python", "idev", "claude", "openai", "localllm", "cloud", "bb"],
            "creative": ["create", "design", "ideas", "share", "blog", "starter"],
            "play": ["games", "movie", "tv", "music", "travel", "reading"],
            "apple": ["apple", "macos", "iphone", "ios", "ipad", "xcode", "airpods"],
            "jobs": ["jobs", "remote", "career", "cv", "outsourcing"],
            "deals": ["all4all", "deals", "invest", "creditcard"],
            "city": ["beijing", "shanghai", "shenzhen", "hangzhou", "chengdu", "guangzhou", "hongkong", "wuhan"],
            "qna": ["qna", "share"]
        ]
    }
}

private final class AnyCacheBox: NSObject {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}

private struct LegacyTopicDTO: Decodable {
    let id: Int
    let title: String
    let url: String?
    let replies: Int?
    let member: LegacyMemberDTO
    let node: LegacyNodeDTO
    let created: TimeInterval?
    let lastModified: TimeInterval?
    let lastTouched: TimeInterval?

    var topic: Topic? {
        let fallbackURL = URL(string: "https://www.v2ex.com/t/\(id)")
        guard let topicURL = url.flatMap(URL.init(string:)) ?? fallbackURL else { return nil }
        return Topic(
            id: id,
            title: title.decodedHTML,
            url: topicURL,
            replies: replies ?? 0,
            member: member.member,
            node: node.node,
            createdAt: created.map(Date.init(timeIntervalSince1970:)),
            lastReplyAt: (lastTouched ?? lastModified).map(Date.init(timeIntervalSince1970:))
        )
    }
}

private struct LegacyMemberDTO: Decodable {
    let id: Int?
    let username: String
    let avatarMini: String?
    let avatarNormal: String?
    let avatarLarge: String?
    let tagline: String?
    let bio: String?

    var member: Member {
        Member(
            id: id,
            username: username,
            avatarURL: normalizedAvatarURL,
            tagline: tagline ?? bio
        )
    }

    private var normalizedAvatarURL: URL? {
        let raw = avatarLarge ?? avatarNormal ?? avatarMini
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }
        return URL(string: raw)
    }
}

private struct LegacyNodeDTO: Decodable {
    let id: Int?
    let name: String
    let title: String
    let topics: Int?
    let avatarNormal: String?

    var node: Node {
        Node(
            id: id,
            name: name,
            title: title.decodedHTML,
            topics: topics,
            avatarURL: normalizedAvatarURL
        )
    }

    private var normalizedAvatarURL: URL? {
        guard let avatarNormal, !avatarNormal.isEmpty else {
            return nil
        }
        if avatarNormal.hasPrefix("//") {
            return URL(string: "https:\(avatarNormal)")
        }
        if avatarNormal.hasPrefix("/") {
            return URL(string: "https://www.v2ex.com\(avatarNormal)")
        }
        return URL(string: avatarNormal)
    }
}

struct NodeTopicListParser: Sendable {
    private let baseURL = URL(string: "https://www.v2ex.com")!

    func parse(html: String, fallbackNodeName: String) -> [Topic] {
        let fallbackNode = Node(
            id: nil,
            name: fallbackNodeName,
            title: pageNodeTitle(in: html) ?? fallbackNodeName.decodedHTML,
            topics: pageTopicCount(in: html)
        )

        let cellTopics = parseCellTopics(html: html, fallbackNode: fallbackNode)
        if !cellTopics.isEmpty {
            return cellTopics
        }

        return parseSchemaTopics(html: html, fallbackNode: fallbackNode)
    }

    func parseCells(html: String, fallbackNodeName: String) -> [Topic] {
        let fallbackNode = Node(
            id: nil,
            name: fallbackNodeName,
            title: fallbackNodeName.decodedHTML,
            topics: nil
        )
        return parseCellTopics(html: html, fallbackNode: fallbackNode)
    }

    private func parseSchemaTopics(html: String, fallbackNode: Node) -> [Topic] {
        guard let json = firstCapture(
            in: html,
            pattern: #"(?is)<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        ),
              let data = json.data(using: .utf8),
              let page = try? JSONDecoder().decode(NodePageSchema.self, from: data) else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        return (page.mainEntity?.itemListElement ?? []).compactMap { element in
            guard let item = element.item,
                  let url = URL(string: item.url),
                  let id = topicID(from: url.absoluteString) else {
                return nil
            }

            return Topic(
                id: id,
                title: item.headline.decodedHTML,
                url: url,
                replies: item.commentCount ?? 0,
                member: Member(
                    id: nil,
                    username: item.author?.name ?? "",
                    avatarURL: nil,
                    tagline: nil
                ),
                node: fallbackNode,
                createdAt: item.datePublished.flatMap { formatter.date(from: $0) },
                lastReplyAt: nil
            )
        }
    }

    private func parseCellTopics(html: String, fallbackNode: Node) -> [Topic] {
        let rows = cellRows(in: html)
        if !rows.isEmpty {
            return rows.compactMap { parseCellTopic(row: $0, fallbackNode: fallbackNode) }
        }

        return parseCellTopic(row: html, fallbackNode: fallbackNode).map { [$0] } ?? []
    }

    private func parseCellTopic(row: String, fallbackNode: Node) -> Topic? {
        let pattern = #"<a(?=[^>]*class=["'][^"']*\btopic-link\b[^"']*["'])(?=[^>]*href=["']([^"']*?/t/(\d+)[^"']*)["'])[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let nsRange = NSRange(row.startIndex..<row.endIndex, in: row)
        guard let match = regex.firstMatch(in: row, range: nsRange),
              let hrefRange = Range(match.range(at: 1), in: row),
              let idRange = Range(match.range(at: 2), in: row),
              let titleRange = Range(match.range(at: 3), in: row),
              let id = Int(row[idRange]),
              let url = normalizedURL(String(row[hrefRange])) else {
            return nil
        }

        let member = parsedMember(from: row)
        let node = parsedNode(from: row) ?? fallbackNode
        let activityDate = parsedDate(from: row)
        return Topic(
            id: id,
            title: String(row[titleRange]).strippedHTML,
            url: url,
            replies: parsedReplyCount(from: row),
            member: member,
            node: node,
            createdAt: activityDate,
            lastReplyAt: activityDate
        )
    }

    private func cellRows(in html: String) -> [String] {
        let cellStartPattern = #"<div\b[^>]*\bclass=["'][^"']*\bcell\b"#
        guard let regex = try? NSRegularExpression(pattern: cellStartPattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: nsRange)
        return matches.enumerated().compactMap { index, match in
            guard let lower = Range(match.range, in: html)?.lowerBound else {
                return nil
            }

            let upper: String.Index
            if index + 1 < matches.count,
               let nextLower = Range(matches[index + 1].range, in: html)?.lowerBound {
                upper = nextLower
            } else {
                upper = html.endIndex
            }

            return String(html[lower..<upper])
        }
    }

    private func parsedMember(from row: String) -> Member {
        let username = firstCapture(in: row, pattern: #"href=["']/member/([^"']+)["']"#) ?? ""
        let avatar = firstCapture(in: row, pattern: #"<img(?=[^>]*\bavatar\b)[^>]*src=["']([^"']+)["']"#)
            .flatMap(normalizedURL)
        let id = firstCapture(in: row, pattern: #"\bdata-uid=["'](\d+)["']"#).flatMap(Int.init)
        return Member(id: id, username: username.decodedHTML, avatarURL: avatar, tagline: nil)
    }

    private func parsedNode(from row: String) -> Node? {
        guard let name = firstCapture(in: row, pattern: #"href=["']/go/([^"']+)["']"#) else {
            return nil
        }
        let title = firstCapture(in: row, pattern: #"<a[^>]*href=["']/go/\#(NSRegularExpression.escapedPattern(for: name))["'][^>]*>(.*?)</a>"#)?
            .strippedHTML
        return Node(id: nil, name: name.decodedHTML, title: title ?? name.decodedHTML, topics: nil)
    }

    private func parsedReplyCount(from row: String) -> Int {
        firstCapture(in: row, pattern: #"<a[^>]*class=["'][^"']*\bcount_(?:livid|orange)\b[^"']*["'][^>]*>(\d+)</a>"#)
            .flatMap(Int.init) ?? 0
    }

    private func parsedDate(from row: String) -> Date? {
        guard let value = firstCapture(in: row, pattern: #"<span[^>]*title=["']([^"']+)["']"#) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter.date(from: value)
    }

    private func pageNodeTitle(in html: String) -> String? {
        guard let rawTitle = firstCapture(in: html, pattern: #"(?is)<title>\s*V2EX\s*›\s*(.*?)\s*</title>"#) else {
            return nil
        }
        return rawTitle.strippedHTML
    }

    private func pageTopicCount(in html: String) -> Int? {
        firstCapture(in: html, pattern: #""numberOfItems"\s*:\s*(\d+)"#).flatMap(Int.init)
    }

    private func topicID(from value: String) -> Int? {
        firstCapture(in: value, pattern: #"/t/(\d+)"#).flatMap(Int.init)
    }

    private func normalizedURL(_ rawValue: String) -> URL? {
        let decoded = rawValue.decodedHTML
        if decoded.hasPrefix("//") {
            return URL(string: "https:\(decoded)")
        }
        if decoded.hasPrefix("/") {
            return URL(string: decoded, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: decoded)
    }

    private func firstCapture(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[range])
    }
}

private struct NodePageSchema: Decodable {
    let mainEntity: NodePageItemList?
}

private struct NodePageItemList: Decodable {
    let itemListElement: [NodePageListElement]?
}

private struct NodePageListElement: Decodable {
    let item: NodePageTopicItem?
}

private struct NodePageTopicItem: Decodable {
    let url: String
    let headline: String
    let commentCount: Int?
    let author: NodePageAuthor?
    let datePublished: String?
}

private struct NodePageAuthor: Decodable {
    let name: String
}
