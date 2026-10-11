import SwiftUI

@main
struct iSweepApp: App {
    var body: some Scene {
        WindowGroup("iSweep") {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 850, minHeight: 600)
                #endif
                .background(ThemeHelper.primaryBackground)
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            CommandMenu("Darstellung") {
                Picker("Erscheinungsbild", selection: Binding(
                    get: { ThemeManager.shared.themeMode },
                    set: { ThemeManager.shared.themeMode = $0 }
                )) {
                    Text("Systemstandard").tag(AppThemeMode.system)
                    Text("Hell").tag(AppThemeMode.light)
                    Text("Dunkel").tag(AppThemeMode.dark)
                }
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Papierkorb entleeren…") {
                    NotificationCenter.default.post(name: .promptEmptyTrash, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                
                Button("Papierkorb im Finder öffnen") {
                    NotificationCenter.default.post(name: .openTrashInFinder, object: nil)
                }
            }
            CommandGroup(replacing: .help) {
                Button("iSweep Einführung & Tutorial…") {
                    NotificationCenter.default.post(name: .showOnboardingTutorial, object: nil)
                }
            }
        }
        #endif
    }
}
