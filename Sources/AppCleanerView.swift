import SwiftUI
#if os(macOS)
import AppKit
import LocalAuthentication
#else
import UIKit
#endif
import UniformTypeIdentifiers

@MainActor
class AppCleanerViewModel: ObservableObject {

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
    @Published var sortOption: SortOption = .name
    @Published var sortAscending: Bool = true
    
    func setSort(_ option: SortOption) {
        if sortOption == option {
            sortAscending.toggle()
        } else {
            sortOption = option
            sortAscending = (option == .name || option == .category)
        }
    }
    
    @Published var appSearchQuery: String = ""

    var sortedFoundItems: [StorageItem] {
        let list = foundItems.sorted(by: sortOption, ascending: sortAscending)
        let q = appSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
    
    @Published var installedApps: [StorageItem] = []
    
    var sortedApps: [StorageItem] {
        let list = installedApps.sorted(by: sortOption, ascending: sortAscending)
        let q = appSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
    
    static func findExistingLocations(for appURL: URL) -> [StorageItem] {
        let fileManager = FileManager.default
        let appName = appURL.deletingPathExtension().lastPathComponent
        var bundleIdentifier = ""
        if let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier {
            bundleIdentifier = id
        }
        if bundleIdentifier.isEmpty { bundleIdentifier = appName }
        
        var items: [StorageItem] = []
        
        let libraryPaths = [
            "~/Library/Application Support/\(bundleIdentifier)",
            "~/Library/Application Support/\(appName)",
            "~/Library/Caches/\(bundleIdentifier)",
            "~/Library/Caches/\(appName)",
            "~/Library/Preferences/\(bundleIdentifier).plist",
            "~/Library/Containers/\(bundleIdentifier)",
            "~/Library/Group Containers/\(bundleIdentifier)"
        ]
        
        for path in libraryPaths {
            let expanded = NSString(string: path).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if fileManager.fileExists(atPath: expanded) {
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: expanded, isDirectory: &isDir)
                var size: Int64 = 0
                if isDir.boolValue {
                    if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                        while let obj = enumerator.nextObject(), let fURL = obj as? URL {
                            if let r = try? fURL.resourceValues(forKeys: [.fileSizeKey]), let s = r.fileSize {
                                size += Int64(s)
                            }
                        }
                    }
                } else {
                    if let r = try? url.resourceValues(forKeys: [.fileSizeKey]), let s = r.fileSize {
                        size = Int64(s)
                    }
                }
                let attrs = try? fileManager.attributesOfItem(atPath: expanded)
                let cDate = attrs?[.creationDate] as? Date
                let mDate = attrs?[.modificationDate] as? Date
                items.append(StorageItem(url: url, isDirectory: isDir.boolValue, size: size, creationDate: cDate, modificationDate: mDate))
            }
        }
        return items
    }
    
