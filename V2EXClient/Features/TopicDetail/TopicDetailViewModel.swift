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
        let startedAt = Date()
        #if DEBUG
        logViewModelTiming("load-start topic=\(topic.id) refresh=\(refresh) hasDetail=\(detail != nil)")
        #endif

        if !refresh {
            if detail != nil {
                if let detail {
                    preloadImages(in: detail)
                }
                state = .loaded
                #if DEBUG
                logViewModelTiming("load-skip-existing topic=\(topic.id) elapsed=\(Self.elapsedMilliseconds(since: startedAt))ms")
                #endif
                return
            }

            if let cachedDetail = service.cachedTopicDetail(for: topic) {
                detail = cachedDetail
                state = .loaded
                preloadImages(in: cachedDetail)
                #if DEBUG
                logViewModelTiming("load-memory-cache topic=\(topic.id) elapsed=\(Self.elapsedMilliseconds(since: startedAt))ms replies=\(cachedDetail.replies.count)")
                #endif
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
            let publishStartedAt = Date()
            detail = loadedDetail
            state = .loaded
            preloadImages(in: loadedDetail)
            #if DEBUG
            logViewModelTiming("load-published topic=\(topic.id) serviceElapsed=\(Self.elapsedMilliseconds(since: startedAt))ms publishAndPreload=\(Self.elapsedMilliseconds(since: publishStartedAt))ms replies=\(loadedDetail.replies.count)")
            #endif
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
            #if DEBUG
            logViewModelTiming("load-failed topic=\(topic.id) elapsed=\(Self.elapsedMilliseconds(since: startedAt))ms error=\(error.localizedDescription)")
            #endif
        }
    }

    func updateFromLoadedHTML(_ html: String, sourceURL: URL) async {
        guard !html.isEmpty else {
            return
        }

        let startedAt = Date()
        let loadedDetail = await service.topicDetail(
            for: topic,
            html: html,
            sourceURL: sourceURL
        )
        detail = loadedDetail
        state = .loaded
        preloadImages(in: loadedDetail)
        #if DEBUG
        logViewModelTiming("web-html-published topic=\(topic.id) elapsed=\(Self.elapsedMilliseconds(since: startedAt))ms replies=\(loadedDetail.replies.count)")
        #endif
    }

    private func preloadImages(in detail: TopicDetail) {
        let startedAt = Date()
        let htmlFragments = [detail.contentHTML]
            + detail.supplements.map(\.contentHTML)
            + detail.replies.map(\.contentHTML)
        let urls = htmlFragments
            .flatMap(\.htmlImageURLs)

        guard !urls.isEmpty else {
            #if DEBUG
            logViewModelTiming("preload-images none elapsed=\(Self.elapsedMilliseconds(since: startedAt))ms")
            #endif
            return
        }

        let uniqueURLs = Array(Set(urls))
        RemoteImageCache.shared.preload(uniqueURLs)
        #if DEBUG
        logViewModelTiming("preload-images count=\(uniqueURLs.count) elapsed=\(Self.elapsedMilliseconds(since: startedAt))ms")
        #endif
    }

    #if DEBUG
    private func logViewModelTiming(_ message: String) {
        print("[V2EXPerf][TopicDetailViewModel] \(message)")
    }

    private static func elapsedMilliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
    #endif
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
