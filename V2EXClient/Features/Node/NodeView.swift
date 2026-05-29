import SwiftUI

struct NodeView: View {
    private let service: V2EXService
    @StateObject private var viewModel: NodeViewModel

    init(nodeName: String, service: V2EXService) {
        self.service = service
        _viewModel = StateObject(wrappedValue: NodeViewModel(nodeName: nodeName, service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingStateView(title: "正在加载节点")
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await viewModel.load(refresh: true) }
                }
            case .empty, .loaded:
                List {
                    if let node = viewModel.node {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(node.title)
                                    .font(.title2.weight(.semibold))
                                Text("/go/\(node.name)")
                                    .foregroundStyle(.secondary)
                                if let topics = node.topics {
                                    Text("\(topics) 个主题")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    Section("主题") {
                        if viewModel.topics.isEmpty {
                            Text("暂无可显示主题")
                                .foregroundStyle(.secondary)
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
                            }
                        }
                    }
                }
                .refreshable {
                    await viewModel.load(refresh: true)
                }
            }
        }
        .navigationTitle(viewModel.node?.title ?? "节点")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.toggleFavorite()
                } label: {
                    Image(systemName: viewModel.isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(viewModel.isFavorite ? "取消收藏节点" : "收藏节点")
            }
        }
        .task {
            await viewModel.load()
        }
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
