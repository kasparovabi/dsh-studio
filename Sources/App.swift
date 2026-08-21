import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared?.shutdownIfSpawned()
        }
    }
}

@main
struct DshStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup("DSH Studio") {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 1180, minHeight: 740)
        }
        .windowStyle(.hiddenTitleBar)
        // Cmd V is a menu key equivalent, so it never reaches a handler inside
        // a view. Own the item, take images for the composer, and hand anything
        // else back to whatever holds focus.
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                    .keyboardShortcut("x")
                Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                    .keyboardShortcut("c")
                Button("Paste") {
                    let attached = MainActor.assumeIsolated {
                        AppModel.shared?.pasteImageFromClipboard() ?? false
                    }
                    if !attached {
                        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("v")
                Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                    .keyboardShortcut("a")
            }
        }
    }
}
