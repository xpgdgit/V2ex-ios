import Foundation

@MainActor
final class NodeViewModel: ObservableObject {
    @Published private(set) var node: Node?
    @Published private(set) var topics: [Topic] = []
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var loadMoreError: String?
    @Published var isFavorite = false

    private let nodeName: String
    private let service: V2EXService
    private let favoritesKey = "favorite_nodes"
    private var currentPage = 1

    init(nodeName: String, service: V2EXService) {
        self.nodeName = nodeName
        self.service = service
        self.isFavorite = UserDefaults.standard.stringArray(forKey: favoritesKey)?.contains(nodeName) ?? false
        applyCachedContent()
    }

    func load(refresh: Bool = false) async {
        if !refresh {
            if !topics.isEmpty, node != nil, state == .loaded {
                return
            }

            if applyCachedContent() {
                return
            }
        }

        if topics.isEmpty {
            state = .loading
        }
        do {
            currentPage = 1
            loadMoreError = nil
            async let node = service.node(named: nodeName, refresh: refresh)
            async let topics = service.nodeTopics(name: nodeName, page: currentPage, refresh: refresh)
            self.node = try await node
            self.topics = try await topics
            canLoadMore = !self.topics.isEmpty
            state = self.topics.isEmpty ? .empty : .loaded
        } catch {
            canLoadMore = false
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(currentTopic topic: Topic? = nil) async {
        guard canLoadMore, !isLoadingMore else { return }
        if let topic, topic.id != topics.last?.id { return }

        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let loaded = try await service.nodeTopics(name: nodeName, page: nextPage)
            currentPage = nextPage
            let appendedCount = appendUnique(loaded)
            canLoadMore = !loaded.isEmpty && appendedCount > 0
        } catch {
            loadMoreError = error.localizedDescription
        }
    }

    func toggleFavorite() {
        var favorites = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        if isFavorite {
            favorites.removeAll { $0 == nodeName }
        } else {
            favorites.append(nodeName)
        }
        UserDefaults.standard.set(Array(Set(favorites)).sorted(), forKey: favoritesKey)
        isFavorite.toggle()
    }

    @discardableResult
    private func applyCachedContent() -> Bool {
        var didApply = false

        if let cachedNode = service.cachedNode(named: nodeName) {
            node = cachedNode
            didApply = true
        }

        if let cachedTopics = service.cachedNodeTopics(name: nodeName), !cachedTopics.isEmpty {
            topics = cachedTopics
            canLoadMore = true
            state = .loaded
            didApply = true
        } else if didApply, topics.isEmpty {
            state = .empty
        }

        return node != nil && !topics.isEmpty
    }

    private func appendUnique(_ loaded: [Topic]) -> Int {
        var seen = Set(topics.map(\.id))
        let uniqueTopics = loaded.filter { seen.insert($0.id).inserted }
        topics.append(contentsOf: uniqueTopics)
        return uniqueTopics.count
    }
}
