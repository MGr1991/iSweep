import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
import AudioToolbox
#endif

// MARK: - Smart Clean Models

struct SmartCleanCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let folderPath: String?
    var isSelected: Bool
    var items: [StorageItem]
    
    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}

// MARK: - Smart Cleaner ViewModel

@MainActor
final class SmartCleanerViewModel: ObservableObject {
    @Published var categories: [SmartCleanCategory] = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var hasCleaned = false
    @Published var lastCleanedBytes: Int64 = 0
    @Published var currentScanningTarget: String = ""
    @Published var expandedCategoryID: String? = nil
    
    var totalSelectableBytes: Int64 {
        categories.filter { $0.isSelected }.reduce(0) { $0 + $1.totalSize }
    }
    
    var formattedTotalSelectableBytes: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSelectableBytes)
    }
    
    var formattedLastCleanedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: lastCleanedBytes)
    }
    
    init() {
        startSmartScan()
    }
    
    func startSmartScan() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        hasCleaned = false
        categories = []
        
        Task.detached {
            #if os(macOS)
            let scanDefs: [(id: String, title: String, subtitle: String, icon: String, color: Color, path: String?)] = [
                ("caches", "Benutzer- & App-Caches", "Temporäre Daten, Web- & App-Caches", "bolt.horizontal.circle.fill", .orange, "~/Library/Caches"),
                ("xcode", "Xcode DerivedData", "Alte Build-Artefakte & Indizes", "hammer.circle.fill", .indigo, "~/Library/Developer/Xcode/DerivedData"),
                ("logs", "Diagnose- & System-Logs", "Alte Fehlerprotokolle & Berichte", "doc.text.magnifyingglass", .blue, "~/Library/Logs"),
                ("mail", "Mail Downloads", "Heruntergeladene E-Mail-Anhänge", "envelope.circle.fill", .teal, "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"),
                ("trash", "Papierkorb", "Dateien im Papierkorb", "trash.circle.fill", .red, "~/.Trash")
            ]
            #else
            let cachesPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path
            let tmpPath = NSTemporaryDirectory()
            let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
            let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
            let trashPath = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))?.path
            let scanDefs: [(id: String, title: String, subtitle: String, icon: String, color: Color, path: String?)] = [
                ("caches", "App- & Web-Caches", "Temporäre Caches & Netzwerk-Puffer", "bolt.horizontal.circle.fill", .orange, cachesPath),
                ("tmp", "Temporäre Zwischendateien", "Kurzzeitige Zwischendaten & Puffer", "clock.badge.xmark.fill", .indigo, tmpPath),
                ("docs", "Dokumente & Downloads", "Lokale Dokumente & Downloads", "arrow.down.circle.fill", .blue, docsPath),
                ("appsupport", "App Support-Daten", "Lokale App-Unterstützungsdaten", "folder.badge.gearshape", .teal, appSupportPath),
                ("trash", "Papierkorb", "Dateien im Papierkorb", "trash.circle.fill", .red, trashPath)
            ]
            #endif
            
            var scannedCategories: [SmartCleanCategory] = []
            let fm = FileManager.default
            
            for def in scanDefs {
                await MainActor.run {
                    self.currentScanningTarget = def.title
                }
                
                guard let rawPath = def.path else { continue }
                let expanded = (rawPath as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded)
                
                var items: [StorageItem] = []
                
                if fm.fileExists(atPath: expanded) {
                    if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsSubdirectoryDescendants]) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            var isDir: ObjCBool = false
                            fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                            
                            var itemSize: Int64 = 0
                            if isDir.boolValue {
                                if let subEnum = fm.enumerator(at: fileURL, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                                    while let subObj = subEnum.nextObject() as? URL {
                                        if let r = try? subObj.resourceValues(forKeys: [.fileSizeKey]), let s = r.fileSize {
                                            itemSize += Int64(s)
                                        }
                                    }
                                }
                            } else {
                                if let r = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let s = r.fileSize {
                                    itemSize = Int64(s)
                                }
                            }
                            
                            if itemSize > 0 {
                                let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                                items.append(StorageItem(url: fileURL, isDirectory: isDir.boolValue, size: itemSize, creationDate: nil, modificationDate: modDate))
                            }
                        }
                    }
                }
                
                let sortedItems = items.sorted { $0.size > $1.size }
                let category = SmartCleanCategory(
                    id: def.id,
                    title: def.title,
                    subtitle: def.subtitle,
                    icon: def.icon,
                    iconColor: def.color,
                    folderPath: def.path,
                    isSelected: !sortedItems.isEmpty,
                    items: sortedItems
                )
                scannedCategories.append(category)
            }
            
            await MainActor.run {
                self.categories = scannedCategories
                self.isScanning = false
                self.currentScanningTarget = ""
            }
        }
    }
    
    func performSmartClean() {
        guard !isCleaning, totalSelectableBytes > 0 else { return }
        isCleaning = true
        
        let selectedCats = categories.filter { $0.isSelected }
        let totalToReclaim = totalSelectableBytes
        
        Task.detached {
            for cat in selectedCats {
                if cat.id == "trash" {
                    await MainActor.run {
                        MacTrashManager.shared.emptyTrash()
                    }
                } else {
                    let urls = cat.items.map { $0.url }
                    let fm = FileManager.default
                    for u in urls {
                        _ = try? fm.removeItem(at: u)
                    }
                }
            }
            
            await MainActor.run {
                CleanStatisticsManager.shared.recordReclaimed(bytes: totalToReclaim)
                #if os(macOS)
                NSSound(named: "Trash")?.play()
                #else
                AudioServicesPlaySystemSound(1108)
                #endif
                self.lastCleanedBytes = totalToReclaim
                self.isCleaning = false
                self.hasCleaned = true
                self.startSmartScan()
            }
        }
    }
    
    func toggleCategorySelection(_ id: String) {
        if let idx = categories.firstIndex(where: { $0.id == id }) {
            categories[idx].isSelected.toggle()
        }
    }
    
    func toggleExpandCategory(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCategoryID == id {
                expandedCategoryID = nil
            } else {
                expandedCategoryID = id
            }
        }
    }
}

