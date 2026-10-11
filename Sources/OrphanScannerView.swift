#if os(macOS)
import SwiftUI
import AppKit
import LocalAuthentication

struct DeletedAppRecord: Identifiable, Codable, Equatable {
    var id: String { bundleIdentifier }
    var name: String
    var bundleIdentifier: String
    var deletionDate: Date
    var iconData: Data?
}

final class DeletedAppTracker: ObservableObject {
    static let shared = DeletedAppTracker()
    private let key = "com.isweep.deleted_apps_history"
    
    @Published var records: [DeletedAppRecord] = []
    
    init() {
        load()
        bootstrapDefaultKnownDeletedApps()
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([DeletedAppRecord].self, from: data) {
            self.records = decoded
        }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    func recordDeletedApp(name: String, bundleIdentifier: String, iconData: Data?) {
        let cleanName = name.replacingOccurrences(of: ".app", with: "")
        if let idx = records.firstIndex(where: { $0.bundleIdentifier.lowercased() == bundleIdentifier.lowercased() || $0.name.lowercased() == cleanName.lowercased() }) {
            records[idx] = DeletedAppRecord(name: cleanName, bundleIdentifier: bundleIdentifier, deletionDate: Date(), iconData: iconData ?? records[idx].iconData)
        } else {
            records.append(DeletedAppRecord(name: cleanName, bundleIdentifier: bundleIdentifier, deletionDate: Date(), iconData: iconData))
        }
        save()
    }
    
    func removeRecord(bundleIdentifier: String) {
        records.removeAll { $0.bundleIdentifier == bundleIdentifier }
        save()
    }
    
    private func bootstrapDefaultKnownDeletedApps() {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        let waContainer = "\(home)/Library/Containers/net.whatsapp.WhatsApp"
        let waGroup = "\(home)/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"
        if fm.fileExists(atPath: waContainer) || fm.fileExists(atPath: waGroup) {
            if !records.contains(where: { $0.bundleIdentifier == "net.whatsapp.WhatsApp" || $0.name.lowercased() == "whatsapp" }) {
                recordDeletedApp(name: "WhatsApp", bundleIdentifier: "net.whatsapp.WhatsApp", iconData: nil)
            }
        }
    }
}

struct DeletedAppLeftoverGroup: Identifiable {
    var id: String { record.id }
    let record: DeletedAppRecord
    var items: [StorageItem]
    
    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }
    
    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}

@MainActor
final class OrphanScannerViewModel: ObservableObject {
    @Published var groups: [DeletedAppLeftoverGroup] = []
    @Published var isScanning: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var adminFallbackAction: (() -> Void)?
    
    @Published var finderViewMode: FinderViewMode = FinderViewMode.shared {
        didSet {
            if finderViewMode != FinderViewMode.shared {
                FinderViewMode.shared = finderViewMode
            }
        }
    }
    
    init() {
        NotificationCenter.default.addObserver(forName: FinderViewMode.didChangeNotification, object: nil, queue: .main) { [weak self] notif in
            if let mode = notif.object as? FinderViewMode, self?.finderViewMode != mode {
                self?.finderViewMode = mode
            }
        }
    }
    @Published var sortOption: SortOption = .size
    @Published var sortAscending: Bool = false
    
    func setSort(_ option: SortOption) {
        if sortOption == option {
            sortAscending.toggle()
        } else {
            sortOption = option
            sortAscending = (option == .name || option == .category)
        }
    }
    
    var sortedGroups: [DeletedAppLeftoverGroup] {
        groups.map { group in
            var g = group
            g.items = group.items.sorted(by: sortOption, ascending: sortAscending)
            return g
        }.sorted { g1, g2 in
            switch sortOption {
            case .name:
                let cmp = g1.record.name.localizedStandardCompare(g2.record.name)
                return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            case .size:
                return sortAscending ? (g1.totalSize < g2.totalSize) : (g1.totalSize > g2.totalSize)
            case .date:
                let d1 = g1.record.deletionDate
                let d2 = g2.record.deletionDate
                return sortAscending ? (d1 < d2) : (d1 > d2)
            case .category:
                return sortAscending ? (g1.totalSize < g2.totalSize) : (g1.totalSize > g2.totalSize)
            }
        }
    }
    
