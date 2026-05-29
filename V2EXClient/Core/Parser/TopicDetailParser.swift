import Foundation

struct TopicDetailParser: Sendable {
    func parse(html: String, topic: Topic, sourceURL: URL) -> TopicDetail {
        let content = extractDivBody(
            from: html,
            classContaining: "topic_content"
        ) ?? extractDivBody(
            from: html,
            classContaining: "markdown_body"
        ) ?? ""

        let topicMetadata = parseTopicMetadata(from: html)
        let supplements = parseSupplements(from: html)
        let replies = parseReplies(from: html)

        return TopicDetail(
            topic: topic,
            contentHTML: content.trimmingCharacters(in: .whitespacesAndNewlines),
            createdText: topicMetadata.createdText,
            viewsText: topicMetadata.viewsText,
            supplements: supplements,
            replies: replies,
            sourceURL: sourceURL
        )
    }

    private func parseTopicMetadata(from html: String) -> (createdText: String?, viewsText: String?) {
        let contentStart = html.range(
            of: #"class=["'][^"']*(topic_content|markdown_body)[^"']*["']"#,
            options: .regularExpression
        )?.lowerBound ?? html.endIndex
        let headerHTML = String(html[..<contentStart])
        let headerText = metadataSearchText(from: headerHTML)

        let createdText = firstMatch(
            in: headerText,
            pattern: #"(?i)\bat\s+(.+?)\s+·\s+[\d,]+\s+views?\b"#
        ) ?? firstRelativeTimeText(in: headerText)
        let viewsText = firstMatch(
            in: headerText,
            pattern: #"(?i)\b([\d,]+\s+views?)\b"#
        )

        return (createdText, viewsText)
    }

    private func parseSupplements(from html: String) -> [TopicSupplement] {
        let replyStart = html.range(
            of: #"id="r_\d+""#,
            options: .regularExpression
        )?.lowerBound ?? html.endIndex
        let preReplyHTML = String(html[..<replyStart])
        let blocks = extractDivHTMLs(from: preReplyHTML, classContaining: "subtle")

        return blocks.enumerated().compactMap { index, block in
            guard var innerHTML = divInnerHTML(from: block) else {
                return nil
            }

            let titleHTML = firstMatch(
                in: innerHTML,
                pattern: #"(?is)<span\b[^>]*\bclass=["'][^"']*\b(?:fade|gray|small)\b[^"']*["'][^>]*>(.*?(?:附言|Supplement).*?)</span>"#
            ) ?? firstMatch(
                in: innerHTML,
                pattern: #"(?is)<span\b[^>]*\bclass=["'][^"']*\bfade\b[^"']*["'][^>]*>(.*?)</span>"#
            )
            let title = titleHTML?.readableHTMLText ?? "Supplement \(index + 1)"

            innerHTML = innerHTML.replacingOccurrences(
                of: #"(?is)<span\b[^>]*\bclass=["'][^"']*\b(?:fade|gray|small)\b[^"']*["'][^>]*>.*?(?:附言|Supplement).*?</span>"#,
                with: "",
                options: .regularExpression
            )
            innerHTML = innerHTML.replacingOccurrences(
                of: #"(?is)<div\b[^>]*\bclass=["'][^"']*\bsep\d+\b[^"']*["'][^>]*>\s*</div>"#,
                with: "",
                options: .regularExpression
            )
            innerHTML = innerHTML.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !innerHTML.readableHTMLText.isEmpty else {
                return nil
            }

            return TopicSupplement(
                id: index + 1,
                title: title,
                contentHTML: innerHTML
            )
        }
    }

