import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

@main
struct JosekiOthelloApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var attRequested = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && !attRequested {
                        attRequested = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            ATTrackingManager.requestTrackingAuthorization { _ in
                                GADMobileAds.sharedInstance().start(completionHandler: nil)
                            }
                        }
                    }
                }
        }
    }
}
