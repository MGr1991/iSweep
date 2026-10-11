#if os(macOS)
import Darwin
#endif
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Notifications

extension Notification.Name {
    static let toggleMultiSelectionMode = Notification.Name("iSweep.toggleMultiSelectionMode")
    static let promptEmptyTrash = Notification.Name("iSweep.promptEmptyTrash")
    static let openTrashInFinder = Notification.Name("iSweep.openTrashInFinder")
}

// MARK: - Navigation Stack Wrapper (iOS 16+ / macOS 13+)

struct NavigationStackWrapper<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            NavigationStack {
                content
            }
        } else {
            NavigationView {
                content
            }
            #if os(iOS)
            .navigationViewStyle(.stack)
            #endif
        }
    }
}

// MARK: - App Header Icon View

struct AppHeaderIconView: View {
    var size: CGFloat = 18
    
    var body: some View {
        HStack(spacing: 6) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
            
            Text("iSweep")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
}

// MARK: - Sidebar App Header View

struct SidebarAppHeaderView: View {
    var subtitle: String = "Speicher & Reste Bereiniger"
    
    var body: some View {
        HStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                .hoverGlowButton(cornerRadius: 10, scale: 1.05)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("iSweep")
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - File Path Bar View

struct FilePathBarView: View {
    @Binding var pathText: String
    var placeholder: String = "Dateipfad eingeben (z. B. ~/Library/Caches oder /Applications)..."
    var onCommitPath: (URL) -> Void
    var currentItemURL: URL? = nil
    
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    @State private var copiedFeedback: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            Image(systemName: iconName)
                .foregroundColor(.accentColor)
                .font(.system(size: 13))
            #else
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))
            #endif
            
            TextField(placeholder, text: $pathText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.vertical, 4)
                .onSubmit {
                    handleSubmit()
                }
            
            if !pathText.isEmpty {
                Button {
                    pathText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            
            // Go To / Submit button
            Button {
                handleSubmit()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Gehe zu")
                        .font(.caption2.bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .hoverGlowButton(color: .accentColor, cornerRadius: 6)
            
            // Copy Path Button
            Button {
                copyPath()
            } label: {
                Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                    .foregroundColor(copiedFeedback ? .green : .secondary)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Pfad in Zwischenablage kopieren")
            
            #if os(macOS)
            // Reveal in Finder Button
            if let activeURL = resolvedURL(from: pathText) ?? currentItemURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([activeURL])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Im Finder zeigen")
            }
            #endif
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ThemeHelper.secondaryBackground.opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Pfad nicht gefunden"),
                message: Text(errorMessage ?? "Der angegebene Pfad existiert nicht."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private var iconName: String {
        if let url = resolvedURL(from: pathText) {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if url.pathExtension == "app" { return "app.fill" }
            return isDir.boolValue ? "folder.fill" : "doc.text.fill"
        }
        return "folder.fill"
    }
    
    private func resolvedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
    
    private func handleSubmit() {
        let trimmed = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: url.path) {
            onCommitPath(url)
        } else {
            errorMessage = "Der angegebene Pfad existiert nicht: \(expanded)"
            showErrorAlert = true
        }
    }
    
    private func copyPath() {
        guard !pathText.isEmpty else { return }
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(pathText, forType: .string)
        #else
        UIPasteboard.general.string = pathText
        #endif
        withAnimation {
            copiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                copiedFeedback = false
            }
        }
    }
}

// MARK: - Tab Style Button

struct TabStyleButton: View {
    let title: String
    let systemImage: String
    var isSelected: Bool = false
    var isDestructive: Bool = false
    var badgeCount: Int? = nil
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(
                        isSelected ? .accentColor :
                        (isDestructive ? .red : (isHovered ? .primary : .secondary))
                    )
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(
                        isSelected ? .accentColor :
                        (isDestructive ? .red : .primary)
                    )
                
                if let count = badgeCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isDestructive ? Color.red.opacity(0.18) : Color.accentColor.opacity(0.18))
                        .foregroundColor(isDestructive ? .red : .accentColor)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.18)
                            : (isDestructive && (badgeCount ?? 0) > 0
                               ? Color.red.opacity(0.12)
                               : (isHovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)))
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.35)
                            : (isDestructive && (badgeCount ?? 0) > 0
                               ? Color.red.opacity(0.3)
                               : (isHovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.1))),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 4)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Selection Mode Toggle Button

