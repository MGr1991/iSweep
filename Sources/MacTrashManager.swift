import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
import AudioToolbox
#endif

// MARK: - Trash Manager (macOS & iPadOS)

@MainActor
final class MacTrashManager: ObservableObject {
    static let shared = MacTrashManager()
    
    @Published var itemCount: Int = 0
    @Published var totalSizeBytes: Int64 = 0
    @Published var isLoading: Bool = false
    @Published var isEmptying: Bool = false
    @Published var showConfirmationDialog: Bool = false
    @Published var statusBannerMessage: String? = nil
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSizeBytes)
    }
    
    private var refreshTimer: Timer?
    
    init() {
        refreshTrashInfo()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTrashInfo()
            }
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    func refreshTrashInfo() {
        guard !isEmptying else { return }
        #if os(macOS)
        DispatchQueue.global(qos: .userInitiated).async {
            let countScript = "tell application \"Finder\" to count every item of trash"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", countScript]
            let outPipe = Pipe()
            p.standardOutput = outPipe
            try? p.run()
            p.waitUntilExit()
            
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let count = Int(str) ?? 0
            
            var sizeBytes: Int64 = 0
            if count > 0 {
                let sizeScript = """
                tell application "Finder"
                    set totalSize to 0
                    set trashItems to every item of trash
                    repeat with anItem in trashItems
                        try
                            set s to (size of anItem)
                            if s is not missing value then
                                set totalSize to totalSize + s
                            end if
                        end try
                    end repeat
                    return totalSize
                end tell
                """
                let pSize = Process()
                pSize.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                pSize.arguments = ["-e", sizeScript]
                let outSizePipe = Pipe()
                pSize.standardOutput = outSizePipe
                try? pSize.run()
                pSize.waitUntilExit()
                let sizeData = outSizePipe.fileHandleForReading.readDataToEndOfFile()
                let sizeStr = String(data: sizeData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                sizeBytes = Int64(sizeStr) ?? 0
            }
            
            DispatchQueue.main.async {
                self.itemCount = max(0, count)
                self.totalSizeBytes = max(0, sizeBytes)
            }
        }
        #else
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var count = 0
            var sizeBytes: Int64 = 0
            
            if let trashURL = try? fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
               let enumerator = fm.enumerator(at: trashURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsSubdirectoryDescendants]) {
                while let itemURL = enumerator.nextObject() as? URL {
                    count += 1
                    if let res = try? itemURL.resourceValues(forKeys: [.fileSizeKey]), let s = res.fileSize {
                        sizeBytes += Int64(s)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.itemCount = count
                self.totalSizeBytes = sizeBytes
            }
        }
        #endif
    }
    
    func openTrashInFinder() {
        #if os(macOS)
        DispatchQueue.global(qos: .userInitiated).async {
            let script = "tell application \"Finder\"\nactivate\nopen trash\nend tell"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            try? p.run()
            p.waitUntilExit()
        }
        #else
        if let url = URL(string: "shareddocuments://") {
            UIApplication.shared.open(url)
        }
        #endif
    }
    
    func promptEmptyTrash() {
        refreshTrashInfo()
        showConfirmationDialog = true
    }
    
    func emptyTrash() {
        guard !isEmptying else { return }
        isEmptying = true
        let prevCount = itemCount
        let prevSize = formattedSize
        let prevSizeBytes = totalSizeBytes
        
        #if os(macOS)
        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
            tell application "Finder"
                tell trash
                    set originalState to warns before emptying
                    set warns before emptying to false
                    empty
                    set warns before emptying to originalState
                end tell
            end tell
            """
            
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            try? p.run()
            p.waitUntilExit()
            
            Thread.sleep(forTimeInterval: 0.5)
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
            
            DispatchQueue.main.async {
                self.isEmptying = false
                self.itemCount = 0
                self.totalSizeBytes = 0
                self.refreshTrashInfo()
                if prevSizeBytes > 0 {
                    CleanStatisticsManager.shared.recordReclaimed(bytes: prevSizeBytes)
                }
                
                NSSound(named: "Trash")?.play()
                self.statusBannerMessage = prevCount > 0
                    ? "🗑️ Papierkorb erfolgreich entleert (\(prevCount) \(prevCount == 1 ? "Objekt" : "Objekte") / \(prevSize) freigegeben)"
                    : "🗑️ Papierkorb erfolgreich entleert"
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    if self.statusBannerMessage?.contains("Papierkorb") == true {
                        self.statusBannerMessage = nil
                    }
                }
            }
        }
        #else
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            if let trashURL = try? fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
               let contents = try? fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) {
                for file in contents {
                    try? fm.removeItem(at: file)
                }
            }
            
            DispatchQueue.main.async {
                self.isEmptying = false
                self.itemCount = 0
                self.totalSizeBytes = 0
                self.refreshTrashInfo()
                if prevSizeBytes > 0 {
                    CleanStatisticsManager.shared.recordReclaimed(bytes: prevSizeBytes)
                }
                
                AudioServicesPlaySystemSound(1108)
                self.statusBannerMessage = prevCount > 0
                    ? "🗑️ Papierkorb erfolgreich entleert (\(prevCount) \(prevCount == 1 ? "Objekt" : "Objekte") / \(prevSize) freigegeben)"
                    : "🗑️ Papierkorb erfolgreich entleert"
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    if self.statusBannerMessage?.contains("Papierkorb") == true {
                        self.statusBannerMessage = nil
                    }
                }
            }
        }
        #endif
    }
}

// MARK: - Trash Quick Bar Button

struct TrashQuickBarButton: View {
    @ObservedObject private var trashManager = MacTrashManager.shared
    
    var body: some View {
        TabStyleButton(
            title: trashManager.itemCount > 0 ? "Papierkorb" : "Papierkorb leeren",
            systemImage: trashManager.itemCount > 0 ? "trash.fill" : "trash",
            isSelected: false,
            isDestructive: trashManager.itemCount > 0,
            badgeCount: trashManager.itemCount > 0 ? trashManager.itemCount : nil
        ) {
            trashManager.promptEmptyTrash()
        }
        #if os(macOS)
        .help("Papierkorb entleeren (⌘⇧⌫)")
        #endif
    }
}