    private func parseReplies(from html: String) -> [Reply] {
        let ids = matches(in: html, pattern: #"id="r_(\d+)""#)
        let structuredDates = parseStructuredReplyDates(from: html)

        return ids.enumerated().compactMap { index, match in
            guard match.count >= 2,
                  let id = Int(match[1]),
                  let replyRange = html.range(of: #"id="r_\#(id)""#, options: .regularExpression) else {
                return nil
            }

            let tail = String(html[replyRange.lowerBound...])
            let replyHTML = extractDivHTML(from: tail, idEquals: "r_\(id)") ?? tail
            let username = firstMatch(in: replyHTML, pattern: #"/member/([^"]+)""#)?.decodedHTML ?? "unknown"
            let avatar = firstMatch(in: replyHTML, pattern: #"<img[^>]*src="([^"]+)""#).flatMap(normalizeAvatar)
            let content = extractDivBody(from: replyHTML, classContaining: "reply_content") ?? ""
            let structuredDate = index < structuredDates.count ? structuredDates[index] : nil
            let createdText = firstRelativeTimeText(in: metadataSearchText(from: replyHTML))
                ?? structuredDate?.relativeText

            return Reply(
                id: id,
                floor: index + 1,
                member: Member(id: nil, username: username, avatarURL: avatar, tagline: nil),
                contentHTML: content.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: structuredDate,
                createdText: createdText
            )
        }
    }

    private func extractDivBody(from html: String, classContaining className: String) -> String? {
        guard let block = extractDivHTML(from: html, classContaining: className) else {
            return nil
        }

        return divInnerHTML(from: block)
    }

    private func extractDivHTML(from html: String, classContaining className: String) -> String? {
        extractDivHTML(from: html) { tag in
            tag.hasClass(containing: className)
        }
    }

    private func extractDivHTML(from html: String, idEquals id: String) -> String? {
        extractDivHTML(from: html) { tag in
            tag.contains(#"id="\#(id)""#)
        }
    }

    private func extractDivHTML(
        from html: String,
        where predicate: (String) -> Bool
    ) -> String? {
        extractDivHTMLs(from: html, where: predicate).first
    }

    private func extractDivHTMLs(from html: String, classContaining className: String) -> [String] {
        extractDivHTMLs(from: html) { tag in
            tag.hasClass(containing: className)
        }
    }

    private func extractDivHTMLs(
        from html: String,
        where predicate: (String) -> Bool
    ) -> [String] {
        var searchStart = html.startIndex
        var blocks: [String] = []

        while let openRange = html.range(of: "<div", range: searchStart..<html.endIndex) {
            guard let tagEnd = html[openRange.lowerBound...].firstIndex(of: ">") else {
                return blocks
            }

            let tag = String(html[openRange.lowerBound...tagEnd])
            if predicate(tag),
               let fullRange = balancedDivRange(in: html, startingAt: openRange.lowerBound) {
                blocks.append(String(html[fullRange]))
                searchStart = fullRange.upperBound
            } else {
                searchStart = html.index(after: tagEnd)
            }
        }

        return blocks
    }

    private func divInnerHTML(from block: String) -> String? {
        guard let bodyStart = block.firstIndex(of: ">"),
              block.index(after: bodyStart) <= block.index(before: block.endIndex) else {
            return nil
        }

        let start = block.index(after: bodyStart)
        let end = block.index(block.endIndex, offsetBy: -6)
        guard start <= end else { return nil }
        return String(block[start..<end])
    }

    private func balancedDivRange(in html: String, startingAt start: String.Index) -> Range<String.Index>? {
        var cursor = start
        var depth = 0

        while cursor < html.endIndex {
            let nextOpen = html.range(of: "<div", range: cursor..<html.endIndex)
            let nextClose = html.range(of: "</div>", range: cursor..<html.endIndex)

            guard let event = nextEvent(open: nextOpen, close: nextClose) else {
                return nil
            }

            switch event {
            case .open(let range):
                depth += 1
                cursor = range.upperBound
            case .close(let range):
                depth -= 1
                cursor = range.upperBound
                if depth == 0 {
                    return start..<cursor
                }
            }
        }

        return nil
    }

    private func nextEvent(
        open: Range<String.Index>?,
        close: Range<String.Index>?
    ) -> DivEvent? {
        switch (open, close) {
        case let (open?, close?):
            return open.lowerBound < close.lowerBound ? .open(open) : .close(close)
        case let (open?, nil):
            return .open(open)
        case let (nil, close?):
            return .close(close)
        case (nil, nil):
            return nil
        }
    }

    private func normalizeAvatar(_ raw: String) -> URL? {
        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }
        return URL(string: raw)
    }

    private func firstRelativeTimeText(in source: String) -> String? {
        let patterns = [
            #"(?i)\b\d+\s*h(?:\s+\d+\s*m)?\s+ago\b"#,
            #"(?i)\b\d+\s*小时(?:\s*\d+\s*分钟)?前\b"#,
            #"(?i)\b\d+\s*m\s+ago\b"#,
            #"(?i)\b\d+\s*分钟(?:前)?\b"#,
            #"(?i)\b\d+\s*s\s+ago\b"#,
            #"(?i)\b\d+\s*秒前\b"#,
            #"(?i)\b\d+\s*d\s+ago\b"#,
            #"(?i)\b\d+\s*天前\b"#,
            #"(?i)\b\d+\s+(?:second|minute|hour|day|week|month|year)s?\s+ago\b"#,
            #"(?i)\bjust now\b"#
        ]

        for pattern in patterns {
            if let match = firstWholeMatch(in: source, pattern: pattern) {
                return match.normalizedWhitespace
            }
        }

        return nil
    }

    private func parseStructuredReplyDates(from html: String) -> [Date?] {
        extractJSONLDScripts(from: html).flatMap { script in
            guard let data = script.data(using: .utf8),
                  let structuredData = try? JSONDecoder().decode(StructuredTopicData.self, from: data),
                  let comments = structuredData.comment else {
                return [Date?]()
            }

            return comments.map { comment in
                comment.datePublished.flatMap(parseISO8601Date)
            }
        }
    }

    private func extractJSONLDScripts(from html: String) -> [String] {
        matches(
            in: html,
            pattern: #"(?is)<script\b[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        ).compactMap { match in
            match.dropFirst().first?.decodedHTML
        }
    }

    private func parseISO8601Date(_ rawValue: String) -> Date? {
        ISO8601DateFormatter().date(from: rawValue)
    }

    private func metadataSearchText(from html: String) -> String {
        html.replacingOccurrences(
            of: #"(?is)<script\b[^>]*>.*?</script>"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"(?is)<style\b[^>]*>.*?</style>"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .decodedHTML
            .normalizedWhitespace
    }

    private func firstMatch(in source: String, pattern: String) -> String? {
        matches(in: source, pattern: pattern).first?.dropFirst().first
    }

    private func firstWholeMatch(in source: String, pattern: String) -> String? {
        matches(in: source, pattern: pattern).first?.first
    }

    private func matches(in source: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: nsRange).map { result in
            (0..<result.numberOfRanges).compactMap { index in
                guard let range = Range(result.range(at: index), in: source) else { return nil }
                return String(source[range])
            }
        }
    }
}

private extension String {
    func hasClass(containing className: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"\bclass\s*=\s*(['"])(.*?)\1"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return false
        }

        let nsRange = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: nsRange),
              let range = Range(match.range(at: 2), in: self) else {
            return false
        }

        return self[range].range(of: className, options: .caseInsensitive) != nil
    }
}

private enum DivEvent {
    case open(Range<String.Index>)
    case close(Range<String.Index>)
}

private struct StructuredTopicData: Decodable {
    let comment: [StructuredComment]?
}

private struct StructuredComment: Decodable {
    let datePublished: String?
}
