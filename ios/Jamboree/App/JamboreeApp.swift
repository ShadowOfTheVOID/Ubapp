import SwiftUI
import GoogleMobileAds

@main
struct JamboreeApp: App {
    init() {
        GADMobileAds.sharedInstance().start()
    }

    var body: some Scene {
        WindowGroup {
            MainMenuView()
        }
    }
}
