import Foundation

/// Returns the Mafia browser bundle (HTML/CSS/JS) loaded from
/// `Resources/mafia_browser.html`. The browser bundle and the SwiftUI host
/// view consume the same JSON the [MafiaServer] emits — when adding a
/// message type, add a handler on both sides.
enum MafiaBrowser {
    static var html: String { HostServer.htmlResource(named: "mafia_browser") }
}
