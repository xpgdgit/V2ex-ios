import SwiftUI

struct TopicRow: View {
    let topic: Topic

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: topic.member.avatarURL, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title)
                    .font(.headline)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Text(topic.node.title)
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(topic.member.username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let activityText {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text(activityText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                        Text("\(topic.replies)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var activityText: String? {
        (topic.lastReplyAt ?? topic.createdAt)?.relativeText
    }
}

struct LoadingStateView: View {
    let title: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "hourglass")
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct AvatarView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct NodeIconView: View {
    let url: URL?
    let size: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Image(systemName: "number.square.fill")
                    .resizable()
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
