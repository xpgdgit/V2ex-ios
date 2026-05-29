import Foundation

struct NodeCatalog {
    static let shared = NodeCatalog()

    let nodes: [Node]

    private let nodesByName: [String: Node]

    private init() {
        self.nodes = Self.bundledNodes
        self.nodesByName = Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, $0) })
    }

    func merge(_ node: Node) -> Node {
        guard let bundled = nodesByName[node.name] else {
            return node
        }

        return Node(
            id: node.id ?? bundled.id,
            name: node.name,
            title: node.title.isEmpty ? bundled.title : node.title,
            topics: node.topics ?? bundled.topics,
            avatarURL: node.avatarURL ?? bundled.avatarURL
        )
    }

    func merged(_ remoteNodes: [Node]) -> [Node] {
        let mergedRemoteNodes = remoteNodes.map(merge)
        let remoteNames = Set(mergedRemoteNodes.map(\.name))
        return mergedRemoteNodes + nodes.filter { !remoteNames.contains($0.name) }
    }

    private static let bundledNodes: [Node] = [
        Node(id: 12, name: "qna", title: "问与答", topics: nil),
        Node(id: 69, name: "all4all", title: "二手交易", topics: nil),
        Node(id: 300, name: "programmer", title: "程序员", topics: nil),
        Node(id: 43, name: "jobs", title: "酷工作", topics: nil),
        Node(id: 16, name: "share", title: "分享发现", topics: nil),
        Node(id: 17, name: "create", title: "分享创造", topics: nil),
        Node(id: 184, name: "apple", title: "Apple", topics: nil),
        Node(id: 22, name: "macos", title: "macOS", topics: nil),
        Node(id: 90, name: "python", title: "Python", topics: nil),
        Node(id: 13, name: "idev", title: "iDev", topics: nil),
        Node(id: 1148, name: "claude", title: "Claude", topics: nil),
        Node(id: 1135, name: "openai", title: "OpenAI", topics: nil),
        Node(id: 722, name: "localllm", title: "Local LLM", topics: nil),
        Node(id: 104, name: "cloud", title: "云计算", topics: nil),
        Node(id: 108, name: "bb", title: "宽带症候群", topics: nil),
        Node(id: 215, name: "design", title: "设计", topics: nil),
        Node(id: 519, name: "ideas", title: "奇思妙想", topics: nil),
        Node(id: 373, name: "blog", title: "Blog", topics: nil),
        Node(id: 122, name: "starter", title: "创造者", topics: nil),
        Node(id: 55, name: "games", title: "游戏", topics: nil),
        Node(id: 5, name: "movie", title: "电影", topics: nil),
        Node(id: 48, name: "tv", title: "剧集", topics: nil),
        Node(id: 4, name: "music", title: "音乐", topics: nil),
        Node(id: 181, name: "travel", title: "旅行", topics: nil),
        Node(id: 111, name: "reading", title: "阅读", topics: nil),
        Node(id: 8, name: "iphone", title: "iPhone", topics: nil),
        Node(id: 580, name: "ios", title: "iOS", topics: nil),
        Node(id: 9, name: "ipad", title: "iPad", topics: nil),
        Node(id: 489, name: "xcode", title: "Xcode", topics: nil),
        Node(id: 1103, name: "airpods", title: "AirPods", topics: nil),
        Node(id: 1051, name: "remote", title: "远程工作", topics: nil),
        Node(id: 770, name: "career", title: "职场话题", topics: nil),
        Node(id: 507, name: "cv", title: "求职", topics: nil),
        Node(id: 190, name: "outsourcing", title: "外包", topics: nil),
        Node(id: 747, name: "deals", title: "优惠信息", topics: nil),
        Node(id: 171, name: "invest", title: "投资", topics: nil),
        Node(id: 205, name: "creditcard", title: "信用卡", topics: nil),
        Node(id: 19, name: "beijing", title: "北京", topics: nil),
        Node(id: 18, name: "shanghai", title: "上海", topics: nil),
        Node(id: 21, name: "shenzhen", title: "深圳", topics: nil),
        Node(id: 26, name: "hangzhou", title: "杭州", topics: nil),
        Node(id: 30, name: "chengdu", title: "成都", topics: nil),
        Node(id: 20, name: "guangzhou", title: "广州", topics: nil),
        Node(id: 113, name: "hongkong", title: "香港", topics: nil),
        Node(id: 80, name: "wuhan", title: "武汉", topics: nil)
    ]
}
