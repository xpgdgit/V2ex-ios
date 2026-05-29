import SwiftUI
import WebKit

struct TopicDetailView: View {
    let topic: Topic
    private let service: V2EXService
    @StateObject private var viewModel: TopicDetailViewModel
    @State private var isShowingWebView = false
    @State private var contentRefreshID = UUID()
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openURL) private var openURL

    init(topic: Topic, service: V2EXService) {
        self.topic = topic
        self.service = service
        _viewModel = StateObject(wrappedValue: TopicDetailViewModel(topic: topic, service: service))
    }

    var body: some View {
        ZStack {
            if isWebLayerVisible {
                webContent
            }

            if isContentLayerVisible {
                detailContent
            }
        }
        .navigationTitle("主题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if settings.enableWebTopicView {
                    Button {
                        isShowingWebView.toggle()
                    } label: {
                        Text("网页")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isShowingWebView ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isShowingWebView ? Color(.label) : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isShowingWebView ? "关闭网页视图" : "打开网页视图")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openURL(topic.webURL)
                } label: {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("在浏览器打开")
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var isWebLayerVisible: Bool {
        settings.enableWebTopicView && isShowingWebView
    }

    private var isContentLayerVisible: Bool {
        !isWebLayerVisible
    }

    @ViewBuilder
    private var detailContent: some View {
        if let detail = viewModel.detail {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    topicCard(detail: detail)

                    Text("回复 \(detail.replies.count)")
                        .font(.headline)
                        .padding(.top, 8)

                    if !detail.replies.isEmpty {
                        ReplyListCard(
                            replies: detail.replies,
                            isOriginalPoster: isOriginalPoster
                        )
                    }
                }
                .padding()
            }
            .id(contentRefreshID)
            .refreshable {
                await viewModel.load(refresh: true)
                contentRefreshID = UUID()
            }
        } else if case .failed(let message) = viewModel.state {
            VStack(spacing: 8) {
                Text("内容暂不可用")
                    .font(.subheadline.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("重试解析") {
                    Task {
                        await viewModel.load(refresh: true)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()
        } else {
            ProgressView("正在加载")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }

    private var webContent: some View {
        ZStack(alignment: .bottom) {
            WebView(url: topic.webURL) { html, sourceURL in
                Task {
                    await viewModel.updateFromLoadedHTML(html, sourceURL: sourceURL)
                }
            }
                .ignoresSafeArea(edges: .bottom)

            if viewModel.state == .loading && viewModel.detail == nil {
                ProgressView("正在加载")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
            }
        }
    }

    private func topicCard(detail: TopicDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(detail: detail)

            if !detail.contentHTML.isEmpty {
                HTMLText(html: detail.contentHTML)
            }

            if !detail.supplements.isEmpty {
                Divider()
                    .padding(.top, 2)

                SupplementList(supplements: detail.supplements)
            }
        }
        .cardStyle()
    }

    private func header(detail: TopicDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(topic.title.withCharacterBreakOpportunities)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                NavigationLink {
                    UserView(username: topic.member.username, service: service)
                } label: {
                    HStack(spacing: 6) {
                        AvatarView(url: topic.member.avatarURL, size: 28)
                        Text(topic.member.username)
                            .font(.subheadline.weight(.medium))
                        if let metadata = topicMetadataText(for: detail) {
                            Text(metadata)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }

    private func topicMetadataText(for detail: TopicDetail) -> String? {
        let createdText = detail.createdText ?? topic.createdAt?.relativeText
        let parts = [createdText, detail.viewsText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func isOriginalPoster(_ reply: Reply) -> Bool {
        reply.member.username.caseInsensitiveCompare(topic.member.username) == .orderedSame
    }
}

private struct SupplementList: View {
    let supplements: [TopicSupplement]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(supplements.enumerated()), id: \.element.id) { index, supplement in
                SupplementRow(supplement: supplement)
                    .padding(.vertical, 14)

                if index < supplements.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.yellow.opacity(0.55))
                .frame(width: 3)
        }
    }
}

private struct SupplementRow: View {
    let supplement: TopicSupplement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(supplement.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HTMLText(html: supplement.contentHTML)
        }
    }
}

private struct ReplyListCard: View {
    let replies: [Reply]
    let isOriginalPoster: (Reply) -> Bool

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                ReplyRow(reply: reply, isOriginalPoster: isOriginalPoster(reply))
                    .padding(.vertical, 14)

                if index < replies.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct ReplyRow: View {
    let reply: Reply
    let isOriginalPoster: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AvatarView(url: reply.member.avatarURL, size: 28)
                Text(reply.member.username)
                    .font(.subheadline.weight(.medium))
                if isOriginalPoster {
                    Text("OP")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay {
                            Capsule()
                                .stroke(.blue, lineWidth: 1)
                        }
                }
                if let createdText = reply.createdText ?? reply.createdAt?.relativeText {
                    Text(createdText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("#\(reply.floor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HTMLText(html: reply.contentHTML)
        }
    }
}

private struct HTMLText: View {
    let html: String

    var body: some View {
        let blocks = HTMLRenderCache.blocks(for: html)

        VStack(alignment: .leading, spacing: 12) {
            if blocks.isEmpty {
                Text(" ")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let html, let style):
                        HTMLStyledText(html: html, style: style)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let url, let style):
                        HTMLImageView(url: url, style: style)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HTMLStyledText: View {
    let html: String
    let style: HTMLTextStyle

    var body: some View {
        Group {
            if html.contains("<img") {
                InlineHTMLSnippetView(html: html, style: style)
            } else if style == .code {
                Text(HTMLRenderCache.readableText(for: html))
                    .font(baseFont)
                    .lineSpacing(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(backgroundStyle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(HTMLRenderCache.attributedText(for: html))
                    .font(baseFont)
                    .lineSpacing(style == .code ? 2 : 4)
                    .padding(style == .code ? 10 : 0)
                    .padding(.leading, style == .quote ? 12 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(backgroundStyle)
                    .overlay(alignment: .leading) {
                        if style == .quote {
                            Rectangle()
                                .fill(.quaternary)
                                .frame(width: 3)
                                .clipShape(Capsule())
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: style == .code ? 8 : 0))
            }
        }
    }

    private var baseFont: Font {
        switch style {
        case .body, .listItem, .quote:
            return .body
        case .code:
            return .system(.body, design: .monospaced)
        case .heading(let level):
            switch level {
            case 1: return .title2.weight(.bold)
            case 2: return .title3.weight(.semibold)
            case 3: return .headline
            default: return .subheadline.weight(.semibold)
            }
        }
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        switch style {
        case .code:
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.08))
        default:
            Color.clear
        }
    }
}

private final class HTMLCacheValue<Value>: NSObject {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private enum HTMLRenderCache {
    private static let blockCache = {
        let cache = NSCache<NSString, HTMLCacheValue<[HTMLRenderableBlock]>>()
        cache.countLimit = 300
        return cache
    }()

    private static let attributedCache = {
        let cache = NSCache<NSString, HTMLCacheValue<AttributedString>>()
        cache.countLimit = 300
        return cache
    }()

    private static let readableCache = {
        let cache = NSCache<NSString, HTMLCacheValue<String>>()
        cache.countLimit = 300
        return cache
    }()

    static func blocks(for html: String) -> [HTMLRenderableBlock] {
        let key = html as NSString
        if let cached = blockCache.object(forKey: key) {
            return cached.value
        }

        let blocks = html.renderableHTMLBlocks
        blockCache.setObject(HTMLCacheValue(blocks), forKey: key)
        return blocks
    }

    static func attributedText(for html: String) -> AttributedString {
        let key = html as NSString
        if let cached = attributedCache.object(forKey: key) {
            return cached.value
        }

        let attributed = html.attributedHTML
        attributedCache.setObject(HTMLCacheValue(attributed), forKey: key)
        return attributed
    }

    static func readableText(for html: String) -> String {
        let key = html as NSString
        if let cached = readableCache.object(forKey: key) {
            return cached.value
        }

        let text = html.readableHTMLText
        readableCache.setObject(HTMLCacheValue(text), forKey: key)
        return text
    }
}

private struct InlineHTMLSnippetView: View {
    let html: String
    let style: HTMLTextStyle
    @State private var measuredHeight: CGFloat = 24

    var body: some View {
        AutoSizingHTMLWebView(
            html: wrappedHTML,
            measuredHeight: $measuredHeight
        )
        .frame(height: measuredHeight)
        .padding(style == .code ? 10 : 0)
        .padding(.leading, style == .quote ? 12 : 0)
        .background(backgroundStyle)
        .overlay(alignment: .leading) {
            if style == .quote {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 3)
                    .clipShape(Capsule())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: style == .code ? 8 : 0))
    }

    private var wrappedHTML: String {
        """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <style>
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: \(fontSize)px;
            font-weight: \(fontWeight);
            line-height: \(lineHeight);
            color: \(textColorHex);
            word-break: break-word;
            overflow-wrap: anywhere;
        }
        p, div, ul, ol, li, blockquote, pre, h1, h2, h3, h4, h5, h6 {
            margin: 0;
            padding: 0;
        }
        blockquote {
            color: #6b7280;
        }
        pre {
            white-space: pre-wrap;
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        }
        ul, ol {
            padding-left: 1.2em;
        }
        img {
            max-width: 100%;
            height: auto;
            vertical-align: middle;
        }
        img.v2ex-inline-emoji {
            width: 1.2em;
            height: 1.2em;
            max-width: 1.2em;
            max-height: 1.2em;
            object-fit: contain;
            vertical-align: -0.18em;
        }
        img.embedded_image {
            display: inline-block;
            width: auto;
            max-width: 100%;
            height: auto;
            object-fit: contain;
            vertical-align: middle;
            border-radius: 8px;
        }
        a {
            color: #0a84ff;
            text-decoration: none;
        }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    private var fontSize: Int {
        switch style {
        case .body, .listItem, .quote:
            return 17
        case .code:
            return 15
        case .heading(let level):
            switch level {
            case 1: return 28
            case 2: return 22
            case 3: return 19
            default: return 17
            }
        }
    }

    private var fontWeight: Int {
        switch style {
        case .heading:
            return 600
        default:
            return 400
        }
    }

    private var lineHeight: Double {
        style == .code ? 1.4 : 1.55
    }

    private var textColorHex: String {
        "#111111"
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        switch style {
        case .code:
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.08))
        default:
            Color.clear
        }
    }
}

private struct AutoSizingHTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(measuredHeight: $measuredHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.v2ex.com"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var measuredHeight: CGFloat
        var lastHTML: String = ""

        init(measuredHeight: Binding<CGFloat>) {
            _measuredHeight = measuredHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(in: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak webView] in
                guard let webView else { return }
                self.measureHeight(in: webView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak webView] in
                guard let webView else { return }
                self.measureHeight(in: webView)
            }
        }

        private func measureHeight(in webView: WKWebView) {
            let script = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);"
            webView.evaluateJavaScript(script) { result, _ in
                guard let height = result as? CGFloat else { return }
                DispatchQueue.main.async {
                    self.measuredHeight = max(height, 24)
                }
            }
        }
    }
}

private struct HTMLImageView: View {
    let url: URL
    let style: HTMLImageStyle

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                switch style {
                case .content:
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .embedded:
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 320, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .emoji(let size):
                    image
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: size, height: size)
                }
            case .failure:
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.title2)
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: style == .content ? .infinity : 220, minHeight: style == .content ? 120 : 56)
                .background {
                    if style == .content {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.secondary.opacity(0.08))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            default:
                Group {
                    if case .content = style {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .background(.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        ProgressView()
                            .frame(width: style == .embedded ? 160 : 56, height: style == .embedded ? 180 : 56)
                    }
                }
            }
        }
        .frame(maxWidth: style == .content ? .infinity : 220, alignment: .leading)
    }
}

private extension String {
    var withCharacterBreakOpportunities: String {
        map(String.init).joined(separator: "\u{200B}")
    }
}
