import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
import AudioToolbox
import UniformTypeIdentifiers
#endif
import CryptoKit

// MARK: - Duplicate Models

struct DuplicateFileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modificationDate: Date?
    var isSelected: Bool = false
    var isOriginal: Bool = false
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let name: String
    let fileSize: Int64
    var items: [DuplicateFileItem]
    
    var wastedBytes: Int64 {
        let count = items.count
        guard count > 1 else { return 0 }
        return fileSize * Int64(count - 1)
    }
    
    var formattedWastedSize: String {
        ByteCountFormatter.string(fromByteCount: wastedBytes, countStyle: .file)
    }
}

// MARK: - Duplicate Scanner ViewModel

@MainActor
final class DuplicateScannerViewModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var scanProgressMessage = ""
    @Published var selectedDirectoryURL: URL? = nil
    @Published var totalWastedBytes: Int64 = 0
    @Published var showDeleteConfirmation = false
    
    var formattedTotalWastedBytes: String {
        ByteCountFormatter.string(fromByteCount: totalWastedBytes, countStyle: .file)
    }
    
    var selectedForDeletionCount: Int {
        groups.reduce(0) { $0 + $1.items.filter { $0.isSelected }.count }
    }
    
    var selectedForDeletionBytes: Int64 {
        groups.reduce(0) { acc, group in
            let selCount = group.items.filter { $0.isSelected }.count
            return acc + (group.fileSize * Int64(selCount))
        }
    }
    
    var formattedSelectedBytes: String {
        ByteCountFormatter.string(fromByteCount: selectedForDeletionBytes, countStyle: .file)
    }
    
    init() {
        #if os(macOS)
        let dir = URL(fileURLWithPath: ("~/Downloads" as NSString).expandingTildeInPath)
        #else
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        #endif
        selectedDirectoryURL = dir
        scanDirectory(url: dir)
    }
    
    func scanDirectory(url: URL) {
        guard !isScanning else { return }
        selectedDirectoryURL = url
        isScanning = true
        groups = []
        totalWastedBytes = 0
        scanProgressMessage = "Sammle Dateien in \(url.lastPathComponent)..."
        
        Task.detached {
            let fm = FileManager.default
            var sizeToURLs: [Int64: [URL]] = [:]
            
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                    if isDir.boolValue { continue }
                    
                    if let r = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let s = r.fileSize, s > 100 * 1024 { // > 100 KB
                        let sz = Int64(s)
                        sizeToURLs[sz, default: []].append(fileURL)
                    }
                }
            }
            
            // Only keep sizes with more than 1 file
            let potentialDuplicateSizes = sizeToURLs.filter { $0.value.count > 1 }
            
            await MainActor.run {
                self.scanProgressMessage = "Vergleiche Prüfsummen von \(potentialDuplicateSizes.count) Kandidatengruppen..."
            }
            
            var confirmedGroups: [DuplicateGroup] = []
            
            for (size, urls) in potentialDuplicateSizes {
                var hashToURLs: [String: [URL]] = [:]
                
                for u in urls {
                    // Quick partial hash of first 64KB for blazing speed
                    if let fileHandle = try? FileHandle(forReadingFrom: u) {
                        let data = fileHandle.readData(ofLength: 64 * 1024)
                        fileHandle.closeFile()
                        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                        hashToURLs[hash, default: []].append(u)
                    }
                }
                
                for (_, matchingURLs) in hashToURLs where matchingURLs.count > 1 {
                    // Sort by modification date: oldest is Original
                    var items: [DuplicateFileItem] = []
                    for u in matchingURLs {
                        let modDate = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                        items.append(DuplicateFileItem(url: u, size: size, modificationDate: modDate))
                    }
                    
                    items.sort { ($0.modificationDate ?? Date.distantPast) < ($1.modificationDate ?? Date.distantPast) }
                    
                    // Mark the first (oldest) as original, others as duplicate and select them
                    if !items.isEmpty {
                        items[0].isOriginal = true
                        for i in 1..<items.count {
                            items[i].isSelected = true
                        }
                    }
                    
                    let group = DuplicateGroup(name: matchingURLs[0].lastPathComponent, fileSize: size, items: items)
                    confirmedGroups.append(group)
                }
            }
            
            let sortedGroups = confirmedGroups.sorted { $0.wastedBytes > $1.wastedBytes }
            let totalWasted = sortedGroups.reduce(0) { $0 + $1.wastedBytes }
            
            await MainActor.run {
                self.groups = sortedGroups
                self.totalWastedBytes = totalWasted
                self.isScanning = false
                self.scanProgressMessage = ""
            }
        }
    }
    
    func selectAllDuplicates(keepOriginals: Bool = true) {
        for gIdx in groups.indices {
            for iIdx in groups[gIdx].items.indices {
                if keepOriginals {
                    groups[gIdx].items[iIdx].isSelected = !groups[gIdx].items[iIdx].isOriginal
                } else {
                    groups[gIdx].items[iIdx].isSelected = true
                }
            }
        }
    }
    
    func deselectAll() {
        for gIdx in groups.indices {
            for iIdx in groups[gIdx].items.indices {
                groups[gIdx].items[iIdx].isSelected = false
            }
        }
    }
    
    func toggleItemSelection(groupID: UUID, itemID: UUID) {
        if let gIdx = groups.firstIndex(where: { $0.id == groupID }) {
            if let iIdx = groups[gIdx].items.firstIndex(where: { $0.id == itemID }) {
                groups[gIdx].items[iIdx].isSelected.toggle()
            }
        }
    }
    
    func deleteSelectedDuplicates() {
        var urlsToDelete: [URL] = []
        var totalReclaimed: Int64 = 0
        
        for group in groups {
            for item in group.items where item.isSelected {
                urlsToDelete.append(item.url)
                totalReclaimed += item.size
            }
        }
        
        guard !urlsToDelete.isEmpty else { return }
        
        #if os(macOS)
        NSWorkspace.shared.recycle(urlsToDelete) { [weak self] _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                CleanStatisticsManager.shared.recordReclaimed(bytes: totalReclaimed)
                NSSound(named: "Trash")?.play()
                
                // Remove deleted items from groups
                let deletedSet = Set(urlsToDelete)
                for gIdx in self.groups.indices {
                    self.groups[gIdx].items.removeAll { deletedSet.contains($0.url) }
                }
                self.groups.removeAll { $0.items.count <= 1 }
                self.totalWastedBytes = self.groups.reduce(0) { $0 + $1.wastedBytes }
            }
        }
        #else
        for u in urlsToDelete {
            try? FileManager.default.removeItem(at: u)
        }
        CleanStatisticsManager.shared.recordReclaimed(bytes: totalReclaimed)
        AudioServicesPlaySystemSound(1108)
        let deletedSet = Set(urlsToDelete)
        for gIdx in self.groups.indices {
            self.groups[gIdx].items.removeAll { deletedSet.contains($0.url) }
        }
        self.groups.removeAll { $0.items.count <= 1 }
        self.totalWastedBytes = self.groups.reduce(0) { $0 + $1.wastedBytes }
        #endif
    }
}

