import XCTest
@testable import V2EXClient

final class TopicDetailParserTests: XCTestCase {
    func testParseTopicContentAndReplies() {
        let topic = Topic(
            id: 1,
            title: "Hello",
            url: URL(string: "https://www.v2ex.com/t/1")!,
            replies: 1,
            member: Member(id: 1, username: "alice", avatarURL: nil, tagline: nil),
            node: Node(id: 1, name: "swift", title: "Swift", topics: 1),
            createdAt: nil,
            lastReplyAt: nil
        )
        let html = """
        <span class="gray">By <a href="/member/alice">alice</a> at 7h 32m ago · 7197 views</span>
        <div class="topic_content">正文 <b>内容</b></div>
        <div id="r_100"><table><tr><td><a href="/member/bob">bob</a><img src="//cdn.v2ex.com/a.png"><span class="fade small">7h 30m ago</span><div class="reply_content">回复 &amp; 内容</div></td></tr></table></div>
        """

        let detail = TopicDetailParser().parse(html: html, topic: topic, sourceURL: topic.url)

        XCTAssertEqual(detail.contentHTML.strippedHTML, "正文 内容")
        XCTAssertEqual(detail.createdText, "7h 32m ago")
        XCTAssertEqual(detail.viewsText, "7197 views")
        XCTAssertEqual(detail.replies.count, 1)
        XCTAssertEqual(detail.replies[0].id, 100)
        XCTAssertEqual(detail.replies[0].floor, 1)
        XCTAssertEqual(detail.replies[0].member.username, "bob")
        XCTAssertEqual(detail.replies[0].contentHTML.strippedHTML, "回复 & 内容")
        XCTAssertEqual(detail.replies[0].createdText, "7h 30m ago")
    }

    func testParseTopicMetadataIgnoresStyleTextBeforeHeader() {
        let topic = Topic(
            id: 5,
            title: "CSS",
            url: URL(string: "https://www.v2ex.com/t/5")!,
            replies: 0,
            member: Member(id: 1, username: "alice", avatarURL: nil, tagline: nil),
            node: Node(id: 1, name: "swift", title: "Swift", topics: 1),
            createdAt: nil,
            lastReplyAt: nil
        )
        let html = """
        <style>
        .avatar { background: radial-gradient(circle at 50% 50%); clip-path: ellipse(100% 100%); }
        </style>
        <span class="gray">By <a href="/member/alice">alice</a> at 5h 1m ago · 1625 views</span>
        <div class="topic_content">正文</div>
        """

        let detail = TopicDetailParser().parse(html: html, topic: topic, sourceURL: topic.url)

        XCTAssertEqual(detail.createdText, "5h 1m ago")
        XCTAssertEqual(detail.viewsText, "1625 views")
    }

    func testParseReplyTimeFromStructuredDataWhenVisibleTimeIsMissing() {
        let topic = Topic(
            id: 4,
            title: "Structured",
            url: URL(string: "https://www.v2ex.com/t/4")!,
            replies: 1,
            member: Member(id: 1, username: "alice", avatarURL: nil, tagline: nil),
            node: Node(id: 1, name: "swift", title: "Swift", topics: 1),
            createdAt: nil,
            lastReplyAt: nil
        )
        let html = """
        <script type="application/ld+json">
        {"@type":"DiscussionForumPosting","comment":[{"datePublished":"2026-05-27T10:08:22Z"}]}
        </script>
        <div class="topic_content">正文</div>
        <div id="r_101"><table><tr><td><a href="/member/chisa">chisa</a><div class="reply_content">没有可见时间</div></td></tr></table></div>
        """

        let detail = TopicDetailParser().parse(html: html, topic: topic, sourceURL: topic.url)
        let expectedDate = ISO8601DateFormatter().date(from: "2026-05-27T10:08:22Z")

        XCTAssertEqual(detail.replies.count, 1)
        XCTAssertEqual(detail.replies[0].createdAt, expectedDate)
        XCTAssertNotNil(detail.replies[0].createdText)
    }

