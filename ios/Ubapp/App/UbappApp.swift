import SwiftUI
import GoogleMobileAds

@main
struct UbappApp: App {
    init() {
        GADMobileAds.sharedInstance().start()
    }

    var body: some Scene {
        WindowGroup {
            MainMenuView()
        }
    }
}
