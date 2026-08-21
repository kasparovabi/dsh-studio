import SwiftUI

@main
struct PhoneApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(app)
                .onAppear { app.bootstrap() }
        }
    }
}
