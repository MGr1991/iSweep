import SwiftUI

struct ContentView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    #if os(macOS)
    @ObservedObject private var trashManager = MacTrashManager.shared
    #else
    @ObservedObject private var applePencilManager = ApplePencilManager.shared
    #endif

    var body: some View {
        TabView {
            #if os(macOS)
            SmartCleanerView()
                .tabItem {
                    Label("Smart-Bereinigung", systemImage: "sparkles")
                }
            
            DuplicateScannerView()
                .tabItem {
                    Label("Duplikate-Finder", systemImage: "doc.on.doc")
                }
            
            OrphanScannerView()
                .tabItem {
                    Label("Verwaiste Reste", systemImage: "sparkles.rectangle.stack")
                }
            #endif
            
            AppCleanerView()
                .tabItem {
                    Label("App-Deinstaller", systemImage: "app.badge.minus")
                }
            
            FolderScannerMainView()
                .tabItem {
                    Label("Speicher-Scanner", systemImage: "folder")
                }
        }
        .preferredColorScheme(themeManager.colorScheme)
        #if os(macOS)
        .overlay(alignment: .top) {
            if let msg = trashManager.statusBannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.subheadline.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            "Papierkorb wirklich entleeren?",
            isPresented: $trashManager.showConfirmationDialog,
            titleVisibility: .visible
        ) {
            Button("Papierkorb endgültig leeren", role: .destructive) {
                trashManager.emptyTrash()
            }
            Button("Im Finder öffnen") {
                trashManager.openTrashInFinder()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            if trashManager.itemCount > 0 {
                Text("Möchtest du alle \(trashManager.itemCount) Objekte (\(trashManager.formattedSize)) im Papierkorb unwiderruflich löschen? Diese Aktion kann nicht rückgängig gemacht werden.")
            } else {
                Text("Möchtest du alle verbleibenden Objekte im Papierkorb unwiderruflich löschen? Diese Aktion kann nicht rückgängig gemacht werden.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .promptEmptyTrash)) { _ in
            trashManager.promptEmptyTrash()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTrashInFinder)) { _ in
            trashManager.openTrashInFinder()
        }
        #else
        .background(ApplePencilInteractionBridge())
        .overlay(ApplePencilHUDBanner())
        .sheet(isPresented: $applePencilManager.showPencilCanvasSheet) {
            ApplePencilNotesSheet()
        }
        #endif
    }
}
