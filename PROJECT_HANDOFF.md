# V2EX iOS Client Project Handoff

## Project Overview

Project path:

```text
/Users/wadxm/Documents/Codex/2026-05-11/ios-app-v2ex
```

This is a native iOS client for V2EX.

Current technical choices:

- Swift + SwiftUI
- iOS 17+
- Lightweight MVVM + Service architecture
- URLSession + async/await
- Simple memory and disk cache
- Mixed data source: V2EX public APIs plus HTML parsing

The current project directory does not appear to be a Git repository. Running `git status` from the project root currently fails.

## Important Files

App:

- `V2EXClient/App/V2EXClientApp.swift`: app entry point
- `V2EXClient/App/AppRouter.swift`: main navigation and tab structure

Core:

- `V2EXClient/Core/Models/Models.swift`: `Topic`, `Member`, `Node`, `Reply`, `TopicDetail`, `TopicFeed`, `LoadState`
- `V2EXClient/Core/Network/NetworkClient.swift`: shared network client
- `V2EXClient/Core/Services/V2EXService.swift`: V2EX data service
- `V2EXClient/Core/Services/SessionStore.swift`: session/login-state placeholder
- `V2EXClient/Core/Cache/CacheStore.swift`: memory and disk cache
- `V2EXClient/Core/Parser/TopicDetailParser.swift`: topic-detail HTML parser
- `V2EXClient/Core/Utilities.swift`: HTML text/image rendering helpers
- `V2EXClient/Core/Components.swift`: shared SwiftUI components such as topic rows and state views

Features:

- `V2EXClient/Features/Home/HomeView.swift`: home page and V2EX-like top node navigation
- `V2EXClient/Features/Home/HomeViewModel.swift`: home loading, category, node and pagination state
- `V2EXClient/Features/TopicDetail/TopicDetailView.swift`: topic detail page with web/simplified modes
- `V2EXClient/Features/TopicDetail/TopicDetailViewModel.swift`: topic detail loading state
- `V2EXClient/Features/TopicDetail/WebView.swift`: WebView wrapper
- `V2EXClient/Features/Node/NodeView.swift`: standalone node page
- `V2EXClient/Features/Node/NodeViewModel.swift`: node page loading and pagination
- `V2EXClient/Features/User/UserView.swift`: user page
- `V2EXClient/Features/User/UserViewModel.swift`: user page view model
- `V2EXClient/Features/Search/SearchView.swift`: basic search screen
- `V2EXClient/Features/Settings/SettingsView.swift`: settings screen
- `V2EXClient/Features/Settings/SettingsStore.swift`: persisted appearance/font/cache preferences

Tests:

- `V2EXClientTests/TopicDetailParserTests.swift`
- `V2EXClientTests/NetworkClientTests.swift`
- `V2EXClientTests/SettingsStoreTests.swift`

## Current Feature Status

Implemented:

- Home topic list
- Hot/latest feeds
- V2EX-style primary category navigation
- Secondary nodes under primary categories
- Node topic lists
- Node topic pagination
- Topic detail page
- Topic detail web/simplified mode switch
- Topic content and reply parsing
- Basic support for text blocks, images, embedded images, inline small images, links, headings, quotes, code and lists in simplified detail view
- Local favorite state for node pages
- Basic search screen
- Basic settings screen
- Pull-to-refresh
- Loading, empty and error states

Primary categories currently modeled in `HomeView.swift`:

- 技术
- 创意
- 好玩
- Apple
- 酷工作
- 交易
- 城市
- 问与答
- 最热
- 全部
- R2
- VXNA

Some important secondary-node examples:

- 技术: 程序员, Python, iDev, Claude, OpenAI, Local LLM, 云计算, 宽带症候群
- Apple: Apple, macOS, iPhone, iOS, iPad, Xcode, AirPods
- 城市: 北京, 上海, 深圳, 杭州, 成都, 广州, 香港, 武汉

## Data Strategy

General topic feeds:

