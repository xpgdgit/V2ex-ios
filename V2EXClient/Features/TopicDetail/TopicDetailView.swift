import SwiftUI
import UIKit
import Photos

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
            ImageViewer(imageURLs: image.urls, initialIndex: image.index)
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
        let urls = topicImageURLs()
        guard !urls.isEmpty else {
            selectedImage = SelectedTopicImage(urls: [url], index: 0)
            return
        }

        let index = urls.firstIndex(of: url) ?? 0
        selectedImage = SelectedTopicImage(urls: urls, index: index)
    }

    private func topicImageURLs() -> [URL] {
        guard let detail = viewModel.detail else {
            return []
        }

        let htmlFragments = [detail.contentHTML]
            + detail.supplements.map(\.contentHTML)
            + detail.replies.map(\.contentHTML)
        return htmlFragments.flatMap(\.htmlImageURLs)
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
                        HTMLStyledText(html: html, style: style)
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
    @Environment(\.openURL) private var openURL

    let html: String
    let style: HTMLTextStyle

    var body: some View {
        SelectableHTMLTextView(
            attributedText: HTMLRenderCache.selectableAttributedText(
                for: html,
                style: style,
                settings: settings
            ),
            contentKey: HTMLRenderCache.selectableContentKey(
                for: html,
                style: style,
                settings: settings
            ),
            onOpenURL: { url in
                openURL(url)
            }
        )
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

private struct SelectableHTMLTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let contentKey: String
    let onOpenURL: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: onOpenURL)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.dataDetectorTypes = []
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        if context.coordinator.contentKey != contentKey {
            textView.attributedText = attributedText
            context.coordinator.contentKey = contentKey
            context.coordinator.resetInlineImageLoading()
        }
        context.coordinator.loadInlineImages(in: textView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context _: Context
    ) -> CGSize? {
        let width = max(1, proposal.width ?? UIScreen.main.bounds.width)
        let fittingSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let height = uiView.sizeThatFits(fittingSize).height
        return CGSize(width: width, height: ceil(height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: (URL) -> Void
        var contentKey: String?
        private var loadingAttachmentIDs = Set<String>()

        init(onOpenURL: @escaping (URL) -> Void) {
            self.onOpenURL = onOpenURL
        }

        func resetInlineImageLoading() {
            loadingAttachmentIDs.removeAll()
        }

        func loadInlineImages(in textView: UITextView) {
            let attachments = inlineImageAttachments(in: textView.attributedText)
            for attachment in attachments where attachment.image == nil {
                if let cachedImage = RemoteImageCache.shared.image(for: attachment.url) {
                    apply(cachedImage, to: attachment, in: textView)
                    continue
                }

                guard loadingAttachmentIDs.insert(attachment.identifier).inserted else {
                    continue
                }

                Task { @MainActor [weak self, weak textView, weak attachment] in
                    guard let self, let textView, let attachment else { return }
                    let image = await RemoteImageCache.shared.loadImage(for: attachment.url)
                    loadingAttachmentIDs.remove(attachment.identifier)
                    guard let image else { return }
                    apply(image, to: attachment, in: textView)
                }
            }
        }

        private func inlineImageAttachments(in attributedText: NSAttributedString) -> [InlineHTMLImageAttachment] {
            var attachments: [InlineHTMLImageAttachment] = []
            let range = NSRange(location: 0, length: attributedText.length)
            attributedText.enumerateAttribute(.attachment, in: range) { value, _, _ in
                guard let attachment = value as? InlineHTMLImageAttachment else {
                    return
                }
                attachments.append(attachment)
            }
            return attachments
        }

        private func apply(
            _ image: UIImage,
            to attachment: InlineHTMLImageAttachment,
            in textView: UITextView
        ) {
            attachment.image = image
            let selectedRange = textView.selectedRange
            textView.attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            if selectedRange.location + selectedRange.length <= textView.attributedText.length {
                textView.selectedRange = selectedRange
            }
            textView.invalidateIntrinsicContentSize()
            textView.setNeedsLayout()
        }

        func textView(
            _: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard let link = textItem.value(forKey: "link") as? URL else {
                return defaultAction
            }

            return UIAction { [weak self] _ in
                self?.onOpenURL(link)
            }
        }
    }
}

private final class InlineHTMLImageAttachment: NSTextAttachment {
    let identifier: String
    let url: URL

    init(identifier: String, url: URL, displaySize: CGFloat, image: UIImage?) {
        self.identifier = identifier
        self.url = url
        super.init(data: nil, ofType: nil)
        self.image = image
        bounds = CGRect(x: 0, y: -displaySize * 0.18, width: displaySize, height: displaySize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private enum SelectableHTMLAttributedStringBuilder {
    static func attributedText(
        for html: String,
        style: HTMLTextStyle,
        settings: SettingsStore
    ) -> NSAttributedString {
        let preparedHTML = preparedSelectableHTML(from: html.selectableHTMLFragment)
        let wrappedHTML = wrappedHTML(for: preparedHTML.html, style: style, settings: settings)
        guard let data = wrappedHTML.data(using: .utf8),
              let attributed = try? NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return fallbackText(for: preparedHTML, style: style, settings: settings)
        }

        if attributed.string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return NSAttributedString(string: " ")
        }

        applyAppStyle(to: attributed, style: style, settings: settings)
        replaceInlineImageMarkers(in: attributed, with: preparedHTML.inlineImages)
        return attributed
    }

    private static func fallbackText(
        for preparedHTML: PreparedSelectableHTML,
        style: HTMLTextStyle,
        settings: SettingsStore
    ) -> NSAttributedString {
        let text = preparedHTML.html.readableHTMLText.isEmpty ? " " : preparedHTML.html.readableHTMLText
        let attributed = NSMutableAttributedString(string: text)
        applyAppStyle(to: attributed, style: style, settings: settings)
        replaceInlineImageMarkers(in: attributed, with: preparedHTML.inlineImages)
        return attributed
    }

    private struct PreparedSelectableHTML {
        let html: String
        let inlineImages: [InlineHTMLImage]
    }

    private struct InlineHTMLImage {
        let marker: String
        let identifier: String
        let url: URL
        let displaySize: CGFloat
    }

    private static func preparedSelectableHTML(from html: String) -> PreparedSelectableHTML {
        guard let regex = try? NSRegularExpression(
            pattern: #"<img\b[^>]*\bsrc\s*=\s*(?:(['"])(.*?)\1|([^'">\s]+))[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return PreparedSelectableHTML(html: html, inlineImages: [])
        }

        var result = ""
        var inlineImages: [InlineHTMLImage] = []
        var cursor = html.startIndex
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        for match in regex.matches(in: html, range: nsRange) {
            guard let range = Range(match.range, in: html) else { continue }
            result += String(html[cursor..<range.lowerBound])

            let tagHTML = String(html[range])
            if isInlineImageTag(tagHTML),
               let rawSource = imageSource(from: match, in: html),
               let url = normalizedImageURL(from: rawSource) {
                result = result.removingTrailingBreakBeforeInlineImage
                let marker = "V2EX_INLINE_IMAGE_MARKER_\(inlineImages.count)_\(UUID().uuidString)"
                let identifier = "\(url.absoluteString)-\(inlineImages.count)-\(UUID().uuidString)"
                inlineImages.append(
                    InlineHTMLImage(
                        marker: marker,
                        identifier: identifier,
                        url: url,
                        displaySize: inlineImageDisplaySize(from: tagHTML)
                    )
                )
                result += marker
            } else {
                result += " "
            }

            cursor = range.upperBound
        }

        result += String(html[cursor...])
        return PreparedSelectableHTML(html: result, inlineImages: inlineImages)
    }

    private static func replaceInlineImageMarkers(
        in attributed: NSMutableAttributedString,
        with inlineImages: [InlineHTMLImage]
    ) {
        guard attributed.length > 0 else { return }

        for inlineImage in inlineImages {
            let markerRange = (attributed.string as NSString).range(of: inlineImage.marker)
            guard markerRange.location != NSNotFound else { continue }

            var attributes: [NSAttributedString.Key: Any] = [:]
            if markerRange.location < attributed.length {
                attributes = attributed.attributes(at: markerRange.location, effectiveRange: nil)
            }
            let attachment = InlineHTMLImageAttachment(
                identifier: inlineImage.identifier,
                url: inlineImage.url,
                displaySize: inlineImage.displaySize,
                image: RemoteImageCache.shared.image(for: inlineImage.url)
            )
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            for (key, value) in attributes where key != .attachment {
                attachmentString.addAttribute(
                    key,
                    value: value,
                    range: NSRange(location: 0, length: attachmentString.length)
                )
            }
            attributed.replaceCharacters(in: markerRange, with: attachmentString)
        }
    }

    private static func isInlineImageTag(_ tagHTML: String) -> Bool {
        let loweredTag = tagHTML.lowercased()
        return loweredTag.contains("v2ex-inline-emoji")
            || loweredTag.contains("v2ex-inline-image")
            || loweredTag.contains("data-v2ex-inline-size")
    }

    private static func imageSource(from match: NSTextCheckingResult, in html: String) -> String? {
        for index in [2, 3] where match.range(at: index).location != NSNotFound {
            if let range = Range(match.range(at: index), in: html) {
                return String(html[range])
            }
        }
        return nil
    }

    private static func normalizedImageURL(from rawValue: String) -> URL? {
        if rawValue.hasPrefix("//") {
            return URL(string: "https:\(rawValue)")
        }
        if rawValue.hasPrefix("/") {
            return URL(string: "https://www.v2ex.com\(rawValue)")
        }
        return URL(string: rawValue)
    }

    private static func inlineImageDisplaySize(from tagHTML: String) -> CGFloat {
        let size = numericHTMLAttribute("data-v2ex-inline-size", in: tagHTML)
            ?? numericHTMLAttribute("width", in: tagHTML)
            ?? numericHTMLAttribute("height", in: tagHTML)
            ?? 24
        return min(max(CGFloat(size), 1), 28)
    }

    private static func numericHTMLAttribute(_ name: String, in tagHTML: String) -> Double? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?i)\b"# + escapedName + #"\s*=\s*(?:(['"])(\d+(?:\.\d+)?)\1|(\d+(?:\.\d+)?))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsRange = NSRange(tagHTML.startIndex..<tagHTML.endIndex, in: tagHTML)
        guard let match = regex.firstMatch(in: tagHTML, range: nsRange) else {
            return nil
        }

        for index in [2, 3] where match.range(at: index).location != NSNotFound {
            if let range = Range(match.range(at: index), in: tagHTML) {
                return Double(tagHTML[range])
            }
        }

        return nil
    }

    private static func wrappedHTML(
        for body: String,
        style: HTMLTextStyle,
        settings: SettingsStore
    ) -> String {
        """
        <html>
        <head>
        <meta name="viewport" content="initial-scale=1.0" />
        <base href="https://www.v2ex.com" />
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: \(baseFontSize(for: style, settings: settings))px;
            line-height: \(style == .code ? "1.4" : "1.55");
            margin: 0;
            padding: 0;
        }
        p, div, ul, ol, li, blockquote, pre, h1, h2, h3, h4, h5, h6 {
            margin: 0;
            padding: 0;
        }
        ul, ol {
            padding-left: 1.2em;
        }
        pre {
            white-space: pre-wrap;
        }
        a {
            color: #0a84ff;
            text-decoration: none;
        }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private static func applyAppStyle(
        to attributed: NSMutableAttributedString,
        style: HTMLTextStyle,
        settings: SettingsStore
    ) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return }

        attributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let existingFont = value as? UIFont
            attributed.addAttribute(
                .font,
                value: font(for: style, settings: settings, existingFont: existingFont),
                range: range
            )
        }

        attributed.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let paragraphStyle = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = style == .code ? 2 : 4
            paragraphStyle.lineBreakMode = .byWordWrapping
            attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
        attributed.addAttribute(.foregroundColor, value: textColor(for: style), range: fullRange)

        attributed.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            attributed.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
        }
    }

    private static func font(
        for style: HTMLTextStyle,
        settings: SettingsStore,
        existingFont: UIFont?
    ) -> UIFont {
        let traits = existingFont?.fontDescriptor.symbolicTraits ?? []
        let weight: UIFont.Weight
        if case .heading = style {
            weight = .semibold
        } else if traits.contains(.traitBold) {
            weight = .semibold
        } else {
            weight = .regular
        }

        let size = baseFontSize(for: style, settings: settings)
        let font: UIFont
        if style == .code {
            font = .monospacedSystemFont(ofSize: size, weight: weight)
        } else {
            font = .systemFont(ofSize: size, weight: weight)
        }

        guard traits.contains(.traitItalic),
              let descriptor = font.fontDescriptor.withSymbolicTraits(
                font.fontDescriptor.symbolicTraits.union(.traitItalic)
              ) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func baseFontSize(for style: HTMLTextStyle, settings: SettingsStore) -> CGFloat {
        switch style {
        case .body, .listItem, .quote:
            return settings.scaledContentSize(17)
        case .code:
            return settings.scaledContentSize(15)
        case .heading(let level):
            switch level {
            case 1: return settings.scaledContentSize(28)
            case 2: return settings.scaledContentSize(22)
            case 3: return settings.scaledContentSize(19)
            default: return settings.scaledContentSize(17)
            }
        }
    }

    private static func textColor(for style: HTMLTextStyle) -> UIColor {
        style == .quote ? .secondaryLabel : .label
    }
}

private extension String {
    var removingTrailingBreakBeforeInlineImage: String {
        var result = replacingOccurrences(
            of: #"(?is)(?:\s*<br\s*/?>\s*)+((?:<a\b[^>]*>\s*)*)$"#,
            with: " $1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?is)</p\s*>\s*<p[^>]*>\s*((?:<a\b[^>]*>\s*)*)$"#,
            with: " $1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?is)</div\s*>\s*<div[^>]*>\s*((?:<a\b[^>]*>\s*)*)$"#,
            with: " $1",
            options: .regularExpression
        )
        return result
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

    static func blocks(for html: String) -> [HTMLRenderableBlock] {
        let key = html as NSString
        if let cached = blockCache.object(forKey: key) {
            return cached.value
        }

        let blocks = html.renderableHTMLBlocks
        blockCache.setObject(HTMLCacheValue(blocks), forKey: key)
        return blocks
    }

    @MainActor
    static func selectableAttributedText(
        for html: String,
        style: HTMLTextStyle,
        settings: SettingsStore
    ) -> NSAttributedString {
        SelectableHTMLAttributedStringBuilder.attributedText(
            for: html,
            style: style,
            settings: settings
        )
    }

    @MainActor
    static func selectableContentKey(
        for html: String,
        style: HTMLTextStyle,
        settings: SettingsStore
    ) -> String {
        "\(settings.contentFontScale)-\(style.cacheKey)-\(html)"
    }
}

private struct HTMLImageView: View {
    let url: URL
    let style: HTMLImageStyle
    let onTap: (URL) -> Void

    @State private var imageActionMessage: ImageActionMessage?

    var body: some View {
        imageContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .alert(item: $imageActionMessage) { message in
                Alert(
                    title: Text(message.title),
                    message: Text(message.message),
                    dismissButton: .default(Text("好"))
                )
            }
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
                .contextMenu {
                    imageActionMenu(for: image)
                }
        } placeholder: {
            loadingPlaceholder
        }
    }

    @ViewBuilder
    private func imageActionMenu(for image: UIImage) -> some View {
        Button {
            Task {
                await save(image)
            }
        } label: {
            Label("保存图片", systemImage: "square.and.arrow.down")
        }

        Button {
            UIPasteboard.general.string = url.absoluteString
            imageActionMessage = ImageActionMessage(title: "已复制", message: "图片链接已复制。")
        } label: {
            Label("复制图片链接", systemImage: "link")
        }

        ShareLink(item: url) {
            Label("分享图片", systemImage: "square.and.arrow.up")
        }
    }

    private func save(_ image: UIImage) async {
        do {
            try await PhotoLibraryImageSaver.save(image)
            imageActionMessage = ImageActionMessage(title: "已保存", message: "图片已保存到相册。")
        } catch {
            imageActionMessage = ImageActionMessage(title: "保存失败", message: error.localizedDescription)
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
    @State private var containerWidth = max(120, UIScreen.main.bounds.width - 60)

    var body: some View {
        let renderedSize = ImageDisplaySize.size(for: image.size, maxWidth: containerWidth)

        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: renderedSize.width, height: renderedSize.height, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ImageContainerWidthPreferenceKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(ImageContainerWidthPreferenceKey.self) { width in
                guard width > 0, width != containerWidth else { return }
                containerWidth = width
            }
    }
}

private struct ImageContainerWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let nextValue = nextValue()
        if nextValue > 0 {
            value = nextValue
        }
    }
}

private struct ImageActionMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum PhotoLibraryImageSaver {
    static func save(_ image: UIImage) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let authorizedStatus: PHAuthorizationStatus
        if status == .notDetermined {
            authorizedStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            authorizedStatus = status
        }

        guard authorizedStatus == .authorized || authorizedStatus == .limited else {
            throw PhotoLibraryImageSaveError.notAuthorized
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibraryImageSaveError.saveFailed)
                }
            }
        }
    }
}

private enum PhotoLibraryImageSaveError: LocalizedError {
    case notAuthorized
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "没有相册写入权限。请在系统设置中允许添加照片。"
        case .saveFailed:
            return "系统未能完成保存，请稍后再试。"
        }
    }
}

private struct SelectedTopicImage: Identifiable {
    let urls: [URL]
    let index: Int

    var id: String {
        let selectedURL = urls.indices.contains(index) ? urls[index].absoluteString : ""
        return "\(index)-\(selectedURL)"
    }
}

private struct ImageViewer: View {
    let imageURLs: [URL]

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var imageActionMessage: ImageActionMessage?

    init(imageURLs: [URL], initialIndex: Int) {
        let safeURLs = imageURLs.isEmpty ? [] : imageURLs
        self.imageURLs = safeURLs
        _currentIndex = State(initialValue: min(max(initialIndex, 0), max(safeURLs.count - 1, 0)))
    }

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
                    if imageURLs.count > 1 {
                        Text("\(currentIndex + 1) / \(imageURLs.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.45))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if let currentURL {
                        Button {
                            Task {
                                await saveCurrentImage()
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.45))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("保存图片")

                        ShareLink(item: currentURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.45))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("分享图片")
                    }

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

            if canMoveBackward {
                HStack {
                    navigationButton(systemName: "chevron.left", action: moveBackward)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }

            if canMoveForward {
                HStack {
                    Spacer()
                    navigationButton(systemName: "chevron.right", action: moveForward)
                }
                .padding(.horizontal, 12)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard imageURLs.count > 1 else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical), abs(horizontal) > 80 else { return }
                    if horizontal < 0 {
                        moveForward()
                    } else {
                        moveBackward()
                    }
                }
        )
        .task(id: currentURL) {
            isLoading = true
            image = nil
            if let currentURL {
                image = await RemoteImageCache.shared.loadImage(for: currentURL)
            }
            isLoading = false
        }
        .alert(item: $imageActionMessage) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text("好"))
            )
        }
        .contextMenu {
            if let image {
                Button {
                    Task {
                        await save(image)
                    }
                } label: {
                    Label("保存图片", systemImage: "square.and.arrow.down")
                }
            }

            if let currentURL {
                Button {
                    UIPasteboard.general.string = currentURL.absoluteString
                    imageActionMessage = ImageActionMessage(title: "已复制", message: "图片链接已复制。")
                } label: {
                    Label("复制图片链接", systemImage: "link")
                }

                ShareLink(item: currentURL) {
                    Label("分享图片", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var currentURL: URL? {
        guard imageURLs.indices.contains(currentIndex) else {
            return nil
        }
        return imageURLs[currentIndex]
    }

    private var canMoveBackward: Bool {
        currentIndex > 0
    }

    private var canMoveForward: Bool {
        currentIndex < imageURLs.count - 1
    }

    private func moveBackward() {
        guard canMoveBackward else { return }
        currentIndex -= 1
    }

    private func moveForward() {
        guard canMoveForward else { return }
        currentIndex += 1
    }

    private func saveCurrentImage() async {
        guard let image else {
            imageActionMessage = ImageActionMessage(title: "图片仍在加载", message: "请稍后再试。")
            return
        }
        await save(image)
    }

    private func save(_ image: UIImage) async {
        do {
            try await PhotoLibraryImageSaver.save(image)
            imageActionMessage = ImageActionMessage(title: "已保存", message: "图片已保存到相册。")
        } catch {
            imageActionMessage = ImageActionMessage(title: "保存失败", message: error.localizedDescription)
        }
    }

    private func navigationButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName == "chevron.left" ? "上一张图片" : "下一张图片")
    }
}

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = CenteredImageScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.bouncesZoom = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        scrollView.centeredImageDelegate = context.coordinator

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
        context.coordinator.updateImageLayout(in: scrollView, animated: false)
    }

    private final class CenteredImageScrollView: UIScrollView {
        weak var centeredImageDelegate: Coordinator?

        override func layoutSubviews() {
            super.layoutSubviews()
            centeredImageDelegate?.updateImageLayout(in: self, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        private var lastBaseSize: CGSize = .zero
        private var lastImageSize: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            updateCentering(in: scrollView)
        }

        func updateImageLayout(in scrollView: UIScrollView, animated: Bool) {
            guard let imageView,
                  let image = imageView.image,
                  scrollView.bounds.width > 0,
                  scrollView.bounds.height > 0 else {
                return
            }

            let baseSize = ImageDisplaySize.size(
                for: image.size,
                maxSize: scrollView.bounds.size
            )
            guard baseSize != lastBaseSize || image.size != lastImageSize else {
                updateCentering(in: scrollView)
                return
            }

            lastBaseSize = baseSize
            lastImageSize = image.size
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
            imageView.frame = CGRect(origin: .zero, size: baseSize)
            scrollView.contentSize = baseSize
            updateCentering(in: scrollView)
        }

        private func updateCentering(in scrollView: UIScrollView) {
            let width = imageView?.bounds.width ?? 0
            let height = imageView?.bounds.height ?? 0
            let scaledWidth = width * scrollView.zoomScale
            let scaledHeight = height * scrollView.zoomScale
            let horizontalInset = max(0, (scrollView.bounds.width - scaledWidth) / 2)
            let verticalInset = max(0, (scrollView.bounds.height - scaledHeight) / 2)
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
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

private extension HTMLTextStyle {
    var cacheKey: String {
        switch self {
        case .body:
            return "body"
        case .quote:
            return "quote"
        case .code:
            return "code"
        case .heading(let level):
            return "heading-\(level)"
        case .listItem:
            return "list-item"
        }
    }
}