struct SelectionModeToggleButton: View {
    let isSelectionMode: Bool
    let onToggle: () -> Void
    
    var body: some View {
        TabStyleButton(
            title: isSelectionMode ? "Fertig" : "Auswählen",
            systemImage: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle",
            isSelected: isSelectionMode,
            isDestructive: false,
            badgeCount: nil,
            action: onToggle
        )
        .help(isSelectionMode ? "Auswahl beenden" : "Dateien auswählen (Mehrfachauswahl)")
    }
}

// MARK: - Batch Selection Action Bar

struct BatchSelectionActionBar: View {
    let selectedCount: Int
    let totalSizeText: String
    let allSelected: Bool
    let onToggleSelectAll: () -> Void
    let onDeleteSelected: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggleSelectAll) {
                HStack(spacing: 6) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(.accentColor)
                    Text(allSelected ? "Keine auswählen" : "Alle auswählen")
                        .font(.subheadline.bold())
                }
            }
            .buttonStyle(.plain)
            .hoverGlowButton(cornerRadius: 6)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("\(selectedCount) ausgewählt")
                    .font(.subheadline.bold())
                if !totalSizeText.isEmpty {
                    Text("Gesamt: \(totalSizeText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(role: .destructive, action: onDeleteSelected) {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("Ausgewählte löschen (\(selectedCount))")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selectedCount > 0 ? Color.red : Color.gray.opacity(0.4))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
            .hoverGlowButton(color: .red, cornerRadius: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ThemeHelper.secondaryBackground.opacity(0.95))
        .overlay(Divider(), alignment: .top)
    }
}


// MARK: - Clean Statistics Manager

final class CleanStatisticsManager: ObservableObject {
    static let shared = CleanStatisticsManager()
    
    @AppStorage("reclaimedBytesTotal") var reclaimedBytesTotal: Int = 0 {
        didSet {
            objectWillChange.send()
        }
    }
    
    var formattedReclaimedTotal: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(reclaimedBytesTotal))
    }
    
    func recordReclaimed(bytes: Int64) {
        guard bytes > 0 else { return }
        DispatchQueue.main.async {
            self.reclaimedBytesTotal += Int(bytes)
        }
    }
    
    func resetCounter() {
        self.reclaimedBytesTotal = 0
    }
}

// MARK: - Memory Manager

final class SystemMemoryManager: ObservableObject {
    static let shared = SystemMemoryManager()
    
    @Published var totalRAM: UInt64 = 0
    @Published var usedRAM: UInt64 = 0
    @Published var freeRAM: UInt64 = 0
    @Published var isPurging: Bool = false
    
    var usedFraction: Double {
        guard totalRAM > 0 else { return 0 }
        return Double(usedRAM) / Double(totalRAM)
    }
    
    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: Int64(usedRAM), countStyle: .memory)
    }
    
    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalRAM), countStyle: .memory)
    }
    
    var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: Int64(freeRAM), countStyle: .memory)
    }
    
    init() {
        refreshMemory()
    }
    
    func refreshMemory() {
        #if os(macOS)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let total = ProcessInfo.processInfo.physicalMemory
            let active = UInt64(stats.active_count) * pageSize
            let wire = UInt64(stats.wire_count) * pageSize
            let compressed = UInt64(stats.compressor_page_count) * pageSize
            let used = active + wire + compressed
            let free = total > used ? total - used : 0
            
            DispatchQueue.main.async {
                self.totalRAM = total
                self.usedRAM = used
                self.freeRAM = free
            }
        }
        #endif
    }
    
    func optimizeMemory() {
        #if os(macOS)
        guard !isPurging else { return }
        isPurging = true
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/sbin/purge"), arguments: [])
            Thread.sleep(forTimeInterval: 0.8)
            DispatchQueue.main.async {
                self.refreshMemory()
                self.isPurging = false
            }
        }
        #endif
    }
}

