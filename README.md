# V2EXClient

SwiftUI 原生 V2EX iOS 客户端 MVP。

## 当前实现

- 热门 / 最新主题列表
- 主题详情与回复解析
- 节点详情、节点主题列表和本地收藏节点
- 用户资料页
- 搜索入口
- 设置页：外观、字体大小、缓存清理
- `NetworkClient`、`V2EXService`、`CacheStore`、`TopicDetailParser`、`SessionStore`
- 单元测试骨架：网络错误、HTML 解析、设置持久化

## 运行方式

1. 使用完整 Xcode 打开 `V2EXClient.xcodeproj`。
2. 选择 `V2EXClient` scheme。
3. 选择 iOS 17+ 模拟器或真机运行。

当前机器的 `xcodebuild` 指向 Command Line Tools，不是完整 Xcode，因此命令行 iOS 构建需要先在本机切换：

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 版权声明

本项目代码版权归项目作者所有。未经作者明确同意，任何个人或组织不得复制、修改、分发、发布、商用或以其他方式使用本项目代码。

如需使用本项目代码，请先联系项目作者并获得明确同意；在获得同意后，可按双方约定的范围使用。

## 后续重点

- 强化主题详情 HTML 渲染，支持图片预览、代码块和链接交互。
- 完善节点主题分页。
- 增加阅读历史和已读状态。
- 第二阶段加入 `WKWebView` 登录、Cookie 持久化、收藏和回复。
