import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet {
            applySearch()
        }
    }
    @Published private(set) var results: [Node] = []
    @Published private(set) var state: LoadState = .idle

    private let service: V2EXService
    private var nodes: [Node] = []

    init(service: V2EXService) {
        self.service = service
    }

    func load(refresh: Bool = false) async {
        if nodes.isEmpty {
            state = .loading
        }

        do {
            nodes = try await service.allNodes(refresh: refresh)
            applySearch()
            state = results.isEmpty ? .empty : .loaded
        } catch {
            results = []
            state = .failed(error.localizedDescription)
        }
    }

    private func applySearch() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = trimmedQuery.isEmpty
            ? nodes
            : nodes.filter { node in
                node.name.localizedCaseInsensitiveContains(trimmedQuery)
                    || node.title.localizedCaseInsensitiveContains(trimmedQuery)
            }

        results = candidates.sorted { lhs, rhs in
            compare(lhs, rhs, query: trimmedQuery)
        }
    }

    private func compare(_ lhs: Node, _ rhs: Node, query: String) -> Bool {
        if !query.isEmpty {
            let lhsRank = matchRank(lhs, query: query)
            let rhsRank = matchRank(rhs, query: query)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
        }

        let lhsTopics = lhs.topics ?? 0
        let rhsTopics = rhs.topics ?? 0
        if lhsTopics != rhsTopics {
            return lhsTopics > rhsTopics
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func matchRank(_ node: Node, query: String) -> Int {
        if node.name.range(of: query, options: [.caseInsensitive, .anchored]) != nil {
            return 0
        }
        if node.title.range(of: query, options: [.caseInsensitive, .anchored]) != nil {
            return 1
        }
        if node.name.localizedCaseInsensitiveContains(query) {
            return 2
        }
        return 3
    }
}