// MARK: - System Storage & Memory Gauge View

struct SystemStorageGaugeView: View {
    @ObservedObject private var statsManager = CleanStatisticsManager.shared
    @ObservedObject private var memManager = SystemMemoryManager.shared
    @State private var totalBytes: Int64 = 0
    @State private var freeBytes: Int64 = 0
    @State private var volumeName: String = "Macintosh HD"
    @State private var selectedTab: Int = 0 // 0 = SSD, 1 = RAM
    
    private var usedBytes: Int64 {
        max(0, totalBytes - freeBytes)
    }
    
    private var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
    
    private var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
    }
    
    private var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if os(macOS)
            Picker("Anzeige", selection: $selectedTab) {
                Text("Festplatte").tag(0)
                Text("RAM").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 2)
            #endif
            
            if selectedTab == 0 {
                // SSD View
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption.bold())
                    Text(volumeName)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(usedFraction * 100))% voll")
                        .font(.caption2.bold())
                        .foregroundColor(usedFraction > 0.9 ? .red : (usedFraction > 0.75 ? .orange : .secondary))
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: usedFraction > 0.9 ? [.orange, .red] : [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(usedFraction))), height: 6)
                    }
                }
                .frame(height: 6)
                
                HStack {
                    Text("\(formattedFree) frei")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("von \(formattedTotal)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if statsManager.reclaimedBytesTotal > 0 {
                    Divider()
                        .padding(.vertical, 1)
                    
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.green)
                            .font(.caption2)
                        Text("Freigegeben:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(statsManager.formattedReclaimedTotal)
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                        Spacer()
                    }
                }
            } else {
                // RAM View (macOS)
                HStack {
                    Image(systemName: "memorychip.fill")
                        .foregroundColor(.purple)
                        .font(.caption.bold())
                    Text("Arbeitsspeicher")
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(memManager.usedFraction * 100))% belegt")
                        .font(.caption2.bold())
                        .foregroundColor(memManager.usedFraction > 0.85 ? .red : (memManager.usedFraction > 0.7 ? .orange : .secondary))
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: memManager.usedFraction > 0.85 ? [.orange, .red] : [.purple, .indigo],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(memManager.usedFraction))), height: 6)
                    }
                }
                .frame(height: 6)
                
                HStack {
                    Text("\(memManager.formattedFree) frei")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("von \(memManager.formattedTotal)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                #if os(macOS)
                Button(action: {
                    memManager.optimizeMemory()
                }) {
                    HStack(spacing: 6) {
                        if memManager.isPurging {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(memManager.isPurging ? "Optimiere RAM..." : "RAM freigeben")
                            .font(.caption2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(memManager.isPurging)
                .hoverGlowButton(color: .purple, cornerRadius: 6)
                .padding(.top, 2)
                #endif
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            refreshStorageInfo()
            memManager.refreshMemory()
        }
    }
    
    private func refreshStorageInfo() {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeNameKey]) {
            self.totalBytes = Int64(values.volumeTotalCapacity ?? 0)
            self.freeBytes = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            #if os(macOS)
            self.volumeName = values.volumeName ?? "Macintosh HD"
            #else
            self.volumeName = "iPad-Speicher"
            #endif
        }
    }
}


// MARK: - Storage Item Inspector View

struct StorageItemInspectorView: View {
    let item: StorageItem
    @Environment(\.dismiss) private var dismiss
    @State private var copiedPath = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                #if os(macOS)
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                #else
                Image(systemName: item.category.iconName)
                    .font(.system(size: 38))
                    .foregroundColor(.accentColor)
                #endif
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    
                    Text(item.formattedSize)
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
                
                Spacer()
                
                Button("Fertig") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            VStack(spacing: 12) {
                metadataRow(title: "Typ", value: item.isDirectory ? "Ordner" : item.category.rawValue)
                metadataRow(title: "Dateigröße (Exakt)", value: "\(item.size.formatted()) Bytes")
                if let mod = item.modificationDate {
                    metadataRow(title: "Zuletzt geändert", value: mod.formatted(date: .long, time: .shortened))
                }
                if let cre = item.creationDate {
                    metadataRow(title: "Erstellt am", value: cre.formatted(date: .long, time: .shortened))
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dateipfad")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text(item.url.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(3)
                            .textSelection(.enabled)
                        
                        Spacer()
                        
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.url.path, forType: .string)
                            #else
                            UIPasteboard.general.string = item.url.path
                            #endif
                            copiedPath = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedPath = false
                            }
                        } label: {
                            Image(systemName: copiedPath ? "checkmark" : "doc.on.doc")
                                .foregroundColor(copiedPath ? .green : .accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            #if os(macOS)
            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Label("Im Finder zeigen", systemImage: "magnifyingglass")
                }
                
                Button {
                    NSWorkspace.shared.open(item.url)
                } label: {
                    Label("Öffnen", systemImage: "arrow.up.right.square")
                }
            }
            .padding(.bottom)
            #endif
        }
        .frame(minWidth: 420, minHeight: 340)
    }
    
    private func metadataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }
}


