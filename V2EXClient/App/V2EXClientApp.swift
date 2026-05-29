import SwiftUI

@main
struct V2EXClientApp: App {
    @StateObject private var settings = SettingsStore()
    private let service = V2EXService()

    var body: some Scene {
        WindowGroup {
            RootView(service: service)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
        }
    }
}

private struct RootView: View {
    let service: V2EXService

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(service: service)
            }
            .tabItem {
                Label("主题", systemImage: "text.bubble")
            }

            NavigationStack {
                SearchView(service: service)
            }
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
    }
}