    func loadInstalledApps(from customDir: URL? = nil) {
        self.isScanning = true
        Task.detached {
            let fileManager = FileManager.default
            #if os(macOS)
            let appDirs: [String]
            if let customDir = customDir {
                appDirs = [customDir.path]
            } else {
                appDirs = [
                    "/Applications",
                    "/System/Applications",
                    "/System/Applications/Utilities",
                    (NSString(string: "~/Applications").expandingTildeInPath),
                    (NSString(string: "~/Desktop").expandingTildeInPath),
                    (NSString(string: "~/Downloads").expandingTildeInPath)
                ]
            }
            #else
            let appDirs: [String]
            if let customDir = customDir {
                appDirs = [customDir.path]
            } else {
                let bundleDir = Bundle.main.bundleURL.deletingLastPathComponent().path
                let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? ""
                appDirs = [bundleDir, "/Applications", docsDir, appSupport].filter { !$0.isEmpty }
            }
            #endif
            var apps: [StorageItem] = []
            
            for dir in appDirs {
                let url = URL(fileURLWithPath: dir)
                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) {
                    while let obj = enumerator.nextObject(), let appURL = obj as? URL {
                        var isApp = appURL.pathExtension == "app"
                        #if !os(macOS)
                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: appURL.path, isDirectory: &isDir), isDir.boolValue {
                            isApp = true
                        }
                        #endif
                        if isApp {
                            if let res = try? appURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
                                apps.append(StorageItem(url: appURL, isDirectory: true, size: 0, creationDate: res.creationDate, modificationDate: res.contentModificationDate))
                            }
                        }
                    }
                }
            }
            
            let sortedApps = apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
            await MainActor.run {
                self.installedApps = sortedApps
                self.isScanning = false
            }
        }
    }

    @Published var foundItems: [StorageItem] = []
    @Published var isScanning = false
    @Published var searchQuery: String = ""
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var adminFallbackAction: (() -> Void)?
    
    // MacOS Spezifisch
    @Published var selectedAppURL: URL?

    #if os(macOS)
    private func robustDelete(url: URL, completion: @escaping (Error?) -> Void) {
        let context = LAContext()
        var authError: NSError?
        
        let reason = "iSweep benötigt Berechtigung, um die Datei sicher zu löschen."
        
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
            // Fallback (z.B. wenn kein Touch ID oder Passwort gesetzt ist)
            performActualDelete(url: url, completion: completion)
        }
    }
    
    private func performActualDelete(url: URL, completion: @escaping (Error?) -> Void) {
        // Zunächst versuchen wir den schnellen FileManager Weg (klappt oft bei Desktop/Downloads)
        do {
            var outURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &outURL)
            DispatchQueue.main.async {
                _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
                completion(nil)
            }
            return
        } catch {}
        
        // Direkter Versuch über macOS Workspace
        NSWorkspace.shared.recycle([url]) { _, error in
            if let err = error as NSError? {
                DispatchQueue.main.async {
                    self.errorMessage = "Das native Mac-Löschen wurde wg. fehlender Rechte blockiert.\n\nTipp am Rande: Für die beste Touch-ID Erfahrung (ohne diese Meldung) erteile der App bitte Berechtigungen unter 'App-Verwaltung' in den System-Einstellungen.\n\nMöchtest du es stattdessen hart als Admin (Klassische Passwort-Eingabe) entfernen?"
                    
                    self.adminFallbackAction = {
                        let adminScript = "do shell script \"rm -rf \" & quoted form of \"\(url.path)\" with administrator privileges"
                        if let script = NSAppleScript(source: adminScript) {
                            DispatchQueue.global().async {
                                var errorInfo: NSDictionary? = nil
                                script.executeAndReturnError(&errorInfo)
                                DispatchQueue.main.async {
                                    if let info = errorInfo, let msg = info[NSAppleScript.errorMessage] as? String {
                                        self.errorMessage = "Löschen entgültig gescheitert: \(msg)"
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
    #endif

    func deleteParentFolder(of item: StorageItem) {
        guard let rootURL = self.selectedAppURL else { return }
        let parentURL = item.url.deletingLastPathComponent()
        
        if parentURL.path == rootURL.path {
            self.errorMessage = "Der Hauptordner kann hier nicht gelöscht werden."
            self.showError = true
            return
        }
        
        #if os(macOS)
        robustDelete(url: parentURL) { error in
            if let _ = error {
                // error message wird bereits in robustDelete gesetzt!
            } else {
                self.foundItems.removeAll { $0.url.path.hasPrefix(parentURL.path) }
            }
        }
        #else
        let startAccessing = rootURL.startAccessingSecurityScopedResource()
        defer { if startAccessing { rootURL.stopAccessingSecurityScopedResource() } }
        
        var deletionError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        
        coordinator.coordinate(writingItemAt: parentURL, options: .forDeleting, error: &coordinatorError) { coordinatedURL in
            do {
                if #available(iOS 11.0, *) {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: &resultingURL)
                } else {
                    try FileManager.default.removeItem(at: coordinatedURL)
                }
            } catch {
                deletionError = error
            }
        }
        
        if let _ = deletionError ?? coordinatorError {
            self.errorMessage = "Fehler beim Löschen des Ordners."
            self.showError = true
        } else {
            self.foundItems.removeAll { $0.url.path.hasPrefix(parentURL.path) }
        }
        #endif
    }

    func deleteItem(_ item: StorageItem) {
        #if os(macOS)
        if item.url.pathExtension == "app" {
            let icon = NSWorkspace.shared.icon(forFile: item.url.path)
            var iconData: Data? = nil
            if let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                iconData = rep.representation(using: .png, properties: [:])
            }
            let bundleID = Bundle(url: item.url)?.bundleIdentifier ?? item.name.replacingOccurrences(of: ".app", with: "")
            let appName = item.name.replacingOccurrences(of: ".app", with: "")
            DeletedAppTracker.shared.recordDeletedApp(name: appName, bundleIdentifier: bundleID, iconData: iconData)
        }
        robustDelete(url: item.url) { error in
            if let _ = error {
                // error message wird bereits in robustDelete gesetzt!
            } else {
                self.foundItems.removeAll { $0.id == item.id }
                self.installedApps.removeAll { $0.url.path == item.url.path }
                CleanStatisticsManager.shared.recordReclaimed(bytes: item.size)
            }
        }
        #else
        let parentURL = self.selectedAppURL ?? item.url
        let startAccessing = parentURL.startAccessingSecurityScopedResource()
        defer { if startAccessing { parentURL.stopAccessingSecurityScopedResource() } }
        
        var deletionError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        
        coordinator.coordinate(writingItemAt: item.url, options: .forDeleting, error: &coordinatorError) { coordinatedURL in
            do {
                if #available(iOS 11.0, *) {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: &resultingURL)
                } else {
                    try FileManager.default.removeItem(at: coordinatedURL)
                }
            } catch {
                deletionError = error
            }
        }
        
        if let _ = deletionError ?? coordinatorError {
            self.errorMessage = "Fehler beim Löschen."
            self.showError = true
        } else {
            self.foundItems.removeAll { $0.id == item.id }
        }
        #endif
    }
    
    func deleteApps(urls: Set<URL>) {
        let appsToDelete = self.installedApps.filter { urls.contains($0.url) }
        guard !appsToDelete.isEmpty else { return }
        for app in appsToDelete {
            self.deleteItem(app)
        }
    }
    
    func deleteFoundItems(urls: Set<URL>) {
        let itemsToDelete = self.foundItems.filter { urls.contains($0.url) }
        guard !itemsToDelete.isEmpty else { return }
        #if os(macOS)
        let urlList = itemsToDelete.map { $0.url }
        NSWorkspace.shared.recycle(urlList) { _, error in
            DispatchQueue.main.async {
                if let _ = error {
                    for item in itemsToDelete {
                        self.deleteItem(item)
                    }
                } else {
                    let ids = Set(itemsToDelete.map { $0.id })
                    let totalReclaimed = itemsToDelete.reduce(Int64(0)) { $0 + $1.size }
                    self.foundItems.removeAll { ids.contains($0.id) }
                    CleanStatisticsManager.shared.recordReclaimed(bytes: totalReclaimed)
                    _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
                }
            }
        }
        #else
        for item in itemsToDelete {
            self.deleteItem(item)
        }
        #endif
    }
    
    func scanMacAppLeftovers(appURL: URL) {
        self.selectedAppURL = appURL
        self.isScanning = true
        self.foundItems = []
        
        Task.detached {
            let fileManager = FileManager.default
            let appName = appURL.deletingPathExtension().lastPathComponent
            var bundleIdentifier = ""
            if let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier {
                bundleIdentifier = id
            }
            if bundleIdentifier.isEmpty { bundleIdentifier = appName }
            
            var items: [StorageItem] = []
            
            #if os(macOS)
            let libraryPaths = [
                "~/Library/Application Support/\(bundleIdentifier)",
                "~/Library/Application Support/\(appName)",
                "~/Library/Caches/\(bundleIdentifier)",
                "~/Library/Caches/\(appName)",
                "~/Library/Preferences/\(bundleIdentifier).plist",
                "~/Library/Containers/\(bundleIdentifier)"
            ]
            #else
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path ?? ""
            let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? ""
            let libraryPaths = [
                "\(cachesDir)/\(bundleIdentifier)",
                "\(cachesDir)/\(appName)",
                "\(appSupportDir)/\(bundleIdentifier)",
                "\(appSupportDir)/\(appName)"
            ]
            #endif
            
            for path in libraryPaths {
                let expanded = NSString(string: path).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded)
                
                if fileManager.fileExists(atPath: expanded) {
                    var isDir: ObjCBool = false
                    fileManager.fileExists(atPath: expanded, isDirectory: &isDir)
                    
                    var totalSize: Int64 = 0
                    if isDir.boolValue, let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                        while let obj = enumerator.nextObject(), let fileURL = obj as? URL {
                            if let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = res.fileSize {
                                totalSize += Int64(size)
                            }
                        }
                    } else if !isDir.boolValue, let res = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = res.fileSize {
                        totalSize = Int64(size)
                    }
                    
                    let attrs = try? fileManager.attributesOfItem(atPath: expanded)
                    let cDate = attrs?[.creationDate] as? Date
                    let mDate = attrs?[.modificationDate] as? Date
                    
                    items.append(StorageItem(url: url, isDirectory: isDir.boolValue, size: totalSize, creationDate: cDate, modificationDate: mDate))
                }
            }
            
            items.insert(StorageItem(url: appURL, isDirectory: true, size: 0, creationDate: nil, modificationDate: nil), at: 0)
            
            await MainActor.run {
                self.foundItems = items
                self.isScanning = false
            }
        }
    }

    func scanLeftoversInFolder(name query: String, searchRoot url: URL) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        self.isScanning = true
        self.foundItems = []
        
        let lowerQuery = query.lowercased()
        
        Task.detached {
            let startAccessing = url.startAccessingSecurityScopedResource()
            defer { if startAccessing { url.stopAccessingSecurityScopedResource() } }
            
            let fileManager = FileManager.default
            var items: [StorageItem] = []
            
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
                var count = 0
                while let obj = enumerator.nextObject(), let fileURL = obj as? URL {
                    count += 1
                    let filename = fileURL.lastPathComponent.lowercased()
                    if filename.contains(lowerQuery) {
                        do {
                            let res = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
                            let isDir = res.isDirectory ?? false
                            var itemSize = Int64(res.fileSize ?? 0)
                            
                            if isDir {
                                let subEnum = fileManager.enumerator(at: fileURL, includingPropertiesForKeys: [.fileSizeKey], options: [])
                                while let sObj = subEnum?.nextObject(), let sURL = sObj as? URL {
                                    if let sr = try? sURL.resourceValues(forKeys: [.fileSizeKey]), let ds = sr.fileSize { itemSize += Int64(ds) }
                                }
                                enumerator.skipDescendants()
                            }
                            items.append(StorageItem(url: fileURL, isDirectory: isDir, size: itemSize, creationDate: res.creationDate, modificationDate: res.contentModificationDate))
                        } catch { }
                    }
                    if count % 1000 == 0 { await Task.yield() }
                }
            }
            
            let sortedItems = items.sorted { $0.size > $1.size }
            await MainActor.run {
                self.foundItems = sortedItems
                self.isScanning = false
            }
        }
    }
}