// MARK: - Smart Cleaner Main View

struct SmartCleanerView: View {
    @StateObject private var viewModel = SmartCleanerViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedInspectorItem: StorageItem? = nil
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $selectedInspectorItem) { item in
            StorageItemInspectorView(item: item)
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarContent: some View {
        List {
            Section {
                SidebarAppHeaderView(subtitle: "1-Klick System-Bereinigung")
                SystemStorageGaugeView()
            }
            
            Section("Aktionen") {
                Button(action: {
                    viewModel.startSmartScan()
                }) {
                    Label("Erneut scannen", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isScanning || viewModel.isCleaning)
                
                Button(action: {
                    let anyUnselected = viewModel.categories.contains { !$0.isSelected && !$0.items.isEmpty }
                    for cat in viewModel.categories {
                        if (anyUnselected && !cat.isSelected) || (!anyUnselected && cat.isSelected) {
                            viewModel.toggleCategorySelection(cat.id)
                        }
                    }
                }) {
                    let allSelected = !viewModel.categories.isEmpty && viewModel.categories.allSatisfy { $0.isSelected || $0.items.isEmpty }
                    Label(allSelected ? "Alle abwählen" : "Alle Kategorien auswählen", systemImage: allSelected ? "checkmark.circle.fill" : "checklist")
                }
            }
            
            SidebarTrashSectionView()
            
            Section("Erscheinungsbild") {
                ThemeSwitchView()
            }
        }
        .navigationTitle("Smart-Bereinigung")
        .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 400)
    }
    
    // MARK: - Detail
    
    private var detailContent: some View {
        VStack(spacing: 0) {
            if viewModel.isScanning {
                scanningStateView
            } else if viewModel.hasCleaned {
                cleanedCelebrationView
            } else {
                overviewContentView
            }
        }
        .navigationTitle("1-Klick Bereinigung")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let anyUnselected = viewModel.categories.contains { !$0.isSelected && !$0.items.isEmpty }
                    for cat in viewModel.categories {
                        if (anyUnselected && !cat.isSelected) || (!anyUnselected && cat.isSelected) {
                            viewModel.toggleCategorySelection(cat.id)
                        }
                    }
                } label: {
                    let allSelected = !viewModel.categories.isEmpty && viewModel.categories.allSatisfy { $0.isSelected || $0.items.isEmpty }
                    Label(allSelected ? "Abwählen" : "Auswählen", systemImage: allSelected ? "checkmark.circle.fill" : "checklist")
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
    
    // MARK: - States
    
    private var scanningStateView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Analysiere System-Datenmüll...")
                .font(.headline)
            if !viewModel.currentScanningTarget.isEmpty {
                Text(viewModel.currentScanningTarget)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var cleanedCelebrationView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 90, height: 90)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 54))
            }
            
            Text("Bereinigung erfolgreich!")
                .font(.title2.bold())
            
            Text("\(viewModel.formattedLastCleanedBytes) wertvoller Speicherplatz wurden freigegeben.")
                .font(.body)
                .foregroundColor(.secondary)
            
            Button("Erneut scannen") {
                viewModel.hasCleaned = false
                viewModel.startSmartScan()
            }
            .buttonStyle(.borderedProminent)
            .hoverGlowButton(cornerRadius: 8)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
    
    private var overviewContentView: some View {
        VStack(spacing: 0) {
            // Hero Header Card
            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bereit zur Bereinigung")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        Text(viewModel.formattedTotalSelectableBytes)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.performSmartClean()
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isCleaning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(viewModel.isCleaning ? "Bereinige..." : "Jetzt bereinigen")
                                .fontWeight(.bold)
                        }
                        .font(.body)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(viewModel.totalSelectableBytes > 0 ? Color.accentColor : Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.totalSelectableBytes == 0 || viewModel.isCleaning)
                    .hoverGlowButton(cornerRadius: 10, scale: 1.04)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(12)
            }
            .padding(16)
            
            // Category List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.categories) { category in
                        categoryCardView(category)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
    
    private func categoryCardView(_ category: SmartCleanCategory) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: {
                    viewModel.toggleCategorySelection(category.id)
                }) {
                    Image(systemName: category.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(category.isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(category.items.isEmpty)
                
                Image(systemName: category.icon)
                    .font(.title2)
                    .foregroundColor(category.iconColor)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.headline)
                    Text(category.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(category.formattedSize)
                    .font(.subheadline.bold())
                    .foregroundColor(category.totalSize > 0 ? .primary : .secondary)
                
                if !category.items.isEmpty {
                    Button(action: {
                        viewModel.toggleExpandCategory(category.id)
                    }) {
                        Image(systemName: viewModel.expandedCategoryID == category.id ? "chevron.up" : "chevron.down")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
            
            if viewModel.expandedCategoryID == category.id && !category.items.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    ForEach(category.items.prefix(8)) { item in
                        HStack(spacing: 10) {
                            #if os(macOS)
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                            #else
                            Image(systemName: item.isDirectory ? "folder.fill" : item.category.iconName)
                                .font(.system(size: 14))
                                .foregroundColor(item.isDirectory ? .blue : .secondary)
                                .frame(width: 16, height: 16)
                            #endif
                            Text(item.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(item.formattedSize)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                selectedInspectorItem = item
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .hoverGlowRow(cornerRadius: 6)
                    }
                    if category.items.count > 8 {
                        Text("+ \(category.items.count - 8) weitere Objekte")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    }
                }
                .background(Color.primary.opacity(0.015))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