- Hot feed uses `/api/topics/hot.json`
- Latest feed uses `/api/topics/latest.json`

Node metadata:

- Uses `/api/nodes/show.json?name={node}`

Node topic lists:

- Important: do not rely on `/api/v2/nodes/{node}/topics?p={page}` for unauthenticated pagination.
- As of the latest debugging, that endpoint returns `401 Token not found`.
- Current implementation uses the public web page instead:

```text
https://www.v2ex.com/go/{node}?p={page}
```

The app parses node pages with `NodeTopicListParser` in `V2EXService.swift`.

Parsing order:

1. Parse the page's `application/ld+json` JSON-LD topic list.
2. If that fails, parse topic cell HTML as a fallback.

Cache key for node pages:

```text
node-topics-web-{name}-page-{page}
```

This key intentionally differs from an older key so previously cached 10-topic API responses do not keep showing.

Topic detail:

- Fetches the topic web page.
- Parses HTML with `TopicDetailParser`.
- Simplified mode renders parsed HTML through helpers in `Utilities.swift`.
- Web mode uses `WebView`.

## Important Recent Fixes

### Topic Detail Stuck Loading

Previously, opening a topic could get stuck on a loading screen. That has been fixed, and topic details now open successfully.

### Simplified Mode Images And Formatting

Several issues were fixed:

- Topic images were not visible in simplified mode.
- Content did not preserve enough line breaks.
- Formatting was flattened too aggressively.
- V2EX `embedded_image` images were initially handled incorrectly.
- Small emoji-like images were too large or blurry.

Relevant logic:

- `V2EXClient/Core/Utilities.swift`
- `V2EXClient/Core/Parser/TopicDetailParser.swift`
- `V2EXClient/Features/TopicDetail/TopicDetailView.swift`

Current simplified rendering supports structured text blocks and image treatment, but this area still needs visual polish for complex V2EX posts.

### Node Pagination Only Showing 10 Topics

Root cause:

- The old node topic API returns only a small set.
- The attempted v2 pagination API returns `401 Token not found` without authentication.

Fix:

- `V2EXService.nodeTopics(name:page:refresh:)` now fetches and parses `/go/{node}?p={page}`.
- `NodeTopicListParser` parses JSON-LD first and cell HTML second.
- Parser tests were added.

## How To Build And Test

Recommended test command:

```bash
xcodebuild test \
  -project V2EXClient.xcodeproj \
  -scheme V2EXClient \
  -destination 'platform=iOS Simulator,OS=18.0,name=iPhone 16' \
  -derivedDataPath DerivedData
```

Latest known result:

```text
** TEST SUCCEEDED **
```

The app has also been built and launched successfully on an iOS 18.0 simulator.

## Known Limitations

- Login is not implemented.
- Replying, notifications, favorite topics, thanks and account actions are not implemented.
- Search page is currently basic.
- Settings page is basic.
- Simplified HTML rendering is usable but still not as complete as Safari/WebView.
- Node pagination depends on V2EX web page structure, so keep parser tests updated if V2EX changes HTML.
- There is no full offline mode.
- There is no image cache optimization beyond current simple caching infrastructure.

## Suggested Next Steps

1. Continue polishing simplified topic rendering.
2. Improve image layout and tap-to-preview behavior.
3. Add real search.
4. Expand settings for font size, appearance and cache clearing.
5. Move `NodeTopicListParser` out of `V2EXService.swift` into `Core/Parser` if the file grows.
6. Add more parser fixtures from real V2EX pages.
7. Implement login later with `WKWebView` and cookie reuse.

## Notes For The Next Codex

This is a SwiftUI V2EX client. The core browsing flow already works: home, categories, nodes, pagination and topic details.

The most important implementation detail is node pagination:

- Do not use `/api/v2/nodes/{node}/topics` for unauthenticated loading-more behavior.
- Use `/go/{node}?p={page}` and parse the web page.

Before making changes, run the test command above. If touching topic rendering or node pagination, add or update tests in `V2EXClientTests/TopicDetailParserTests.swift`.
