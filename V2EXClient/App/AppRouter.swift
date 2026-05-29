import Foundation

enum AppRoute: Hashable {
    case topic(Topic)
    case node(Node)
    case member(Member)
    case web(URL)
}
