import SwiftUI
import UIKit
import WebKit

struct TopicDetailView: View {
    let topic: Topic
    private let service: V2EXService
    @StateObject private var viewModel: TopicDetailViewModel
    @State private var isShowingWebView = false
    @State private var contentRefreshID = UUID()
    @State private var selectedImage: SelectedTopicImage?
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
        .fullScreenCover(item: $selectedImage) { image in
            ImageViewer(imageURL: image.url)
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
                        .font(settings.contentFont(size: 17, weight: .semibold))
                        .padding(.top, 8)

                    if !detail.replies.isEmpty {
                        ReplyListCard(
                            replies: detail.replies,
                            isOriginalPoster: isOriginalPoster,
                            onImageTap: openImageViewer
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
                    .font(settings.contentFont(size: 15, weight: .medium))
                Text(message)
                    .font(settings.contentFont(size: 12))
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
                HTMLText(html: detail.contentHTML, onImageTap: openImageViewer)
            }

            if !detail.supplements.isEmpty {
                Divider()
                    .padding(.top, 2)

                SupplementList(supplements: detail.supplements, onImageTap: openImageViewer)
            }
        }
        .cardStyle()
    }

    private func header(detail: TopicDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(topic.title.withCharacterBreakOpportunities)
                .font(settings.contentFont(size: 22, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                NavigationLink {
                    UserView(username: topic.member.username, service: service)
                } label: {
                    HStack(spacing: 6) {
                        AvatarView(url: topic.member.avatarURL, size: 28)
                        Text(topic.member.username)
                            .font(settings.contentFont(size: 15, weight: .medium))
                        if let metadata = topicMetadataText(for: detail) {
                            Text(metadata)
                                .font(settings.contentFont(size: 15))
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

    private func openImageViewer(_ url: URL) {
        selectedImage = SelectedTopicImage(url: url)
    }
}

private struct SupplementList: View {
    let supplements: [TopicSupplement]
    let onImageTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(supplements.enumerated()), id: \.element.id) { index, supplement in
                SupplementRow(supplement: supplement, onImageTap: onImageTap)
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
    @EnvironmentObject private var settings: SettingsStore

    let supplement: TopicSupplement
    let onImageTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(supplement.title)
                .font(settings.contentFont(size: 12))
                .foregroundStyle(.secondary)

            HTMLText(html: supplement.contentHTML, onImageTap: onImageTap)
        }
    }
}

private struct ReplyListCard: View {
    let replies: [Reply]
    let isOriginalPoster: (Reply) -> Bool
    let onImageTap: (URL) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                ReplyRow(reply: reply, isOriginalPoster: isOriginalPoster(reply), onImageTap: onImageTap)
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
    @EnvironmentObject private var settings: SettingsStore

    let reply: Reply
    let isOriginalPoster: Bool
    let onImageTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AvatarView(url: reply.member.avatarURL, size: 28)
                Text(reply.member.username)
                    .font(settings.contentFont(size: 15, weight: .medium))
                if isOriginalPoster {
                    Text("OP")
                        .font(settings.contentFont(size: 11, weight: .semibold))
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
                        .font(settings.contentFont(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("#\(reply.floor)")
                    .font(settings.contentFont(size: 12))
                    .foregroundStyle(.secondary)
            }

            HTMLText(html: reply.contentHTML, onImageTap: onImageTap)
        }
    }
}

private struct HTMLText: View {
    let html: String
    let onImageTap: (URL) -> Void

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
                        HTMLStyledText(html: html, style: style, onImageTap: onImageTap)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let url, let style):
                        HTMLImageView(url: url, style: style, onTap: onImageTap)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HTMLStyledText: View {
    @EnvironmentObject private var settings: SettingsStore

    let html: String
    let style: HTMLTextStyle
    let onImageTap: (URL) -> Void

    var body: some View {
        Group {
            if html.contains("<img") {
                InlineHTMLTextView(html: html, style: style, onImageTap: onImageTap)
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
            return settings.contentFont(size: 17)
        case .code:
            return settings.contentFont(size: 15, design: .monospaced)
        case .heading(let level):
            switch level {
            case 1: return settings.contentFont(size: 28, weight: .bold)
            case 2: return settings.contentFont(size: 22, weight: .semibold)
            case 3: return settings.contentFont(size: 19, weight: .semibold)
            default: return settings.contentFont(size: 17, weight: .semibold)
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

    private static let inlineRunCache = {
        let cache = NSCache<NSString, HTMLCacheValue<[HTMLInlineRun]>>()
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

    static func inlineRuns(for html: String) -> [HTMLInlineRun] {
        let key = html as NSString
        if let cached = inlineRunCache.object(forKey: key) {
            return cached.value
        }

        let runs = html.inlineHTMLRuns
        inlineRunCache.setObject(HTMLCacheValue(runs), forKey: key)
        return runs
    }
}

private struct InlineHTMLTextView: View {
    @EnvironmentObject private var settings: SettingsStore

    let html: String
    let style: HTMLTextStyle
    let onImageTap: (URL) -> Void

    var body: some View {
        InlineFlowLayout(horizontalSpacing: 0, verticalSpacing: lineSpacing) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                switch run {
                case .text(let text):
                    Text(text)
                        .font(baseFont)
                        .foregroundStyle(textStyle)
                        .lineLimit(1)
                        .fixedSize()
                case .image(let url, let size):
                    InlineCachedImage(url: url, preferredSize: size, onTap: onImageTap)
                case .lineBreak:
                    Color.clear
                        .frame(width: 0, height: lineHeight)
                        .layoutValue(key: InlineLineBreakKey.self, value: true)
                }
            }
        }
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

    private var runs: [HTMLInlineRun] {
        HTMLRenderCache.inlineRuns(for: html)
    }

    private var baseFont: Font {
        switch style {
        case .body, .listItem, .quote:
            return settings.contentFont(size: 17)
        case .code:
            return settings.contentFont(size: 15, design: .monospaced)
        case .heading(let level):
            switch level {
            case 1: return settings.contentFont(size: 28, weight: .bold)
            case 2: return settings.contentFont(size: 22, weight: .semibold)
            case 3: return settings.contentFont(size: 19, weight: .semibold)
            default: return settings.contentFont(size: 17, weight: .semibold)
            }
        }
    }

    private var lineHeight: CGFloat {
        switch style {
        case .code:
            return settings.scaledContentSize(21)
        case .heading(let level):
            switch level {
            case 1: return settings.scaledContentSize(36)
            case 2: return settings.scaledContentSize(30)
            case 3: return settings.scaledContentSize(26)
            default: return settings.scaledContentSize(24)
            }
        default:
            return settings.scaledContentSize(24)
        }
    }

    private var lineSpacing: CGFloat {
        style == .code ? 3 : 5
    }

    private var textStyle: HierarchicalShapeStyle {
        style == .quote ? .secondary : .primary
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

private struct InlineCachedImage: View {
    let url: URL
    let preferredSize: CGFloat?
    let onTap: (URL) -> Void

    var body: some View {
        CachedRemoteImage(url: url) { image in
            Button {
                onTap(url)
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: renderedSize(for: image).width, height: renderedSize(for: image).height)
                    .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius(for: image)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看图片")
        } placeholder: {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 24, height: 24)
        }
    }

    private func renderedSize(for image: UIImage) -> CGSize {
        let naturalSize = image.size
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            return CGSize(width: 24, height: 24)
        }

        if let preferredSize {
            let scale = preferredSize / max(naturalSize.width, naturalSize.height)
            return CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        }

        if max(naturalSize.width, naturalSize.height) <= 128 {
            return naturalSize
        }

        let width = maxContentImageWidth
        let scale = width / naturalSize.width
        return CGSize(width: width, height: naturalSize.height * scale)
    }

    private var maxContentImageWidth: CGFloat {
        max(120, UIScreen.main.bounds.width - 60)
    }

    private func imageCornerRadius(for image: UIImage) -> CGFloat {
        let size = renderedSize(for: image)
        return min(size.width, size.height) > 64 ? 8 : 0
    }
}

private struct InlineLineBreakKey: LayoutValueKey {
    static let defaultValue = false
}

private struct InlineFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            if subview[InlineLineBreakKey.self] {
                y += max(lineHeight, subview.sizeThatFits(.unspecified).height) + verticalSpacing
                x = 0
                lineHeight = 0
                continue
            }

            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + verticalSpacing
                x = 0
                lineHeight = 0
            }

            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var lineItems: [(index: Int, x: CGFloat, size: CGSize)] = []

        func placeLine() {
            for item in lineItems {
                let subview = subviews[item.index]
                subview.place(
                    at: CGPoint(
                        x: bounds.minX + item.x,
                        y: bounds.minY + y + (lineHeight - item.size.height) / 2
                    ),
                    proposal: ProposedViewSize(item.size)
                )
            }
            y += lineHeight + verticalSpacing
            x = 0
            lineHeight = 0
            lineItems.removeAll(keepingCapacity: true)
        }

        for index in subviews.indices {
            let subview = subviews[index]
            if subview[InlineLineBreakKey.self] {
                if lineItems.isEmpty {
                    y += subview.sizeThatFits(.unspecified).height + verticalSpacing
                } else {
                    placeLine()
                }
                continue
            }

            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                placeLine()
            }

            lineItems.append((index, x, size))
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        if !lineItems.isEmpty {
            for item in lineItems {
                let subview = subviews[item.index]
                subview.place(
                    at: CGPoint(
                        x: bounds.minX + item.x,
                        y: bounds.minY + y + (lineHeight - item.size.height) / 2
                    ),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }
}

private struct InlineHTMLSnippetView: View {
    @EnvironmentObject private var settings: SettingsStore

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
        Int(settings.scaledContentSize(baseFontSize).rounded())
    }

    private var baseFontSize: CGFloat {
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
    let onTap: (URL) -> Void

    var body: some View {
        imageContent
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var imageContent: some View {
        if canOpenViewer {
            Button {
                onTap(url)
            } label: {
                renderedImage
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看图片")
        } else {
            renderedImage
        }
    }

    private var renderedImage: some View {
        CachedRemoteImage(url: url) { image in
            loadedImage(image)
        } placeholder: {
            loadingPlaceholder
        }
    }

    @ViewBuilder
    private func loadedImage(_ image: UIImage) -> some View {
        switch style {
        case .content, .embedded:
            NaturalSizeImage(image: image)
        case .emoji(let size), .inline(let size?):
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: size, height: size)
        case .inline(nil):
            NaturalSizeImage(image: image)
        }
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        if usesFullWidth {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ProgressView()
                .frame(width: 56, height: 56)
        }
    }

    private var usesFullWidth: Bool {
        switch style {
        case .content, .embedded:
            return true
        case .emoji, .inline:
            return false
        }
    }

    private var canOpenViewer: Bool {
        switch style {
        case .content, .embedded:
            return true
        case .emoji, .inline:
            return false
        }
    }
}

private struct NaturalSizeImage: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var aspectRatio: CGFloat {
        guard image.size.width > 0, image.size.height > 0 else {
            return 1
        }
        return image.size.width / image.size.height
    }
}

private struct SelectedTopicImage: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

private struct ImageViewer: View {
    let imageURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let image {
                ZoomableImageView(image: image)
                    .ignoresSafeArea()
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 36))
                    Text("图片暂不可用")
                        .font(.headline)
                }
                .foregroundStyle(.white.opacity(0.8))
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("关闭图片")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .task(id: imageURL) {
            isLoading = true
            image = await RemoteImageCache.shared.loadImage(for: imageURL)
            isLoading = false
        }
    }
}

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.bouncesZoom = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = recognizer.location(in: imageView)
                let targetZoom = min(scrollView.maximumZoomScale, 2.5)
                let width = scrollView.bounds.width / targetZoom
                let height = scrollView.bounds.height / targetZoom
                let rect = CGRect(
                    x: location.x - width / 2,
                    y: location.y - height / 2,
                    width: width,
                    height: height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

private extension String {
    var withCharacterBreakOpportunities: String {
        map(String.init).joined(separator: "\u{200B}")
    }
}
