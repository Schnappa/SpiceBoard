import SwiftUI

extension Notification.Name {
    static let triggerComposeNew = Notification.Name("triggerComposeNew")
    static let triggerReply = Notification.Name("triggerReply")
    static let triggerFollowup = Notification.Name("triggerFollowup")
    static let triggerKillThread = Notification.Name("triggerKillThread")
    static let triggerIgnorePoster = Notification.Name("triggerIgnorePoster")
    static let triggerSettings = Notification.Name("triggerSettings")
    static let triggerSync = Notification.Name("triggerSync")
    static let triggerLogs = Notification.Name("triggerLogs")
    static let triggerAbout = Notification.Name("triggerAbout") // Added to open custom retro About dialog
}

@main
struct SpiceBoardSwiftUIApp: App {
    @State private var store = UsenetStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onAppear {
                    if !store.loadState() {
                        store.loadMockData()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Über SpiceBoard...") {
                    NotificationCenter.default.post(name: .triggerAbout, object: nil)
                }
            }
            
            CommandMenu("Ablage") {
                Button("Neuer Beitrag") {
                    NotificationCenter.default.post(name: .triggerComposeNew, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Postausgang senden") {
                    NotificationCenter.default.post(name: .triggerSync, object: nil)
                }
            }
            
            CommandMenu("Bearbeiten") {
                Button("Antworten per E-Mail") {
                    NotificationCenter.default.post(name: .triggerReply, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Button("Followup im Forum") {
                    NotificationCenter.default.post(name: .triggerFollowup, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("Thema Ignorieren / Kill") {
                    NotificationCenter.default.post(name: .triggerKillThread, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Button("Autor Ignorieren") {
                    NotificationCenter.default.post(name: .triggerIgnorePoster, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
            
            CommandMenu("Spezial") {
                Button(store.isOffline ? "Online gehen (Modem an)" : "Offline gehen (Modem aus)") {
                    store.isOffline.toggle()
                }
                .keyboardShortcut("d", modifiers: .command)
                
                Divider()
                
                Button("Verbindungsprotokoll...") {
                    NotificationCenter.default.post(name: .triggerLogs, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
                
                Button("Einstellungen...") {
                    NotificationCenter.default.post(name: .triggerSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
