import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("appearance_mode") var appearanceMode: AppearanceMode = .system {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorage("font_scale") var fontScale: Double = 1.0 {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorage("enable_web_topic_view") var enableWebTopicView = false {
        willSet {
            objectWillChange.send()
        }
    }

    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
