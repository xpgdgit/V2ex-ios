import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var didClearCache = false
    @State private var cacheSizeText = "计算中"
    private let service = V2EXService()

    var body: some View {
        Form {
            Section("外观") {
                Picker("模式", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                VStack(alignment: .leading) {
                    Text("字体大小")
                    Slider(value: $settings.fontScale, in: 0.85...1.25, step: 0.05)
                }
            }

            Section("主题") {
                Toggle("打开网页视图", isOn: $settings.enableWebTopicView)
            }

            Section("缓存") {
                LabeledContent("缓存大小", value: cacheSizeText)

                Button(role: .destructive) {
                    Task {
                        await service.clearCache()
                        await refreshCacheSize()
                        didClearCache = true
                    }
                } label: {
                    Label("清理缓存", systemImage: "trash")
                }
            }

            Section("关于") {
                LabeledContent("版本", value: "0.1.0")
                Text("V2EX Client 是一个 SwiftUI 原生浏览客户端。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .task {
            await refreshCacheSize()
        }
        .alert("缓存已清理", isPresented: $didClearCache) {
            Button("好", role: .cancel) {}
        }
    }

    private func refreshCacheSize() async {
        let bytes = await service.cacheSizeBytes()
        let formatted = ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
        await MainActor.run {
            cacheSizeText = formatted
        }
    }
}
