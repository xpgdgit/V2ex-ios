import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    var onHTMLLoaded: ((String, URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onHTMLLoaded: onHTMLLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = TopicWebViewCache.shared.webView(for: url)
        if webView.superview != nil {
            webView.removeFromSuperview()
        }
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.navigationDelegate = context.coordinator
        context.coordinator.onHTMLLoaded = onHTMLLoaded

        if context.coordinator.loadedURL == url || webView.url == url {
            context.coordinator.loadedURL = url
            return
        }

        context.coordinator.loadedURL = url
        context.coordinator.load(url: url, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var onHTMLLoaded: ((String, URL) -> Void)?
        private var loadTask: Task<Void, Never>?

        init(onHTMLLoaded: ((String, URL) -> Void)?) {
            self.onHTMLLoaded = onHTMLLoaded
        }

        deinit {
            loadTask?.cancel()
        }

        func load(url: URL, in webView: WKWebView) {
            loadTask?.cancel()
            loadTask = Task { [weak webView] in
                let cachedHTML: String? = await CacheStore.shared.value(for: topicHTMLCacheKey(for: url))

                await MainActor.run {
                    guard let webView else { return }
                    if let cachedHTML {
                        webView.loadHTMLString(cachedHTML, baseURL: url)
                    } else {
                        let request = URLRequest(
                            url: url,
                            cachePolicy: .returnCacheDataElseLoad,
                            timeoutInterval: 30
                        )
                        webView.load(request)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = loadedURL ?? webView.url else {
                return
            }

            webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { result, _ in
                guard let html = result as? String, !html.isEmpty else {
                    return
                }

                Task {
                    await CacheStore.shared.set(html, for: topicHTMLCacheKey(for: url))
                }
                self.onHTMLLoaded?(html, url)
            }
        }
    }
}

private func topicHTMLCacheKey(for url: URL) -> String {
    "topic-html-v1-\(url.absoluteString)"
}

private final class TopicWebViewCache {
    static let shared = TopicWebViewCache()

    private let limit = 8
    private var webViews: [URL: WKWebView] = [:]
    private var accessOrder: [URL] = []
    private var cacheClearObserver: NSObjectProtocol?

    private init() {
        cacheClearObserver = NotificationCenter.default.addObserver(
            forName: .v2exCacheDidClear,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clear()
        }
    }

    deinit {
        if let cacheClearObserver {
            NotificationCenter.default.removeObserver(cacheClearObserver)
        }
    }

    func webView(for url: URL) -> WKWebView {
        if let webView = webViews[url] {
            markAccessed(url)
            return webView
        }

        let webView = WKWebView()
        webViews[url] = webView
        markAccessed(url)
        pruneIfNeeded()
        return webView
    }

    private func clear() {
        webViews.values.forEach { webView in
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.removeFromSuperview()
        }
        webViews.removeAll()
        accessOrder.removeAll()

        WKWebsiteDataStore.default().removeData(
            ofTypes: [
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache
            ],
            modifiedSince: .distantPast
        ) {}
    }

    private func markAccessed(_ url: URL) {
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
    }

    private func pruneIfNeeded() {
        while accessOrder.count > limit, let url = accessOrder.first {
            accessOrder.removeFirst()
            webViews.removeValue(forKey: url)
        }
    }
}
