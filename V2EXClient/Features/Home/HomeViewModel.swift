import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var selectedCategory: HomePrimaryCategory = .tech
    @Published private(set) var selectedNode: HomeQuickNode?
    @Published private(set) var topics: [Topic] = []
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var loadMoreError: String?

    private let service: V2EXService
    private var currentPage = 1
    private var loadRequestID = 0

    init(service: V2EXService) {
        self.service = service
    }

    func load(refresh: Bool = false) async {
        loadRequestID += 1
        let requestID = loadRequestID
        let scope = activeScope

        if topics.isEmpty {
            state = .loading
        }

        do {
            currentPage = 1
            loadMoreError = nil
            let loaded: [Topic]
            if let node = scope.node {
                loaded = try await service.nodeTopics(name: node.name, page: currentPage, refresh: refresh)
            } else {
                loaded = try await service.categoryTopics(tab: scope.category.tabName, page: currentPage, refresh: refresh)
            }

            guard requestID == loadRequestID, scope == activeScope else {
                return
            }

            topics = loaded
            canLoadMore = !loaded.isEmpty
            state = loaded.isEmpty ? .empty : .loaded
        } catch {
            guard requestID == loadRequestID, scope == activeScope else {
                return
            }

            topics = []
            canLoadMore = false
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(currentTopic topic: Topic? = nil) async {
        guard canLoadMore, !isLoadingMore else { return }
        if let topic, topic.id != topics.last?.id { return }

        let scope = activeScope
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let loaded: [Topic]
            if let node = scope.node {
                loaded = try await service.nodeTopics(name: node.name, page: nextPage)
            } else {
                loaded = try await service.categoryTopics(tab: scope.category.tabName, page: nextPage)
            }

            guard scope == activeScope else {
                return
            }

            currentPage = nextPage
            let appendedCount = appendUnique(loaded)
            canLoadMore = !loaded.isEmpty && appendedCount > 0
        } catch {
            guard scope == activeScope else {
                return
            }

            loadMoreError = error.localizedDescription
        }
    }

    func selectCategory(_ category: HomePrimaryCategory) {
        guard selectedCategory != category else { return }
        selectedCategory = category
        selectedNode = nil
        currentPage = 1
        topics = []
        canLoadMore = false
        loadMoreError = nil
        state = .loading
        Task {
            await load()
        }
    }

    func selectSecondaryNode(_ node: HomeQuickNode) {
        guard selectedNode != node else { return }
        selectedNode = node
        currentPage = 1
        topics = []
        canLoadMore = false
        loadMoreError = nil
        state = .loading
        Task {
            await load()
        }
    }

    private var activeScope: TopicListScope {
        TopicListScope(category: selectedCategory, node: selectedNode)
    }

    private func appendUnique(_ loaded: [Topic]) -> Int {
        var seen = Set(topics.map(\.id))
        let uniqueTopics = loaded.filter { seen.insert($0.id).inserted }
        topics.append(contentsOf: uniqueTopics)
        return uniqueTopics.count
    }
}

private struct TopicListScope: Equatable {
    let category: HomePrimaryCategory
    let node: HomeQuickNode?
}
