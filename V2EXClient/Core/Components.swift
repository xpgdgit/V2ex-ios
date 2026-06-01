import SwiftUI
import UIKit
import ImageIO

struct TopicRow: View {
    @EnvironmentObject private var settings: SettingsStore

    let topic: Topic

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: topic.member.avatarURL, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title)
                    .font(settings.contentFont(size: 17, weight: .semibold))
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Text(topic.node.title)
                        .font(settings.contentFont(size: 12))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(topic.member.username)
                        .font(settings.contentFont(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let activityText {
                        Text("·")
                            .font(settings.contentFont(size: 12))
                            .foregroundStyle(.tertiary)

                        Text(activityText)
                            .font(settings.contentFont(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                        Text("\(topic.replies)")
                            .monospacedDigit()
                    }
                    .font(settings.contentFont(size: 12))
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
        CachedRemoteImage(url: url) { image in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
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
        CachedRemoteImage(url: url) { image in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image(systemName: "number.square.fill")
                .resizable()
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (UIImage) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader = RemoteImageLoader()

    var body: some View {
        Group {
            if let url, let cachedImage = RemoteImageCache.shared.image(for: url) {
                content(cachedImage)
            } else if loader.imageURL == url, let image = loader.image {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loader.load(url: url)
        }
    }
}

@MainActor
private final class RemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var imageURL: URL?

    private var currentURL: URL?

    func load(url: URL?) async {
        guard currentURL != url else {
            return
        }

        currentURL = url
        guard let url else {
            image = nil
            imageURL = nil
            return
        }

        if let cached = RemoteImageCache.shared.image(for: url) {
            image = cached
            imageURL = url
            return
        }

        image = nil
        imageURL = nil
        guard let loaded = await RemoteImageCache.shared.loadImage(for: url) else {
            return
        }

        guard currentURL == url else {
            return
        }
        image = loaded
        imageURL = url
    }
}

@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let directory: URL
    private var inFlightTasks: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 600
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "V2EXClient", directoryHint: .isDirectory)
        directory = base.appending(path: "ImageCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.excludeFromBackup(directory)
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func preload(_ urls: [URL]) {
        for url in urls where image(for: url) == nil {
            Task {
                _ = await loadImage(for: url)
            }
        }
    }

    func clear() {
        cache.removeAllObjects()
        inFlightTasks.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.excludeFromBackup(directory)
    }

    func diskUsage() -> Int64 {
        Self.diskUsage(of: directory)
    }

    func loadImage(for url: URL) async -> UIImage? {
        if let cached = image(for: url) {
            return cached
        }

        if let task = inFlightTasks[url] {
            return await task.value
        }

        let fileURL = fileURL(for: url)
        let task = Task<UIImage?, Never>.detached(priority: .utility) {
            if let data = try? Data(contentsOf: fileURL),
               let image = UIImage.decodedImage(from: data) {
                return image
            }

            do {
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                request.timeoutInterval = 20
                request.setValue("V2EXClient/0.1 iOS", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode,
                      let image = UIImage.decodedImage(from: data) else {
                    return nil
                }
                try? data.write(to: fileURL, options: .atomic)
                return image
            } catch {
                return nil
            }
        }

        inFlightTasks[url] = task
        let loaded = await task.value
        inFlightTasks[url] = nil

        if let loaded {
            cache.setObject(loaded, forKey: url as NSURL)
        }
        return loaded
    }

    private func fileURL(for url: URL) -> URL {
        let key = String.md5HexDigest(for: url.absoluteString)
        return directory.appending(path: "\(key).img")
    }

    private static func excludeFromBackup(_ url: URL) {
        var cacheURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? cacheURL.setResourceValues(values)
    }

    private static func diskUsage(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]),
                  values.isRegularFile == true else {
                continue
            }

            let bytes = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
            total += Int64(bytes)
        }

        return total
    }
}

private extension UIImage {
    static func decodedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400
        ]

        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        }

        return UIImage(data: data)
    }
}