    func scanRememberedDeletedApps() {
        self.isScanning = true
        self.groups = []
        
        Task.detached {
            let tracker = DeletedAppTracker.shared
            let records = tracker.records
            var detectedGroups: [DeletedAppLeftoverGroup] = []
            
            for record in records {
                let leftovers = Self.scanLeftoversOnDisk(for: record)
                if !leftovers.isEmpty {
                    detectedGroups.append(DeletedAppLeftoverGroup(record: record, items: leftovers))
                }
            }
            
            await MainActor.run {
                self.groups = detectedGroups
                self.isScanning = false
            }
        }
    }
    
    private nonisolated static func scanLeftoversOnDisk(for record: DeletedAppRecord) -> [StorageItem] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        let bundleID = record.bundleIdentifier.lowercased()
        let name = record.name.lowercased()
        
        var foundPaths: Set<String> = []
        
        // 1. Containers
        let containersURL = URL(fileURLWithPath: "\(home)/Library/Containers")
        if let list = try? fm.contentsOfDirectory(atPath: containersURL.path) {
            for entry in list {
                let lower = entry.lowercased()
                if lower == name || lower == bundleID || lower.hasPrefix(bundleID) || lower.contains(name) {
                    foundPaths.insert("\(containersURL.path)/\(entry)")
                }
            }
        }
        
        // 2. Group Containers
        let groupContainersURL = URL(fileURLWithPath: "\(home)/Library/Group Containers")
        if let list = try? fm.contentsOfDirectory(atPath: groupContainersURL.path) {
            for entry in list {
                let lower = entry.lowercased()
                if lower.contains(name) || lower.contains(bundleID) {
                    foundPaths.insert("\(groupContainersURL.path)/\(entry)")
                }
            }
        }
        
        // 3. Application Support
        let appSupportURL = URL(fileURLWithPath: "\(home)/Library/Application Support")
        if let list = try? fm.contentsOfDirectory(atPath: appSupportURL.path) {
            for entry in list {
                let lower = entry.lowercased()
                if lower == name || lower == bundleID || lower.hasPrefix(bundleID) {
                    foundPaths.insert("\(appSupportURL.path)/\(entry)")
                }
            }
        }
        
        // 4. Caches
        let cachesURL = URL(fileURLWithPath: "\(home)/Library/Caches")
        if let list = try? fm.contentsOfDirectory(atPath: cachesURL.path) {
            for entry in list {
                let lower = entry.lowercased()
                if lower == name || lower == bundleID || lower.hasPrefix(bundleID) {
                    foundPaths.insert("\(cachesURL.path)/\(entry)")
                }
            }
        }
        
        // 5. Preferences
        let prefPath = "\(home)/Library/Preferences/\(record.bundleIdentifier).plist"
        if fm.fileExists(atPath: prefPath) {
            foundPaths.insert(prefPath)
        }
        
        // 6. Application Scripts
        let scriptsURL = URL(fileURLWithPath: "\(home)/Library/Application Scripts")
        if let list = try? fm.contentsOfDirectory(atPath: scriptsURL.path) {
            for entry in list {
                let lower = entry.lowercased()
                if lower.contains(name) || lower.contains(bundleID) {
                    foundPaths.insert("\(scriptsURL.path)/\(entry)")
                }
            }
        }
        
