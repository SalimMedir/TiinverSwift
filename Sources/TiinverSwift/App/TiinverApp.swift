import SwiftUI

@main
struct TiinverApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootRouterView()
        }
    }
}
