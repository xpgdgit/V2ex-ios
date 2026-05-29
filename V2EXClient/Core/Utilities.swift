import CryptoKit
import Foundation
import SwiftUI

enum HTMLTextStyle: Equatable {
    case body
    case quote
    case code
    case heading(level: Int)
    case listItem
}

enum HTMLRenderableBlock: Equatable {
    case text(html: String, style: HTMLTextStyle)
    case image(URL, style: HTMLImageStyle)

    var plainText: String? {
        switch self {
        case .text(let html, _):
            return html.readableHTMLText
        case .image:
            return nil
        }
    }
}

enum HTMLImageStyle: Equatable {
    case content
    case embedded
    case emoji(size: CGFloat)
}

extension String {
    static func md5HexDigest(for value: String) -> String {
        let data = Data(value.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var normalizedWhitespace: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var decodedHTML: String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return self
        }
        return attributed.string
    }

    var strippedHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .decodedHTML
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var decodedHTMLEntitiesPreservingLineBreaks: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map(\.decodedHTML)
            .joined(separator: "\n")
    }

    var readableHTMLText: String {
        let blockAwareHTML = self
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p\s*>"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</div\s*>"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</li\s*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<li[^>]*>"#, with: "• ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</h[1-6]\s*>"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</pre\s*>"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</blockquote\s*>"#, with: "\n\n", options: .regularExpression)

        let withoutTags = blockAwareHTML
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .decodedHTMLEntitiesPreservingLineBreaks
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let normalizedLines = withoutTags
            .components(separatedBy: "\n")
            .map { line in
                line.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }

        let joined = normalizedLines.joined(separator: "\n")
        let collapsedBlankLines = joined
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return collapsedBlankLines
    }

    var renderableHTMLBlocks: [HTMLRenderableBlock] {
        let pattern = #"<img\b[^>]*\bsrc\s*=\s*(?:(['"])(.*?)\1|([^'">\s]+))[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return structuredTextBlocks(from: self)
        }

        let nsRange = NSRange(startIndex..<endIndex, in: self)
        let matches = regex.matches(in: self, range: nsRange)
        if matches.isEmpty {
            return structuredTextBlocks(from: self)
        }

        var blocks: [HTMLRenderableBlock] = []
        var cursor = startIndex
        var bufferedHTML = ""

        for match in matches {
            guard let wholeRange = Range(match.range(at: 0), in: self) else {
                continue
            }

            let leadingHTML = String(self[cursor..<wholeRange.lowerBound])
            let rawSource: String
            if let quotedRange = Range(match.range(at: 2), in: self) {
                rawSource = String(self[quotedRange])
            } else if let unquotedRange = Range(match.range(at: 3), in: self) {
                rawSource = String(self[unquotedRange])
            } else {
                cursor = wholeRange.upperBound
                continue
            }
            let tagHTML = String(self[wholeRange])
            let style = htmlImageStyle(for: tagHTML, source: rawSource)

            switch style {
            case .content:
                bufferedHTML += leadingHTML
                appendTextBlock(from: bufferedHTML, into: &blocks)
                bufferedHTML = ""
                if let url = normalizedHTMLImageURL(from: rawSource) {
                    blocks.append(.image(url, style: .content))
                }
            case .embedded:
                bufferedHTML += leadingHTML
                bufferedHTML += normalizedEmbeddedHTMLTag(tagHTML, source: rawSource)
            case .emoji:
                bufferedHTML += leadingHTML
                if let url = normalizedHTMLImageURL(from: rawSource) {
                    bufferedHTML += inlineEmojiHTMLTag(for: url)
                }
            }

            cursor = wholeRange.upperBound
        }

        bufferedHTML += String(self[cursor..<endIndex])
        appendTextBlock(from: bufferedHTML, into: &blocks)
        return blocks
    }

    private func appendTextBlock(from html: String, into blocks: inout [HTMLRenderableBlock]) {
        blocks.append(contentsOf: structuredTextBlocks(from: html))
    }

    private func normalizedHTMLImageURL(from rawValue: String) -> URL? {
        if rawValue.hasPrefix("//") {
            return URL(string: "https:\(rawValue)")
        }
        if rawValue.hasPrefix("/") {
            return URL(string: "https://www.v2ex.com\(rawValue)")
        }
        return URL(string: rawValue)
    }

    private func structuredTextBlocks(from html: String) -> [HTMLRenderableBlock] {
        let separator = "\u{001E}"
        let markedHTML = html
            .replacingOccurrences(of: #"(?i)</p\s*>"#, with: "$0\(separator)", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</div\s*>"#, with: "$0\(separator)", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</blockquote\s*>"#, with: "$0\(separator)", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</pre\s*>"#, with: "$0\(separator)", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</li\s*>"#, with: "$0\(separator)", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</h([1-6])\s*>"#, with: "$0\(separator)", options: .regularExpression)

        return markedHTML
            .components(separatedBy: separator)
            .compactMap { fragment in
                let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.readableHTMLText.isEmpty || trimmed.contains("<img") else { return nil }
                let style = htmlTextStyle(for: trimmed)
                return .text(html: normalizedHTMLFragment(trimmed, style: style), style: style)
            }
    }

    private func htmlTextStyle(for fragment: String) -> HTMLTextStyle {
        if let match = firstRegexCapture(in: fragment, pattern: #"(?i)<h([1-6])[^>]*>"#),
           let level = Int(match) {
            return .heading(level: level)
        }
        if fragment.range(of: #"(?i)<blockquote[^>]*>"#, options: .regularExpression) != nil {
            return .quote
        }
        if fragment.range(of: #"(?i)<pre[^>]*>"#, options: .regularExpression) != nil {
            return .code
        }
        if fragment.range(of: #"(?i)<li[^>]*>"#, options: .regularExpression) != nil {
            return .listItem
        }
        return .body
    }

    private func normalizedHTMLFragment(_ fragment: String, style: HTMLTextStyle) -> String {
        switch style {
        case .body:
            return fragment
        case .quote:
            return fragment.range(of: #"(?i)<blockquote[^>]*>"#, options: .regularExpression) == nil
                ? "<blockquote>\(fragment)</blockquote>"
                : fragment
        case .code:
            return fragment.range(of: #"(?i)<pre[^>]*>"#, options: .regularExpression) == nil
                ? "<pre>\(fragment)</pre>"
                : fragment
        case .heading(let level):
            return fragment.range(of: #"(?i)<h[1-6][^>]*>"#, options: .regularExpression) == nil
                ? "<h\(level)>\(fragment)</h\(level)>"
                : fragment
        case .listItem:
            if fragment.range(of: #"(?i)<li[^>]*>"#, options: .regularExpression) != nil {
                return "<ul>\(fragment)</ul>"
            }
            return "<ul><li>\(fragment)</li></ul>"
        }
    }

    private func firstRegexCapture(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: source) else {
            return nil
        }

        return String(source[range])
    }

    private func htmlImageStyle(for tagHTML: String, source: String) -> HTMLImageStyle {
        let loweredTag = tagHTML.lowercased()
        let loweredSource = source.lowercased()

        if loweredTag.contains("embedded_image") {
            return .embedded
        }

        if loweredTag.contains("emoji")
            || loweredTag.contains("emoticon")
            || loweredTag.contains("smiley")
            || loweredSource.contains("emoji")
            || loweredSource.contains("emoticon")
            || loweredSource.contains("smiley") {
            return .emoji(size: 24)
        }

        let width = firstRegexCapture(in: tagHTML, pattern: #"(?i)\bwidth="(\d+)""#).flatMap(Double.init)
        let height = firstRegexCapture(in: tagHTML, pattern: #"(?i)\bheight="(\d+)""#).flatMap(Double.init)
        let candidate = max(width ?? 0, height ?? 0)

        if candidate > 0, candidate <= 128 {
            return .emoji(size: min(CGFloat(candidate), 28))
        }

        return .content
    }

    private func inlineEmojiHTMLTag(for url: URL) -> String {
        #"<img class="v2ex-inline-emoji" src="\#(url.absoluteString)" alt="emoji">"#
    }

    private func normalizedEmbeddedHTMLTag(_ tagHTML: String, source: String) -> String {
        guard let url = normalizedHTMLImageURL(from: source) else {
            return tagHTML
        }

        let replacedDoubleQuoted = tagHTML.replacingOccurrences(
            of: #"(?i)\bsrc\s*=\s*"[^"]*""#,
            with: #"src="\#(url.absoluteString)""#,
            options: .regularExpression
        )

        if replacedDoubleQuoted != tagHTML {
            return replacedDoubleQuoted
        }

        let replacedSingleQuoted = tagHTML.replacingOccurrences(
            of: #"(?i)\bsrc\s*=\s*'[^']*'"#,
            with: #"src="\#(url.absoluteString)""#,
            options: .regularExpression
        )

        if replacedSingleQuoted != tagHTML {
            return replacedSingleQuoted
        }

        return #"<img src="\#(url.absoluteString)" class="embedded_image">"#
    }

    var attributedHTML: AttributedString {
        let html = """
        <html>
        <head>
        <meta name="viewport" content="initial-scale=1.0" />
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: 17px;
            line-height: 1.55;
            margin: 0;
            padding: 0;
        }
        p, div, ul, ol, li, blockquote, pre, h1, h2, h3, h4, h5, h6 {
            margin: 0;
            padding: 0;
        }
        h1, h2, h3, h4, h5, h6 {
            font-weight: 700;
        }
        blockquote {
            color: #6b7280;
        }
        pre {
            font-family: Menlo, Monaco, monospace;
            font-size: 14px;
            white-space: pre-wrap;
        }
        a {
            color: #0a84ff;
            text-decoration: none;
        }
        strong, b {
            font-weight: 600;
        }
        </style>
        </head>
        <body>\(self)</body>
        </html>
        """

        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ),
              let swiftUIAttributed = try? AttributedString(attributed, including: \.uiKit) else {
            return AttributedString(readableHTMLText)
        }

        return swiftUIAttributed
    }
}

extension Date {
    var relativeText: String {
        RelativeDateTimeFormatter().localizedString(for: self, relativeTo: Date())
    }
}

extension View {
    func cardStyle() -> some View {
        padding(14)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            )
    }
}
