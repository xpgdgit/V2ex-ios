import Foundation
import WebKit

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var isLoggedIn = false
    @Published private(set) var username: String?

    func refreshFromCookies() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        isLoggedIn = cookies.contains { $0.domain.contains("v2ex.com") && $0.name == "A2" }
    }

    func clear() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)
        isLoggedIn = false
        username = nil
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

private extension WKWebsiteDataStore {
    func dataRecords(ofTypes types: Set<String>) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { continuation in
            fetchDataRecords(ofTypes: types) { records in
                continuation.resume(returning: records)
            }
        }
    }

    func removeData(ofTypes types: Set<String>, for records: [WKWebsiteDataRecord]) async {
        await withCheckedContinuation { continuation in
            removeData(ofTypes: types, for: records) {
                continuation.resume()
            }
        }
    }
}
