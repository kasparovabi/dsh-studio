import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ZStack {
            MetalBackground(activity: app.running ? 1.0 : 0.5, dark: app.appearance == .dark)
                .ignoresSafeArea()
            HStack(spacing: 14) {
                SidebarView()
                    .frame(width: 264)
                MainView()
            }
            .padding(14)
        }
        .preferredColorScheme(app.appearance.colorScheme)
        .onAppear { app.bootstrap() }
    }
}
