import SwiftUI

@main
struct JamboreeApp: App {
    // The Mobile Ads SDK is not started here. `ConsentManager` gathers UMP
    // consent and ATT first, then starts ads — see MainMenuView.onAppear.
    var body: some Scene {
        WindowGroup {
            MainMenuView()
        }
    }
}
