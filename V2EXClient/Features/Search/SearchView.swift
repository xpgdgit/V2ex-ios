import SwiftUI

struct SearchView: View {
    private let service: V2EXService
    @StateObject private var viewModel: SearchViewModel

    init(service: V2EXService) {
        self.service = service
        _viewModel = StateObject(wrappedValue: SearchViewModel(service: service))
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
                nodeList
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索节点")
        .task {
            await viewModel.load()
        }
    }

    private var nodeList: some View {
        List {
            ForEach(viewModel.results, id: \.name) { node in
                NavigationLink {
                    NodeView(nodeName: node.name, service: service)
                } label: {
                    NodeSearchRow(node: node)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.load(refresh: true)
        }
    }
}

private struct NodeSearchRow: View {
    @EnvironmentObject private var settings: SettingsStore

    let node: Node

    var body: some View {
        HStack(spacing: 12) {
            NodeIconView(url: node.iconURL, size: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(node.title)
                        .font(settings.contentFont(size: 17, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let topics = node.topics {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                            Text(topics.formatted())
                                .monospacedDigit()
                        }
                        .font(settings.contentFont(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }

                Text(node.path)
                    .font(settings.contentFont(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}
