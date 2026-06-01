import Foundation

@MainActor
final class TopicDetailViewModel: ObservableObject {
    @Published private(set) var detail: TopicDetail?
    @Published private(set) var state: LoadState = .idle

    private let topic: Topic
    private let service: V2EXService
    private var loadGeneration = 0

    init(topic: Topic, service: V2EXService) {
        self.topic = topic
        self.service = service
        if let cachedDetail = service.cachedTopicDetail(for: topic) {
            self.detail = cachedDetail
            self.state = .loaded
        }
    }

    func load(refresh: Bool = false) async {
        if !refresh {
            if detail != nil {
                if let detail {
                    preloadImages(in: detail)
                }
                state = .loaded
                return
            }

            if let cachedDetail = service.cachedTopicDetail(for: topic) {
                detail = cachedDetail
                state = .loaded
                preloadImages(in: cachedDetail)
                return
            }
        }

        loadGeneration += 1
        let generation = loadGeneration
        if detail == nil {
            state = .loading
        }
        do {
            let loadedDetail = try await service.topicDetail(for: topic, refresh: refresh)
            guard generation == loadGeneration else {
                return
            }
            detail = loadedDetail
            state = .loaded
            preloadImages(in: loadedDetail)
        } catch {
            guard generation == loadGeneration else {
                return
            }

            if error.isCancellation {
                state = detail == nil ? .idle : .loaded
            } else if detail == nil {
                state = .failed(error.localizedDescription)
            } else {
                state = .loaded
            }
        }
    }

    func updateFromLoadedHTML(_ html: String, sourceURL: URL) async {
        guard !html.isEmpty else {
            return
        }

        let loadedDetail = await service.topicDetail(
            for: topic,
            html: html,
            sourceURL: sourceURL
        )
        detail = loadedDetail
        state = .loaded
        preloadImages(in: loadedDetail)
    }

    private func preloadImages(in detail: TopicDetail) {
        let htmlFragments = [detail.contentHTML]
            + detail.supplements.map(\.contentHTML)
            + detail.replies.map(\.contentHTML)
        let urls = htmlFragments
            .flatMap(\.htmlImageURLs)

        guard !urls.isEmpty else {
            return
        }

        RemoteImageCache.shared.preload(Array(Set(urls)))
    }
}

private extension Error {
    var isCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError {
            return urlError.code == .cancelled
        }

        return (self as NSError).code == NSURLErrorCancelled
    }
}
