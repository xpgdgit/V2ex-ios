import Foundation

@MainActor
final class UserViewModel: ObservableObject {
    @Published private(set) var member: Member?
    @Published private(set) var state: LoadState = .idle

    private let username: String
    private let service: V2EXService

    init(username: String, service: V2EXService) {
        self.username = username
        self.service = service
    }

    func load(refresh: Bool = false) async {
        state = .loading
        do {
            member = try await service.member(username: username, refresh: refresh)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
