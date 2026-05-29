import SwiftUI

struct UserView: View {
    @StateObject private var viewModel: UserViewModel

    init(username: String, service: V2EXService) {
        _viewModel = StateObject(wrappedValue: UserViewModel(username: username, service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingStateView(title: "正在加载用户")
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await viewModel.load(refresh: true) }
                }
            case .empty:
                ContentUnavailableView("暂无资料", systemImage: "person")
            case .loaded:
                if let member = viewModel.member {
                    VStack(spacing: 16) {
                        AvatarView(url: member.avatarURL, size: 88)
                        Text(member.username)
                            .font(.title2.weight(.semibold))
                        if let tagline = member.tagline, !tagline.isEmpty {
                            Text(tagline.strippedHTML)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(viewModel.member?.username ?? "用户")
        .task {
            await viewModel.load()
        }
    }
}