        var storageItems: [StorageItem] = []
        for path in foundPaths {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir) {
                var size: Int64 = 0
                if isDir.boolValue {
                    if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                        while let obj = enumerator.nextObject(), let fURL = obj as? URL {
                            if let res = try? fURL.resourceValues(forKeys: [.fileSizeKey]), let s = res.fileSize {
                                size += Int64(s)
                            }
                        }
                    }
                } else {
                    if let res = try? url.resourceValues(forKeys: [.fileSizeKey]), let s = res.fileSize {
                        size = Int64(s)
                    }
                }
                let attrs = try? fm.attributesOfItem(atPath: path)
                let cDate = attrs?[.creationDate] as? Date
                let mDate = attrs?[.modificationDate] as? Date
                storageItems.append(StorageItem(url: url, isDirectory: isDir.boolValue, size: size, creationDate: cDate, modificationDate: mDate))
            }
        }
        
        return storageItems.sorted { $0.size > $1.size }
    }
    
    func deleteItem(_ item: StorageItem, from group: DeletedAppLeftoverGroup) {
        robustDelete(url: item.url) { [weak self] error in
            guard let self = self else { return }
            if error == nil {
                CleanStatisticsManager.shared.recordReclaimed(bytes: item.size)
                if let gIdx = self.groups.firstIndex(where: { $0.id == group.id }) {
                    self.groups[gIdx].items.removeAll { $0.id == item.id }
                    if self.groups[gIdx].items.isEmpty {
                        self.groups.remove(at: gIdx)
                    }
                }
            }
        }
    }
    
    func deleteAllLeftovers(for group: DeletedAppLeftoverGroup) {
        var urlsToDelete = group.items.map { $0.url }
        
        #if os(macOS)
        let fm = FileManager.default
        let possibleAppLocations = [
            "/Applications/\(group.record.name).app",
            "/Applications/\(group.record.name)",
            NSString(string: "~/Applications/\(group.record.name).app").expandingTildeInPath,
            NSString(string: "~/Applications/\(group.record.name)").expandingTildeInPath
        ]
        for path in possibleAppLocations {
            if fm.fileExists(atPath: path) {
                let appURL = URL(fileURLWithPath: path)
                if !urlsToDelete.contains(appURL) {
                    urlsToDelete.append(appURL)
                }
            }
        }
        
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: group.record.bundleIdentifier) {
            if !urlsToDelete.contains(appURL) {
                urlsToDelete.append(appURL)
            }
        }
        
        NSWorkspace.shared.recycle(urlsToDelete) { _, error in
            DispatchQueue.main.async {
                if let _ = error {
                    for url in urlsToDelete {
                        self.robustDelete(url: url) { _ in }
                    }
                }
                self.forgetApp(group.record)
                _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
            }
        }
        #else
        for item in group.items {
            deleteItem(item, from: group)
        }
        self.forgetApp(group.record)
        #endif
    }
    
    func deleteItems(urls: Set<URL>) {
        var itemsToDelete: [StorageItem] = []
        for g in self.groups {
            for it in g.items {
                if urls.contains(it.url) {
                    itemsToDelete.append(it)
                }
            }
        }
        guard !itemsToDelete.isEmpty else { return }
        
        #if os(macOS)
        let urlList = itemsToDelete.map { $0.url }
        NSWorkspace.shared.recycle(urlList) { _, error in
            DispatchQueue.main.async {
                if let _ = error {
                    for g in self.groups {
                        for it in g.items where urls.contains(it.url) {
                            self.deleteItem(it, from: g)
                        }
                    }
                } else {
                    let ids = Set(itemsToDelete.map { $0.id })
                    let totalReclaimed = itemsToDelete.reduce(Int64(0)) { $0 + $1.size }
                    CleanStatisticsManager.shared.recordReclaimed(bytes: totalReclaimed)
                    for idx in self.groups.indices {
                        self.groups[idx].items.removeAll { ids.contains($0.id) }
                    }
                    for g in self.groups where g.items.isEmpty {
                        DeletedAppTracker.shared.removeRecord(bundleIdentifier: g.record.bundleIdentifier)
                    }
                    self.groups.removeAll { $0.items.isEmpty }
                    _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
                }
            }
        }
        #endif
    }
    
    func forgetApp(_ record: DeletedAppRecord) {
        DeletedAppTracker.shared.removeRecord(bundleIdentifier: record.bundleIdentifier)
        groups.removeAll { $0.record.id == record.id }
    }
    
    private func robustDelete(url: URL, completion: @escaping (Error?) -> Void) {
        let context = LAContext()
        var authError: NSError?
        let reason = "iSweep benötigt Berechtigung, um die Restdatei sicher zu löschen."
        
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evaluateError in
                DispatchQueue.main.async {
                    if success {
                        self.performActualDelete(url: url, completion: completion)
                    } else {
                        completion(evaluateError ?? NSError(domain: "iSweep", code: 2, userInfo: nil))
                    }
                }
            }
        } else {
            performActualDelete(url: url, completion: completion)
        }
    }
    
    private func performActualDelete(url: URL, completion: @escaping (Error?) -> Void) {
        do {
            var outURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &outURL)
            DispatchQueue.main.async {
                _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
                completion(nil)
            }
            return
        } catch {}
        
        NSWorkspace.shared.recycle([url]) { _, error in
            if let err = error as NSError? {
                DispatchQueue.main.async {
                    self.errorMessage = "Das native Mac-Löschen wurde wg. fehlender Rechte blockiert.\n\nMöchtest du es stattdessen als Admin per Passwort entfernen?"
                    self.adminFallbackAction = {
                        let adminScript = "do shell script \"rm -rf \" & quoted form of \"\(url.path)\" with administrator privileges"
                        if let script = NSAppleScript(source: adminScript) {
                            DispatchQueue.global().async {
                                var errorInfo: NSDictionary? = nil
                                script.executeAndReturnError(&errorInfo)
                                DispatchQueue.main.async {
                                    if let info = errorInfo, let msg = info[NSAppleScript.errorMessage] as? String {
                                        self.errorMessage = "Löschen gescheitert: \(msg)"
                                        self.adminFallbackAction = nil
                                        self.showError = true
                                        completion(NSError(domain: "iSweep", code: 3, userInfo: nil))
                                    } else {
                                        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
                                        completion(nil)
                                    }
                                }
                            }
                        } else {
                            completion(err)
                        }
                    }
                    self.showError = true
                }
            } else {
                DispatchQueue.main.async {
                    _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
                    completion(nil)
                }
            }
        }
    }
}