// MARK: - Duplicate Scanner View

struct DuplicateScannerView: View {
    @StateObject private var viewModel = DuplicateScannerViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showFolderPicker = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if let urls = try? result.get(), let first = urls.first {
                viewModel.scanDirectory(url: first)
            }
        }
        .confirmationDialog(
            "Ausgewählte Duplikate wirklich löschen?",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("In den Papierkorb verschieben (\(viewModel.formattedSelectedBytes))", role: .destructive) {
                viewModel.deleteSelectedDuplicates()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Es werden \(viewModel.selectedForDeletionCount) doppelte Dateien gelöscht. Originale bleiben unberührt.")
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarContent: some View {
        List {
            Section {
                SidebarAppHeaderView(subtitle: "Duplikate-Finder")
                SystemStorageGaugeView()
            }
            
            Section("Zu durchsuchende Ordner") {
                Button(action: {
                    showFolderPicker = true
                }) {
                    Label("Anderen Ordner wählen…", systemImage: "folder.badge.plus")
                }
                
                Button(action: {
                    let u = URL(fileURLWithPath: ("~/Downloads" as NSString).expandingTildeInPath)
                    viewModel.scanDirectory(url: u)
                }) {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                
                Button(action: {
                    let u = URL(fileURLWithPath: ("~/Documents" as NSString).expandingTildeInPath)
                    viewModel.scanDirectory(url: u)
                }) {
                    Label("Dokumente", systemImage: "doc")
                }
                
                Button(action: {
                    let u = URL(fileURLWithPath: ("~/Pictures" as NSString).expandingTildeInPath)
                    viewModel.scanDirectory(url: u)
                }) {
                    Label("Bilder", systemImage: "photo")
                }
            }
            
            Section("Auswahl-Aktionen") {
                Button(action: {
                    viewModel.selectAllDuplicates(keepOriginals: true)
                }) {
                    Label("Duplikate markieren (Originale behalten)", systemImage: "checkmark.circle.badge.questionmark")
                }
                
                Button(action: {
                    viewModel.deselectAll()
                }) {
                    Label("Alle abwählen", systemImage: "circle")
                }
            }
            
            SidebarTrashSectionView()
            
            Section("Erscheinungsbild") {
                ThemeSwitchView()
            }
        }
        .navigationTitle("Duplikate-Finder")
        .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 400)
    }
    
    // MARK: - Detail
    
    private var detailContent: some View {
        VStack(spacing: 0) {
            if viewModel.isScanning {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("Suche nach identischen Duplikaten...")
                        .font(.headline)
                    Text(viewModel.scanProgressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.groups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Keine doppelten Dateien gefunden")
                        .font(.title3.bold())
                    Text("In \(viewModel.selectedDirectoryURL?.lastPathComponent ?? "dem Ordner") gibt es keine Duplikate.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Anderen Ordner scannen") {
                        showFolderPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .hoverGlowButton(cornerRadius: 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Summary Top Card
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Verschwendeter Speicherplatz:")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text(viewModel.formattedTotalWastedBytes)
                                .font(.title.bold())
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.showDeleteConfirmation = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text("Löschen (\(viewModel.formattedSelectedBytes))")
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(viewModel.selectedForDeletionCount > 0 ? Color.red : Color.gray.opacity(0.4))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.selectedForDeletionCount == 0)
                        .hoverGlowButton(color: .red, cornerRadius: 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.primary.opacity(0.04))
                    
                    // Group List
                    List {
                        ForEach(viewModel.groups) { group in
                            duplicateGroupSection(group)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .navigationTitle(viewModel.selectedDirectoryURL?.lastPathComponent ?? "Duplikate")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if viewModel.selectedForDeletionCount > 0 {
                        viewModel.deselectAll()
                    } else {
                        viewModel.selectAllDuplicates(keepOriginals: true)
                    }
                } label: {
                    Label(viewModel.selectedForDeletionCount > 0 ? "Abwählen" : "Duplikate auswählen", systemImage: viewModel.selectedForDeletionCount > 0 ? "checkmark.circle.fill" : "checklist")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    MacTrashManager.shared.promptEmptyTrash()
                } label: {
                    Label("Papierkorb leeren", systemImage: "trash.slash.fill")
                }
            }
        }
    }
    
    private func duplicateGroupSection(_ group: DuplicateGroup) -> some View {
        Section {
            ForEach(group.items) { item in
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.toggleItemSelection(groupID: group.id, itemID: item.id)
                    }) {
                        Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(item.isSelected ? (item.isOriginal ? .orange : .red) : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    #if os(macOS)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    #else
                    Image(systemName: "doc.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                    #endif
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.url.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            
                            if item.isOriginal {
                                Text("Original")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            } else {
                                Text("Duplikat")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(item.url.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Text(item.formattedSize)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    #if os(macOS)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    #endif
                }
                .padding(.vertical, 4)
                .hoverGlowRow(cornerRadius: 6)
            }
        } header: {
            HStack {
                Text(group.name)
                    .font(.caption.bold())
                Spacer()
                Text("\(group.items.count) Kopien • \(group.formattedWastedSize) verschwendet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