struct AppCleanerView: View {
    @StateObject private var viewModel = AppCleanerViewModel()
    @State private var showFolderPicker = false
    @State private var itemToDelete: StorageItem?
    @State private var pathBarText: String = "/Applications" 
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
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section {
                    SidebarAppHeaderView(subtitle: "App-Deinstaller")
                    SystemStorageGaugeView()
                }
                
                Section("Aktionen") {
                    #if os(macOS)
                    Button(action: {
                        viewModel.loadInstalledApps()
                    }) {
                        Label("Apps aktualisieren", systemImage: "arrow.clockwise")
                    }
                    Button(action: {
                        viewModel.loadInstalledApps(from: URL(fileURLWithPath: "/Applications"))
                    }) {
                        Label("Programme (/Applications)", systemImage: "macwindow")
                    }
                    Button(action: {
                        let userApps = URL(fileURLWithPath: ("~/Applications" as NSString).expandingTildeInPath)
                        viewModel.loadInstalledApps(from: userApps)
                    }) {
                        Label("Benutzer-Apps (~/Applications)", systemImage: "person.crop.square")
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
                        Label(isSelectionMode ? "Auswahl beenden" : "Elemente auswählen", systemImage: isSelectionMode ? "checkmark.circle.fill" : "checklist")
                    }
                }
                
