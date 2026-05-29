import Foundation

struct Topic: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let url: URL
    let replies: Int
    let member: Member
    let node: Node
    let createdAt: Date?
    let lastReplyAt: Date?

    var webURL: URL {
        URL(string: "https://www.v2ex.com/t/\(id)") ?? url
    }
}

struct Member: Identifiable, Codable, Hashable {
    let id: Int?
    let username: String
    let avatarURL: URL?
    let tagline: String?
}

struct Node: Identifiable, Codable, Hashable {
    let id: Int?
    let name: String
    let title: String
    let topics: Int?
    let avatarURL: URL?

    init(id: Int?, name: String, title: String, topics: Int?, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.title = title
        self.topics = topics
        self.avatarURL = avatarURL
    }

    var path: String {
        "/go/\(name)"
    }

    var iconURL: URL? {
        if let avatarURL {
            return avatarURL
        }
        guard let id else { return nil }
        return Self.navatarURL(for: id)
    }

    private static func navatarURL(for id: Int) -> URL? {
        let digest = String.md5HexDigest(for: String(id))
        let first = String(digest.prefix(4))
        let secondStart = digest.index(digest.startIndex, offsetBy: 4)
        let secondEnd = digest.index(digest.startIndex, offsetBy: 8)
        let second = String(digest[secondStart..<secondEnd])
        return URL(string: "https://cdn.v2ex.com/navatar/\(first)/\(second)/\(id)_normal.png")
    }
}

struct Reply: Identifiable, Codable, Hashable {
    let id: Int
    let floor: Int
    let member: Member
    let contentHTML: String
    let createdAt: Date?
    let createdText: String?
}

struct TopicSupplement: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let contentHTML: String
}

struct TopicDetail: Codable, Hashable {
    let topic: Topic
    let contentHTML: String
    let createdText: String?
    let viewsText: String?
    let supplements: [TopicSupplement]
    let replies: [Reply]
    let sourceURL: URL
}

enum TopicFeed: String, CaseIterable, Identifiable {
    case hot
    case latest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hot: "热门"
        case .latest: "最新"
        }
    }
}

enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}