    func testParseNestedTopicContent() {
        let topic = Topic(
            id: 2,
            title: "Nested",
            url: URL(string: "https://www.v2ex.com/t/2")!,
            replies: 0,
            member: Member(id: 1, username: "alice", avatarURL: nil, tagline: nil),
            node: Node(id: 1, name: "swift", title: "Swift", topics: 1),
            createdAt: nil,
            lastReplyAt: nil
        )
        let html = """
        <div class="topic_content">
            正文
            <div class="inner">嵌套内容</div>
            <p>更多内容</p>
        </div>
        """

        let detail = TopicDetailParser().parse(html: html, topic: topic, sourceURL: topic.url)

        XCTAssertTrue(detail.contentHTML.contains("嵌套内容"))
        XCTAssertEqual(detail.contentHTML.strippedHTML.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: ""), "正文嵌套内容更多内容")
    }

    func testParseTopicSupplementsBeforeReplies() {
        let topic = Topic(
            id: 3,
            title: "Supplements",
            url: URL(string: "https://www.v2ex.com/t/3")!,
            replies: 1,
            member: Member(id: 1, username: "alice", avatarURL: nil, tagline: nil),
            node: Node(id: 1, name: "swift", title: "Swift", topics: 1),
            createdAt: nil,
            lastReplyAt: nil
        )
        let html = """
        <div class="topic_content">正文内容</div>
        <div class="subtle">
          <span class="fade">Supplement 1 · 2 小时前</span>
          <div class="sep10"></div>
          如果只是喜欢 IDEA 的版本控制，可以试试 <a href="https://example.com">Git 客户端</a>。
        </div>
        <div id="r_100"><table><tr><td><a href="/member/bob">bob</a><div class="reply_content">回复内容</div></td></tr></table></div>
        """

        let detail = TopicDetailParser().parse(html: html, topic: topic, sourceURL: topic.url)

        XCTAssertEqual(detail.supplements.count, 1)
        XCTAssertEqual(detail.supplements[0].id, 1)
        XCTAssertEqual(detail.supplements[0].title, "Supplement 1 · 2 小时前")
        XCTAssertEqual(detail.supplements[0].contentHTML.strippedHTML, "如果只是喜欢 IDEA 的版本控制，可以试试 Git 客户端。")
        XCTAssertEqual(detail.replies.count, 1)
    }

    func testParseChineseTopicSupplementsWithSingleQuotedClass() {
        let topic = Topic(
            id: 4,
            title: "Chinese Supplements",
            url: URL(string: "https://www.v2ex.com/t/4")!,
            replies: 1,
            member: Member(id: 1, username: "alice", avatarURL: nil, tagline: nil),
            node: Node(id: 1, name: "claude", title: "Claude", topics: 1),
            createdAt: nil,
            lastReplyAt: nil
        )
        let html = """
        <div class="topic_content">正文内容</div>
        <div class='subtle'>
          <span class='fade'>第 1 条附言 · 11 分钟前</span>
          <div class='sep10'></div>
          总结，claude 因为各种限制，目前我是靠 kiro 用 claude。
        </div>
        <div id="r_100"><table><tr><td><a href="/member/bob">bob</a><div class="reply_content">回复内容</div></td></tr></table></div>
        """

        let detail = TopicDetailParser().parse(html: html, topic: topic, sourceURL: topic.url)

        XCTAssertEqual(detail.supplements.count, 1)
        XCTAssertEqual(detail.supplements[0].title, "第 1 条附言 · 11 分钟前")
        XCTAssertEqual(detail.supplements[0].contentHTML.strippedHTML, "总结，claude 因为各种限制，目前我是靠 kiro 用 claude。")
        XCTAssertEqual(detail.replies.count, 1)
    }

    func testRenderableBlocksIncludeImages() {
        let html = """
        <p>第一段</p>
        <img src="//cdn.v2ex.com/test.png">
        <p>第二段</p>
        """

        let blocks = html.renderableHTMLBlocks

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].plainText, "第一段")
        XCTAssertEqual(blocks[1], .image(URL(string: "https://cdn.v2ex.com/test.png")!, style: .content))
        XCTAssertEqual(blocks[2].plainText, "第二段")
    }

    func testRenderableBlocksKeepEmojiImagesSmall() {
        let html = #"<img src="//cdn.v2ex.com/emoji/smile.png" width="48" height="48">"#

        let blocks = html.renderableHTMLBlocks

        XCTAssertEqual(blocks, [.text(html: #"<img class="v2ex-inline-emoji" src="https://cdn.v2ex.com/emoji/smile.png" alt="emoji">"#, style: .body)])
    }

    func testRenderableBlocksHandleSingleQuotedImageSource() {
        let html = "<img src='//cdn.v2ex.com/emoji/think.png' width='48' height='48'>"

        let blocks = html.renderableHTMLBlocks

        XCTAssertEqual(blocks, [.text(html: #"<img class="v2ex-inline-emoji" src="https://cdn.v2ex.com/emoji/think.png" alt="emoji">"#, style: .body)])
    }

    func testRenderableBlocksKeepEmbeddedImagesInHTMLSnippet() {
        let html = #"我 15pro 换 17pro 要 3699 <img src="https://i.imgur.com/MAyk5GN.png" class="embedded_image" rel="noreferrer">"#

        let blocks = html.renderableHTMLBlocks

        XCTAssertEqual(blocks.count, 1)

        guard case let .text(fragment, style) = blocks[0] else {
            return XCTFail("Expected embedded image to remain inside a text fragment")
        }

        XCTAssertEqual(style, .body)
        XCTAssertTrue(fragment.contains("embedded_image"))
        XCTAssertTrue(fragment.contains("https://i.imgur.com/MAyk5GN.png"))
    }

    func testRenderableBlocksSplitParagraphs() {
        let html = """
        <p>第一段</p>
        <p>第二段<br>第二段续行</p>
        <div>第三段</div>
        """

        let blocks = html.renderableHTMLBlocks

        XCTAssertEqual(blocks.compactMap(\.plainText), ["第一段", "第二段\n第二段续行", "第三段"])
    }

    func testRenderableBlocksPreserveHeadingAndQuoteStyles() {
        let html = """
        <h2>标题</h2>
        <blockquote>引用内容</blockquote>
        """

        let blocks = html.renderableHTMLBlocks

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], .text(html: "<h2>标题</h2>", style: .heading(level: 2)))
        XCTAssertEqual(blocks[1], .text(html: "<blockquote>引用内容</blockquote>", style: .quote))
    }

    func testNodeTopicListParserReadsSchemaPageItems() {
        let html = """
        <title>V2EX › Apple</title>
        <script type="application/ld+json">
        {
          "mainEntity": {
            "numberOfItems": 30649,
            "itemListElement": [
              {
                "item": {
                  "url": "https://www.v2ex.com/t/1213831",
                  "headline": "记录 &amp; 测试",
                  "commentCount": 29,
                  "datePublished": "2026-05-19T07:30:04Z",
                  "author": { "name": "luvcoriander" }
                }
              }
            ]
          }
        }
        </script>
        """

        let topics = NodeTopicListParser().parse(html: html, fallbackNodeName: "apple")

        XCTAssertEqual(topics.count, 1)
        XCTAssertEqual(topics[0].id, 1213831)
        XCTAssertEqual(topics[0].title, "记录 & 测试")
        XCTAssertEqual(topics[0].replies, 29)
        XCTAssertEqual(topics[0].member.username, "luvcoriander")
        XCTAssertEqual(topics[0].node.name, "apple")
        XCTAssertEqual(topics[0].node.title, "Apple")
        XCTAssertEqual(topics[0].node.topics, 30649)
    }

    func testNodeTopicListParserFallsBackToTopicCells() {
        let html = """
        <title>V2EX › Apple</title>
        <div class="cell from_1 t_1213246">
          <table>
            <tr>
              <td><a href="/member/esrkforward"><img src="//cdn.v2ex.com/avatar.png" class="avatar" data-uid="42" /></a></td>
              <td>
                <span class="item_title"><a href="/t/1213246#reply8" class="topic-link">如果大家近期考虑入手 Mac mini 丐版，可以考虑去 Apple 认证零售商处自提</a></span>
                <span class="topic_info"><strong><a href="/member/esrkforward">esrkforward</a></strong></span>
              </td>
              <td><a href="/t/1213246#reply8" class="count_livid">8</a></td>
            </tr>
          </table>
        </div>
        """

        let topics = NodeTopicListParser().parse(html: html, fallbackNodeName: "apple")

        XCTAssertEqual(topics.count, 1)
        XCTAssertEqual(topics[0].id, 1213246)
        XCTAssertEqual(topics[0].replies, 8)
        XCTAssertEqual(topics[0].member.id, 42)
        XCTAssertEqual(topics[0].member.username, "esrkforward")
        XCTAssertEqual(topics[0].member.avatarURL, URL(string: "https://cdn.v2ex.com/avatar.png"))
        XCTAssertEqual(topics[0].node.title, "Apple")
    }

    func testCategoryTopicListParserReadsTopicCellNodes() {
        let html = """
        <div class="cell from_1 t_1214000">
          <table>
            <tr>
              <td><a href="/member/a0210077"><img src="//cdn.v2ex.com/avatar.png" class="avatar" data-uid="42" /></a></td>
              <td>
                <span class="item_title"><a href="/t/1214000#reply37" class="topic-link">公司不给钱我该用哪个 AI 码代码?</a></span>
                <span class="topic_info">
                  <a class="node" href="/go/programmer">程序员</a>
                  <strong><a href="/member/a0210077">a0210077</a></strong>
                </span>
              </td>
              <td><a href="/t/1214000#reply37" class="count_livid">37</a></td>
            </tr>
          </table>
        </div>
        <div class="cell from_2 t_1214001">
          <table>
            <tr>
              <td><a href="/member/ddter"><img src="//cdn.v2ex.com/cloud.png" class="avatar" /></a></td>
              <td>
                <span class="item_title"><a href="/t/1214001#reply95" class="topic-link">阿里云的 dns 解析要收钱了</a></span>
                <span class="topic_info">
                  <a class="node" href="/go/cloud">云计算</a>
                  <strong><a href="/member/ddter">ddter</a></strong>
                </span>
              </td>
              <td><a href="/t/1214001#reply95" class="count_livid">95</a></td>
            </tr>
          </table>
        </div>
        """

        let topics = NodeTopicListParser().parseCells(html: html, fallbackNodeName: "tech")

        XCTAssertEqual(topics.count, 2)
        XCTAssertEqual(topics[0].node.name, "programmer")
        XCTAssertEqual(topics[0].node.title, "程序员")
        XCTAssertEqual(topics[0].replies, 37)
        XCTAssertEqual(topics[1].node.name, "cloud")
        XCTAssertEqual(topics[1].node.title, "云计算")
        XCTAssertEqual(topics[1].replies, 95)
    }
}