// MARK: - Sidebar Trash Section View

#if os(macOS)
struct SidebarTrashSectionView: View {
    @ObservedObject private var trashManager = MacTrashManager.shared
    
    var body: some View {
        Section("Papierkorb") {
            HStack {
                Label("Papierkorb", systemImage: "trash")
                Spacer()
                Text("\(trashManager.itemCount) \(trashManager.itemCount == 1 ? "Objekt" : "Objekte") • \(trashManager.formattedSize)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            
            HStack(spacing: 8) {
                Button {
                    trashManager.openTrashInFinder()
                } label: {
                    Label("Öffnen", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Button(role: .destructive) {
                    trashManager.promptEmptyTrash()
                } label: {
                    Label("Entleeren", systemImage: "trash.slash.fill")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
}
#endif


// MARK: - Onboarding Notification

extension Notification.Name {
    static let showOnboardingTutorial = Notification.Name("showOnboardingTutorial")
}

// MARK: - Onboarding Tutorial View

struct OnboardingTutorialView: View {
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                #if os(macOS)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 5)
                #else
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                #endif
                
                Text("Willkommen bei iSweep")
                    .font(.system(size: 26, weight: .bold))
                
                Text("Deine intelligente All-in-One Suite für maximale Performance und freien Speicherplatz.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 24)
            
            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    icon: "sparkles",
                    color: .purple,
                    title: "1-Klick Smart-Bereinigung",
                    description: "Analysiert Caches, Logs, Xcode-Builds und Mail-Downloads in Sekunden."
                )
                
                featureRow(
                    icon: "doc.on.doc.fill",
                    color: .blue,
                    title: "Intelligenter Duplikate-Finder",
                    description: "Findet identische Dateien per SHA-256 Prüfsumme. Originale bleiben sicher erhalten."
                )
                
                featureRow(
                    icon: "app.badge.minus",
                    color: .orange,
                    title: "App-Deinstaller & Verwaiste Reste",
                    description: "Entfernt Programme samt aller versteckten Support-Dateien rückstandslos."
                )
                
                featureRow(
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    color: .green,
                    title: "Live SSD- & RAM-Monitor",
                    description: "Echtzeit-Auslastung in der Seitenleiste mit 1-Klick-Arbeitsspeicher-Optimierung."
                )
            }
            .padding(.horizontal, 28)
            
            Spacer()
            
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("100% Sicher: Alle Löschaktionen landen zuerst im Papierkorb.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button(action: onDismiss) {
                    Text("Jetzt loslegen")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        #if os(macOS)
        .frame(width: 520, height: 600)
        #endif
    }
    
    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
