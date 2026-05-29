import SwiftUI

struct HomeQuickNode: Identifiable, Hashable {
    let name: String
    let title: String

    var id: String { name }
}

enum HomePrimaryCategory: String, CaseIterable, Identifiable {
    case tech
    case creative
    case play
    case apple
    case jobs
    case deals
    case city
    case qna
    case hot
    case latest
    case r2
    case vxna

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tech: "技术"
        case .creative: "创意"
        case .play: "好玩"
        case .apple: "Apple"
        case .jobs: "酷工作"
        case .deals: "交易"
        case .city: "城市"
        case .qna: "问与答"
        case .hot: "最热"
        case .latest: "全部"
        case .r2: "R2"
        case .vxna: "VXNA"
        }
    }

    var feed: TopicFeed? {
        switch self {
        case .hot: .hot
        case .latest: .latest
        default: nil
        }
    }

    var tabName: String {
        switch self {
        case .latest:
            "all"
        default:
            rawValue
        }
    }

    var secondaryNodes: [HomeQuickNode] {
        switch self {
        case .tech:
            [
                .init(name: "programmer", title: "程序员"),
                .init(name: "python", title: "Python"),
                .init(name: "idev", title: "iDev"),
                .init(name: "claude", title: "Claude"),
                .init(name: "openai", title: "OpenAI"),
                .init(name: "localllm", title: "Local LLM"),
                .init(name: "cloud", title: "云计算"),
                .init(name: "bb", title: "宽带症候群")
            ]
        case .creative:
            [
                .init(name: "create", title: "分享创造"),
                .init(name: "design", title: "设计"),
                .init(name: "ideas", title: "奇思妙想"),
                .init(name: "share", title: "分享发现"),
                .init(name: "blog", title: "Blog"),
                .init(name: "starter", title: "创造者")
            ]
        case .play:
            [
                .init(name: "games", title: "游戏"),
                .init(name: "movie", title: "电影"),
                .init(name: "tv", title: "剧集"),
                .init(name: "music", title: "音乐"),
                .init(name: "travel", title: "旅行"),
                .init(name: "reading", title: "阅读")
            ]
        case .apple:
            [
                .init(name: "apple", title: "Apple"),
                .init(name: "macos", title: "macOS"),
                .init(name: "iphone", title: "iPhone"),
                .init(name: "ios", title: "iOS"),
                .init(name: "ipad", title: "iPad"),
                .init(name: "xcode", title: "Xcode"),
                .init(name: "airpods", title: "AirPods")
            ]
        case .jobs:
            [
                .init(name: "jobs", title: "酷工作"),
                .init(name: "remote", title: "远程工作"),
                .init(name: "career", title: "职场话题"),
                .init(name: "cv", title: "求职"),
                .init(name: "outsourcing", title: "外包")
            ]
        case .deals:
            [
                .init(name: "all4all", title: "二手交易"),
                .init(name: "deals", title: "优惠信息"),
                .init(name: "invest", title: "投资"),
                .init(name: "creditcard", title: "信用卡")
            ]
        case .city:
            [
                .init(name: "beijing", title: "北京"),
                .init(name: "shanghai", title: "上海"),
                .init(name: "shenzhen", title: "深圳"),
                .init(name: "hangzhou", title: "杭州"),
                .init(name: "chengdu", title: "成都"),
                .init(name: "guangzhou", title: "广州"),
                .init(name: "hongkong", title: "香港"),
                .init(name: "wuhan", title: "武汉")
            ]
        case .qna:
            [
                .init(name: "qna", title: "问与答"),
                .init(name: "share", title: "分享发现"),
                .init(name: "create", title: "分享创造"),
                .init(name: "ideas", title: "奇思妙想"),
                .init(name: "design", title: "设计"),
                .init(name: "blog", title: "Blog")
            ]
        default:
            []
        }
    }
}

struct HomeView: View {
    private let service: V2EXService
    @StateObject private var viewModel: HomeViewModel

    init(service: V2EXService) {
        self.service = service
        _viewModel = StateObject(wrappedValue: HomeViewModel(service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                topicList
            case .idle:
                if viewModel.topics.isEmpty {
                    LoadingStateView(title: "正在加载主题")
                } else {
                    topicList
                }
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await viewModel.load(refresh: true) }
                }
            case .empty, .loaded:
                topicList
            }
        }
        .navigationTitle("V2EX")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
        }
    }

    private var topicList: some View {
        List {
            navigationPanel
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)

            if case .loading = viewModel.state {
                loadingRow
                    .listRowSeparator(.hidden)
            } else if case .empty = viewModel.state {
                Text("这个节点下暂时没有可显示的主题")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.topics) { topic in
                    NavigationLink {
                        TopicDetailView(topic: topic, service: service)
                    } label: {
                        TopicRow(topic: topic)
                    }
                    .task {
                        await viewModel.loadMoreIfNeeded(currentTopic: topic)
                    }
                }

                if viewModel.canLoadMore || viewModel.isLoadingMore || viewModel.loadMoreError != nil {
                    loadMoreFooter
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.load(refresh: true)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在加载主题")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    private var navigationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(HomePrimaryCategory.allCases) { category in
                        Button {
                            viewModel.selectCategory(category)
                        } label: {
                            Text(category.title)
                                .font(.system(size: 17, weight: viewModel.selectedCategory == category ? .semibold : .regular))
                                .foregroundStyle(viewModel.selectedCategory == category ? .white : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(viewModel.selectedCategory == category ? Color(.label) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            if !viewModel.selectedCategory.secondaryNodes.isEmpty {
                Divider()
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.selectedCategory.secondaryNodes) { node in
                            Button {
                                viewModel.selectSecondaryNode(node)
                            } label: {
                                Text(node.title)
                                    .font(.system(size: 15, weight: viewModel.selectedNode == node ? .semibold : .regular))
                                    .foregroundStyle(viewModel.selectedNode == node ? .primary : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .overlay(alignment: .bottom) {
                                        if viewModel.selectedNode == node {
                                            Capsule()
                                                .fill(Color.accentColor)
                                                .frame(height: 3)
                                                .padding(.horizontal, 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                }
            }
        }
        .background(.background)
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        HStack {
            Spacer()
            if viewModel.isLoadingMore {
                ProgressView()
                    .padding(.vertical, 12)
            } else if viewModel.loadMoreError != nil {
                Button {
                    Task { await viewModel.loadMoreIfNeeded() }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .padding(.vertical, 8)
            } else {
                ProgressView()
                    .padding(.vertical, 12)
                    .task {
                        await viewModel.loadMoreIfNeeded()
                    }
            }
            Spacer()
        }
    }
}