                SidebarTrashSectionView()
                
                Section("Übersicht") {
                    Text("\(viewModel.installedApps.count) Apps installiert")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !viewModel.foundItems.isEmpty {
                        Text("\(viewModel.foundItems.count) Reste gefunden")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Section("Erscheinungsbild") {
                    ThemeSwitchView()
                }
            }
            .navigationTitle("App-Deinstaller")
            .searchable(text: $viewModel.appSearchQuery, prompt: "Installierte Apps suchen…")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    AppHeaderIconView()
                }
            }
            .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 400)
        } detail: {
            contentBody
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        TrashQuickBarButton()
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            MacTrashManager.shared.promptEmptyTrash()
                        } label: {
                            Label("Papierkorb leeren", systemImage: "trash.slash.fill")
                        }
                    }
                    
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
                        Button(action: {
                            viewModel.loadInstalledApps()
                        }) {
                            Label("Aktualisieren", systemImage: "arrow.clockwise")
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            columnVisibility = .all
            viewModel.loadInstalledApps()
        }
        .alert(isPresented: $viewModel.showError) {
            if let action = viewModel.adminFallbackAction {
                return Alert(
                    title: Text("macOS Blockade"),
                    message: Text(viewModel.errorMessage ?? ""),
                    primaryButton: .destructive(Text("Trotzdem per Passwort löschen"), action: {
                        action()
                        viewModel.adminFallbackAction = nil
                    }),
                    secondaryButton: .cancel(Text("Abbrechen"))
                )
            } else {
                return Alert(title: Text("Fehler"), message: Text(viewModel.errorMessage ?? ""), dismissButton: .default(Text("OK")))
            }
        }
        .confirmationDialog(
            "Möchtest du \(selectedURLs.count) ausgewählte Elemente wirklich löschen?",
            isPresented: $showBatchDeleteAlert,
            titleVisibility: .visible
        ) {
            Button("Ausgewählte löschen (\(selectedURLs.count))", role: .destructive) {
                if viewModel.foundItems.isEmpty {
                    viewModel.deleteApps(urls: selectedURLs)
                } else {
                    viewModel.deleteFoundItems(urls: selectedURLs)
                }
                selectedURLs.removeAll()
                isSelectionMode = false
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            let currentPool = viewModel.foundItems.isEmpty ? viewModel.sortedApps : viewModel.sortedFoundItems
            let selectedItems = currentPool.filter { selectedURLs.contains($0.url) }
            let totalBytes = selectedItems.reduce(Int64(0)) { $0 + $1.size }
            let formatter = ByteCountFormatter()
            let sizeStr = formatter.string(fromByteCount: totalBytes)
            Text("Gesamtgröße: \(sizeStr). Die \(selectedURLs.count) Elemente werden in den Papierkorb verschoben.")
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
    private var contentBody: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            FilePathBarView(
                pathText: $pathBarText,
                placeholder: "App- oder Ordnerpfad eingeben (z. B. /Applications/Slack.app oder /Applications)...",
                onCommitPath: { url in
                    if url.pathExtension == "app" {
                        viewModel.scanMacAppLeftovers(appURL: url)
                    } else {
                        viewModel.loadInstalledApps(from: url)
                    }
                },
                currentItemURL: viewModel.selectedAppURL
            )
            .onChange(of: viewModel.selectedAppURL) { newURL in
                if let u = newURL {
                    pathBarText = u.path
                }
            }
            #else
            FilePathBarView(
                pathText: $pathBarText,
                placeholder: "Dateipfad eingeben...",
                onCommitPath: { url in }
            )
            #endif
            
            if viewModel.isScanning {
                ProgressView("Suche Reste...").padding()
            } else if viewModel.foundItems.isEmpty {
                emptyState
            } else {
                resultsState
            }
            
            if isSelectionMode {
                #if os(macOS)
                let currentPool = viewModel.foundItems.isEmpty ? viewModel.sortedApps : viewModel.sortedFoundItems
                #else
                let currentPool = viewModel.sortedFoundItems
                #endif
                let selectedItems = currentPool.filter { selectedURLs.contains($0.url) }
                let totalBytes = selectedItems.reduce(Int64(0)) { $0 + $1.size }
                let formatter = ByteCountFormatter()
                let sizeStr = formatter.string(fromByteCount: totalBytes)
                
                BatchSelectionActionBar(
                    selectedCount: selectedURLs.count,
                    totalSizeText: sizeStr,
                    allSelected: !currentPool.isEmpty && selectedURLs.count == currentPool.count,
                    onToggleSelectAll: {
                        if selectedURLs.count == currentPool.count {
                            selectedURLs.removeAll()
                        } else {
                            selectedURLs = Set(currentPool.map { $0.url })
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
    private var emptyState: some View {
        if !viewModel.installedApps.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("\(viewModel.sortedApps.count) Apps installiert")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Sortiert: \(viewModel.sortOption.rawValue) (\(viewModel.sortAscending ? "▲" : "▼"))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                
                switch viewModel.finderViewMode {
                case .list:
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(viewModel.sortedApps) { app in
                                macAppRow(for: app)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                case .icons:
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 140), spacing: 16)], spacing: 16) {
                            ForEach(viewModel.sortedApps) { app in
                                AppIconItemView(
                                    app: app,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedURLs.contains(app.url),
                                    onToggleSelect: {
                                        performMultiSelectClick(
                                            item: app,
                                            in: viewModel.sortedApps,
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
                                        selectedURLs.insert(app.url)
                                        lastSelectedURL = app.url
                                    },
                                    onUninstall: {
                                        viewModel.scanMacAppLeftovers(appURL: app.url)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                case .columns:
                    FinderColumnBrowserView(
                        rootItems: viewModel.sortedApps,
                        sortOption: viewModel.sortOption,
                        sortAscending: viewModel.sortAscending,
                        onDelete: { app in
                            viewModel.scanMacAppLeftovers(appURL: app.url)
                        },
                        childrenProvider: { appItem in
                            if appItem.category == .apps {
                                return AppCleanerViewModel.findExistingLocations(for: appItem.url)
                            }
                            return nil
                        },
                        onItemSelected: { item in
                            pathBarText = item.url.path
                        },
                        isSelectionMode: isSelectionMode,
                        selectedURLs: selectedURLs,
                        onToggleSelect: { item in
                            performMultiSelectClick(
                                item: item,
                                in: viewModel.sortedApps,
                                selectedURLs: &selectedURLs,
                                lastSelectedURL: &lastSelectedURL,
                                isSelectionMode: &isSelectionMode
                            )
                        },
                        onSelectRange: { item, columnItems in
                            performMultiSelectClick(
                                item: item,
                                in: columnItems,
                                selectedURLs: &selectedURLs,
                                lastSelectedURL: &lastSelectedURL,
                                isSelectionMode: &isSelectionMode
                            )
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .gallery:
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 12)], spacing: 12) {
                            ForEach(viewModel.sortedApps) { app in
                                AppCardItemView(
                                    app: app,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedURLs.contains(app.url),
                                    onToggleSelect: {
                                        performMultiSelectClick(
                                            item: app,
                                            in: viewModel.sortedApps,
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
                                        selectedURLs.insert(app.url)
                                        lastSelectedURL = app.url
                                    },
                                    onUninstall: {
                                        viewModel.scanMacAppLeftovers(appURL: app.url)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "app.badge.minus")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Keine Apps oder Container gefunden")
                    .font(.headline)
                Button("Apps aktualisieren") {
                    viewModel.loadInstalledApps()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
    
    @ViewBuilder
    private func macAppRow(for app: StorageItem) -> some View {
        let isAppSelected = selectedURLs.contains(app.url)
        HStack {
            if isSelectionMode {
                Button {
                    performMultiSelectClick(
                        item: app,
                        in: viewModel.sortedApps,
                        selectedURLs: &selectedURLs,
                        lastSelectedURL: &lastSelectedURL,
                        isSelectionMode: &isSelectionMode
                    )
                } label: {
                    Image(systemName: isAppSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isAppSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            #if os(macOS)
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 32, height: 32)
            #else
            Image(systemName: "app.fill")
                .font(.system(size: 26))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
            #endif
            VStack(alignment: .leading) {
                Text(app.name).font(.headline)
                Text(app.url.path).font(.caption).foregroundColor(.gray)
            }
            Spacer()
            if !isSelectionMode {
                Button {
                    viewModel.scanMacAppLeftovers(appURL: app.url)
                } label: {
                    Text("App & Reste löschen")
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .hoverGlowButton(color: .red, cornerRadius: 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            performMultiSelectClick(
                item: app,
                in: viewModel.sortedApps,
                selectedURLs: &selectedURLs,
                lastSelectedURL: &lastSelectedURL,
                isSelectionMode: &isSelectionMode
            )
        }
        #if !os(macOS)
        .onLongPressGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            isSelectionMode = true
            selectedURLs.insert(app.url)
            lastSelectedURL = app.url
        }
        #endif
        .hoverGlowRow()
        .padding(.vertical, 2)
        .background(isAppSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(6)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.scanMacAppLeftovers(appURL: app.url)
            } label: {
                Label("App & Reste suchen", systemImage: "magnifyingglass")
            }
        }
    }
    
    #if !os(macOS)
    @ViewBuilder
    private var iosEmptyState: some View {
        VStack(spacing: 20) {
            Text("iPad App-Deinstallation").font(.title2)
            Text("iOS erlaubt es Drittanbieter-Apps nicht, andere Apps auszulesen.")
                .multilineTextAlignment(.center)
            
            TextField("Name der App", text: $viewModel.searchQuery)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Ordner auswählen") {
                showFolderPicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if let url = try? result.get().first {
                viewModel.scanLeftoversInFolder(name: viewModel.searchQuery, searchRoot: url)
            }
        }
    }
    #endif
    
    @ViewBuilder
    private var resultsState: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← Zurück zur App-Liste") {
                    viewModel.foundItems = []
                    viewModel.selectedAppURL = nil
                }
                .hoverGlowButton(cornerRadius: 6)
                
                Spacer()
                
                Text("\(viewModel.sortedFoundItems.count) Reste gefunden")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            
            switch viewModel.finderViewMode {
            case .list:
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.sortedFoundItems) { item in
                            FinderListItemView(
                                item: item,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedURLs.contains(item.url),
                                onToggleSelect: {
                                    performMultiSelectClick(
                                        item: item,
                                        in: viewModel.sortedFoundItems,
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
                                    viewModel.deleteItem(item)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            case .icons:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 16)], spacing: 16) {
                        ForEach(viewModel.sortedFoundItems) { item in
                            FinderIconItemView(
                                item: item,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedURLs.contains(item.url),
                                onToggleSelect: {
                                    performMultiSelectClick(
                                        item: item,
                                        in: viewModel.sortedFoundItems,
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
                                    viewModel.deleteItem(item)
                                }
                            )
                        }
                    }
                    .padding()
                }
            case .columns:
                FinderColumnBrowserView(
                    rootItems: viewModel.sortedFoundItems,
                    sortOption: viewModel.sortOption,
                    sortAscending: viewModel.sortAscending,
                    onDelete: { item in
                        viewModel.deleteItem(item)
                    },
                    onItemSelected: { item in
                        pathBarText = item.url.path
                    },
                    isSelectionMode: isSelectionMode,
                    selectedURLs: selectedURLs,
                    onToggleSelect: { item in
                        performMultiSelectClick(
                            item: item,
                            in: viewModel.sortedFoundItems,
                            selectedURLs: &selectedURLs,
                            lastSelectedURL: &lastSelectedURL,
                            isSelectionMode: &isSelectionMode
                        )
                    },
                    onSelectRange: { item, columnItems in
                        performMultiSelectClick(
                            item: item,
                            in: columnItems,
                            selectedURLs: &selectedURLs,
                            lastSelectedURL: &lastSelectedURL,
                            isSelectionMode: &isSelectionMode
                        )
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .gallery:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 12)], spacing: 12) {
                        ForEach(viewModel.sortedFoundItems) { item in
                            FinderCardItemView(
                                item: item,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedURLs.contains(item.url),
                                onToggleSelect: {
                                    performMultiSelectClick(
                                        item: item,
                                        in: viewModel.sortedFoundItems,
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
                                    viewModel.deleteItem(item)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }
}