#if os(macOS)
struct OrphanColumnBrowserView: View {
    @ObservedObject var viewModel: OrphanScannerViewModel
    @Binding var selectedPath: String
    var isSelectionMode: Bool = false
    var selectedURLs: Set<URL> = []
    var onToggleSelect: ((StorageItem) -> Void)? = nil
    @State private var selectedGroupID: String? = nil
    
    var body: some View {
        let groups = viewModel.sortedGroups
        let activeGroup = groups.first { $0.id == (selectedGroupID ?? groups.first?.id) }
        
        HStack(spacing: 0) {
            // Column 0: List of deleted apps
            VStack(spacing: 0) {
                HStack {
                    Text("Gelöschte Apps (\(groups.count))")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(ThemeHelper.secondaryBackground.opacity(0.3))
                
                Divider()
                
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(groups) { group in
                            let isSelected = activeGroup?.id == group.id
                            HStack(spacing: 6) {
                                Button {
                                    selectedGroupID = group.id
                                    if let first = group.items.first {
                                        selectedPath = first.url.path
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        if let iconData = group.record.iconData, let img = NSImage(data: iconData) {
                                            Image(nsImage: img)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 22, height: 22)
                                        } else {
                                            Image(nsImage: NSWorkspace.shared.icon(forFileType: "app"))
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 22, height: 22)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(group.record.name)
                                                .font(.subheadline)
                                                .foregroundColor(isSelected ? .white : .primary)
                                                .lineLimit(1)
                                            Text("\(group.items.count) Reste • \(group.formattedTotalSize)")
                                                .font(.caption2)
                                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                Button(role: .destructive) {
                                    viewModel.deleteAllLeftovers(for: group)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .hoverGlowTrash()
                                }
                                .buttonStyle(.plain)
                                .help("App und alle zugehörigen Reste löschen")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                            )
                            .hoverGlowRow(cornerRadius: 6)
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.deleteAllLeftovers(for: group)
                                } label: {
                                    Label("App & alle Reste löschen", systemImage: "trash")
                                }
                                Button {
                                    viewModel.forgetApp(group.record)
                                } label: {
                                    Label("Aus Liste entfernen", systemImage: "xmark.circle")
                                }
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .frame(width: 270)
            
            Divider()
            
            // Subsequent columns for the selected app leftovers
            if let group = activeGroup {
                FinderColumnBrowserView(
                    rootItems: group.items,
                    sortOption: viewModel.sortOption,
                    sortAscending: viewModel.sortAscending,
                    onDelete: { item in
                        viewModel.deleteItem(item, from: group)
                    },
                    onItemSelected: { item in
                        selectedPath = item.url.path
                    },
                    isSelectionMode: isSelectionMode,
                    selectedURLs: selectedURLs,
                    onToggleSelect: { item in
                        onToggleSelect?(item)
                    },
                    onSelectRange: { item, columnItems in
                        onToggleSelect?(item)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif

struct OrphanScannerView: View {
    @StateObject private var viewModel = OrphanScannerViewModel()
    @State private var pathBarText: String = "~/Library/Containers"
    @State private var isSelectionMode: Bool = false
    @State private var selectedURLs: Set<URL> = []
    @State private var lastSelectedURL: URL? = nil
    @State private var showBatchDeleteAlert: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    private func toggleSelection(for url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
        lastSelectedURL = url
    }
    
    private var allOrphanURLs: [URL] {
        viewModel.sortedGroups.flatMap { $0.items.map { $0.url } }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section {
                    SidebarAppHeaderView(subtitle: "Verwaiste Reste")
                    SystemStorageGaugeView()
                }
                
                Section("Aktionen") {
                    Button(action: {
                        viewModel.scanRememberedDeletedApps()
                    }) {
                        Label("Reste prüfen", systemImage: "arrow.clockwise")
                    }
                    
                    #if os(macOS)
                    Button(action: {
                        pathBarText = "~/Library/Containers"
                    }) {
                        Label("Containers prüfen", systemImage: "shippingbox")
                    }
                    Button(action: {
                        pathBarText = "~/Library/Caches"
                    }) {
                        Label("Caches prüfen", systemImage: "trash")
                    }
                    Button(action: {
                        pathBarText = "~/Library/Application Support"
                    }) {
                        Label("App Support prüfen", systemImage: "folder")
                    }
                    #endif
                    
                    Button(action: {
                        withAnimation {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedURLs.removeAll()
                            }
                        }
                    }) {
                        Label(isSelectionMode ? "Auswahl beenden" : "Reste auswählen", systemImage: isSelectionMode ? "checkmark.circle.fill" : "checklist")
                    }
                }
                
                #if os(macOS)
                SidebarTrashSectionView()
                #endif
                
                Section("Übersicht") {
                    Text("\(viewModel.sortedGroups.count) gelöschte Apps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    let totalLeftovers = viewModel.sortedGroups.reduce(0) { $0 + $1.items.count }
                    Text("\(totalLeftovers) verwaiste Reste")
                        .font(.caption)
                        .foregroundColor(totalLeftovers > 0 ? .orange : .secondary)
                }
                
                Section("Erscheinungsbild") {
                    ThemeSwitchView()
                }
            }
            .navigationTitle("Verwaiste Reste")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    AppHeaderIconView()
                }
            }
            .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 400)
        } detail: {
            detailBody
                .toolbar {
                    #if os(macOS)
                    ToolbarItem(placement: .primaryAction) {
                        TrashQuickBarButton()
                    }
                    #endif
                    
                    ToolbarItem(placement: .primaryAction) {
                        SelectionModeToggleButton(isSelectionMode: isSelectionMode) {
                            withAnimation {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedURLs.removeAll()
                                }
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Picker("Darstellung", selection: $viewModel.finderViewMode) {
                            Image(systemName: FinderViewMode.list.systemImage)
                                .tag(FinderViewMode.list)
                            Image(systemName: FinderViewMode.icons.systemImage)
                                .tag(FinderViewMode.icons)
                            Image(systemName: FinderViewMode.columns.systemImage)
                                .tag(FinderViewMode.columns)
                            Image(systemName: FinderViewMode.gallery.systemImage)
                                .tag(FinderViewMode.gallery)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Section("Sortieren nach") {
                                Button {
                                    viewModel.setSort(.name)
                                } label: {
                                    HStack {
                                        Text("Name")
                                        if viewModel.sortOption == .name { Image(systemName: "checkmark") }
                                    }
                                }
                                Button {
                                    viewModel.setSort(.size)
                                } label: {
                                    HStack {
                                        Text("Größe")
                                        if viewModel.sortOption == .size { Image(systemName: "checkmark") }
                                    }
                                }
                                Button {
                                    viewModel.setSort(.date)
                                } label: {
                                    HStack {
                                        Text("Änderungsdatum")
                                        if viewModel.sortOption == .date { Image(systemName: "checkmark") }
                                    }
                                }
                                Button {
                                    viewModel.setSort(.category)
                                } label: {
                                    HStack {
                                        Text("Kategorie / Art")
                                        if viewModel.sortOption == .category { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Reihenfolge") {
                                Button {
                                    viewModel.sortAscending = true
                                } label: {
                                    HStack {
                                        Text(viewModel.sortOption == .size ? "Kleinste zuerst" : (viewModel.sortOption == .date ? "Älteste zuerst" : "Aufsteigend (A-Z)"))
                                        if viewModel.sortAscending { Image(systemName: "checkmark") }
                                    }
                                }
                                Button {
                                    viewModel.sortAscending = false
                                } label: {
                                    HStack {
                                        Text(viewModel.sortOption == .size ? "Größte zuerst" : (viewModel.sortOption == .date ? "Neueste zuerst" : "Absteigend (Z-A)"))
                                        if !viewModel.sortAscending { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            Label("Sortieren", systemImage: "arrow.up.arrow.down")
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.scanRememberedDeletedApps()
                        } label: {
                            Label("Aktualisieren", systemImage: "arrow.clockwise")
                        }
                    }
                }
        }
        .alert(isPresented: $viewModel.showError) {
            if let action = viewModel.adminFallbackAction {
                return Alert(
                    title: Text("macOS Berechtigung"),
                    message: Text(viewModel.errorMessage ?? ""),
                    primaryButton: .destructive(Text("Per Passwort löschen"), action: {
                        action()
                        viewModel.adminFallbackAction = nil
                    }),
                    secondaryButton: .cancel(Text("Abbrechen"))
                )
            } else {
                return Alert(title: Text("Hinweis"), message: Text(viewModel.errorMessage ?? ""), dismissButton: .default(Text("OK")))
            }
        }
        .confirmationDialog(
            "Möchtest du \(selectedURLs.count) verwaiste Reste wirklich löschen?",
            isPresented: $showBatchDeleteAlert,
            titleVisibility: .visible
        ) {
            Button("Ausgewählte löschen (\(selectedURLs.count))", role: .destructive) {
                viewModel.deleteItems(urls: selectedURLs)
                selectedURLs.removeAll()
                isSelectionMode = false
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            let selectedItems = viewModel.sortedGroups.flatMap { $0.items }.filter { selectedURLs.contains($0.url) }
            let totalBytes = selectedItems.reduce(Int64(0)) { $0 + $1.size }
            let formatter = ByteCountFormatter()
            let sizeStr = formatter.string(fromByteCount: totalBytes)
            Text("Gesamtgröße: \(sizeStr). Die \(selectedURLs.count) verwaisten Dateien werden in den Papierkorb verschoben.")
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            columnVisibility = .all
            viewModel.scanRememberedDeletedApps()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMultiSelectionMode)) { _ in
            withAnimation {
                isSelectionMode.toggle()
                if !isSelectionMode {
                    selectedURLs.removeAll()
                }
            }
        }
    }
    
    @ViewBuilder
    private var detailBody: some View {
        VStack(spacing: 0) {
            FilePathBarView(
                pathText: $pathBarText,
                placeholder: "Pfad eingeben oder prüfen (z. B. ~/Library/Containers oder ~/Library/Caches)...",
                onCommitPath: { url in
                    #if os(macOS)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    #endif
                },
                currentItemURL: URL(fileURLWithPath: NSString(string: pathBarText).expandingTildeInPath)
            )
            if viewModel.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Suche Reste gemerkter Apps...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.groups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 54))
                        .foregroundColor(.green)
                    Text("Keine verwaisten Reste vorhanden")
                        .font(.title2.bold())
                    Text("Es liegen keine Rest-Dateien von gemerkten, gelöschten Apps auf deinem Mac.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button("Erneut prüfen") {
                        viewModel.scanRememberedDeletedApps()
                    }
                    .buttonStyle(.bordered)
                    .hoverGlowButton()
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(viewModel.sortedGroups.count) gelöschte Apps • \(viewModel.sortedGroups.reduce(0) { $0 + $1.items.count }) Reste")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Sortiert: \(viewModel.sortOption.rawValue) (\(viewModel.sortAscending ? "▲" : "▼"))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    
                    #if os(macOS)
                    if viewModel.finderViewMode == .columns {
                        OrphanColumnBrowserView(
                            viewModel: viewModel,
                            selectedPath: $pathBarText,
                            isSelectionMode: isSelectionMode,
                            selectedURLs: selectedURLs,
                            onToggleSelect: { item in
                                let allItems = viewModel.sortedGroups.flatMap { $0.items }
                                performMultiSelectClick(
                                    item: item,
                                    in: allItems,
                                    selectedURLs: &selectedURLs,
                                    lastSelectedURL: &lastSelectedURL,
                                    isSelectionMode: &isSelectionMode
                                )
                            }
                        )
                    } else {
                        orphanCardListView
                    }
                    #else
                    orphanCardListView
                    #endif
                }
            }
            
            if isSelectionMode {
                let allURLs = allOrphanURLs
                let selectedItems = viewModel.sortedGroups.flatMap { $0.items }.filter { selectedURLs.contains($0.url) }
                let totalBytes = selectedItems.reduce(Int64(0)) { $0 + $1.size }
                let formatter = ByteCountFormatter()
                let sizeStr = formatter.string(fromByteCount: totalBytes)
                
                BatchSelectionActionBar(
                    selectedCount: selectedURLs.count,
                    totalSizeText: sizeStr,
                    allSelected: !allURLs.isEmpty && selectedURLs.count == allURLs.count,
                    onToggleSelectAll: {
                        if selectedURLs.count == allURLs.count {
                            selectedURLs.removeAll()
                        } else {
                            selectedURLs = Set(allURLs)
                        }
                    },
                    onDeleteSelected: {
                        showBatchDeleteAlert = true
                    },
                    onCancel: {
                        withAnimation {
                            isSelectionMode = false
                            selectedURLs.removeAll()
                        }
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private var orphanCardListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.sortedGroups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            #if os(macOS)
                            if let iconData = group.record.iconData, let img = NSImage(data: iconData) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            } else {
                                Image(nsImage: NSWorkspace.shared.icon(forFileType: "app"))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                            #else
                            Image(systemName: "app.dashed")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)
                            #endif
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(group.record.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Gelöscht")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }
                                Text("\(group.items.count) Reste • Gesamt: \(group.formattedTotalSize)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if isSelectionMode {
                                let groupURLs = Set(group.items.map { $0.url })
                                let isAllInGroup = !group.items.isEmpty && groupURLs.isSubset(of: selectedURLs)
                                Button {
                                    if isAllInGroup {
                                        selectedURLs.subtract(groupURLs)
                                    } else {
                                        selectedURLs.formUnion(groupURLs)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: isAllInGroup ? "checkmark.circle.fill" : "circle")
                                        Text(isAllInGroup ? "Reste abwählen" : "Alle wählen")
                                    }
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.15))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(role: .destructive) {
                                    viewModel.deleteAllLeftovers(for: group)
                                } label: {
                                    Label("App & alle Reste löschen", systemImage: "trash.fill")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.red)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .hoverGlowButton(color: .red, cornerRadius: 6)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        Divider().padding(.horizontal)
                        
                        switch viewModel.finderViewMode {
                        case .list:
                            LazyVStack(spacing: 2) {
                                ForEach(group.items) { item in
                                    FinderListItemView(
                                        item: item,
                                        isSelectionMode: isSelectionMode,
                                        isSelected: selectedURLs.contains(item.url),
                                        onToggleSelect: {
                                            performMultiSelectClick(
                                                item: item,
                                                in: group.items,
                                                selectedURLs: &selectedURLs,
                                                lastSelectedURL: &lastSelectedURL,
                                                isSelectionMode: &isSelectionMode
                                            )
                                        },
                                        onLongPress: {
                                            #if !os(macOS)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            #endif
                                            isSelectionMode = true
                                            selectedURLs.insert(item.url)
                                            lastSelectedURL = item.url
                                        },
                                        onDelete: {
                                            viewModel.deleteItem(item, from: group)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        case .icons:
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 16)], spacing: 16) {
                                ForEach(group.items) { item in
                                    FinderIconItemView(
                                        item: item,
                                        isSelectionMode: isSelectionMode,
                                        isSelected: selectedURLs.contains(item.url),
                                        onToggleSelect: {
                                            performMultiSelectClick(
                                                item: item,
                                                in: group.items,
                                                selectedURLs: &selectedURLs,
                                                lastSelectedURL: &lastSelectedURL,
                                                isSelectionMode: &isSelectionMode
                                            )
                                        },
                                        onLongPress: {
                                            #if !os(macOS)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            #endif
                                            isSelectionMode = true
                                            selectedURLs.insert(item.url)
                                            lastSelectedURL = item.url
                                        },
                                        onDelete: {
                                            viewModel.deleteItem(item, from: group)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        case .columns:
                            FinderColumnBrowserView(
                                rootItems: group.items,
                                sortOption: viewModel.sortOption,
                                sortAscending: viewModel.sortAscending,
                                onDelete: { item in
                                    viewModel.deleteItem(item, from: group)
                                },
                                isSelectionMode: isSelectionMode,
                                selectedURLs: selectedURLs,
                                onToggleSelect: { item in
                                    performMultiSelectClick(
                                        item: item,
                                        in: group.items,
                                        selectedURLs: &selectedURLs,
                                        lastSelectedURL: &lastSelectedURL,
                                        isSelectionMode: &isSelectionMode
                                    )
                                }
                            )
                            .frame(height: 380)
                        case .gallery:
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 12)], spacing: 12) {
                                ForEach(group.items) { item in
                                    FinderCardItemView(
                                        item: item,
                                        isSelectionMode: isSelectionMode,
                                        isSelected: selectedURLs.contains(item.url),
                                        onToggleSelect: {
                                            performMultiSelectClick(
                                                item: item,
                                                in: group.items,
                                                selectedURLs: &selectedURLs,
                                                lastSelectedURL: &lastSelectedURL,
                                                isSelectionMode: &isSelectionMode
                                            )
                                        },
                                        onLongPress: {
                                            #if !os(macOS)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            #endif
                                            isSelectionMode = true
                                            selectedURLs.insert(item.url)
                                            lastSelectedURL = item.url
                                        },
                                        onDelete: {
                                            viewModel.deleteItem(item, from: group)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(ThemeHelper.secondaryBackground.opacity(0.4))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

#endif
