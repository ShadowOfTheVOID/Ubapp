import Foundation

/// Returns the Bureaucrat browser bundle from `Resources/bureaucrat_browser.html`.
/// The bundle and the SwiftUI host/guest views consume the same JSON the
/// `BureaucratServer` emits — when adding a message type, add a handler on
/// every side (server, browser bundle, `BureaucratGuestView`).
enum BureaucratBrowser {
    static var html: String { HostServer.htmlResource(named: "bureaucrat_browser") }
}
