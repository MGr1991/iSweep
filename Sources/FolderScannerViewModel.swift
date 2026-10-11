import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

enum FilterType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all = "Alle Dateien"
    case hugeFiles = "Riesendateien (> 500 MB)"
    case largeFiles = "Große Dateien (> 100 MB)"
    case oldFiles = "Alte Dateien (> 6 Monate)"
    case folders = "Nur Ordner"
    case images = "Bilder"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Dokumente"
    case archives = "Archive & Zips"
    case developer = "Entwickler-Dateien"
    
    var id: String { rawValue }
    
    func matches(url: URL, size: Int64 = 0, date: Date? = nil) -> Bool {
        switch self {
        case .all:
            return true
        case .hugeFiles:
            return size >= 500 * 1024 * 1024
        case .largeFiles:
            return size >= 100 * 1024 * 1024
        case .oldFiles:
            if let d = date {
                return d < Date().addingTimeInterval(-180 * 24 * 3600)
            }
            return false
        case .folders:
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        case .images:
            let ext = url.pathExtension.lowercased()
            return ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "svg", "raw", "cr2", "nef"].contains(ext)
        case .videos:
            let ext = url.pathExtension.lowercased()
            return ["mp4", "mov", "mkv", "avi", "m4v", "wmv", "flv", "webm"].contains(ext)
        case .audio:
            let ext = url.pathExtension.lowercased()
            return ["mp3", "wav", "m4a", "flac", "aac", "aiff", "ogg"].contains(ext)
        case .documents:
            let ext = url.pathExtension.lowercased()
            return ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "txt", "rtf", "pages", "numbers", "keynote", "csv", "md"].contains(ext)
        case .archives:
            let ext = url.pathExtension.lowercased()
            return ["zip", "tar", "gz", "bz2", "7z", "rar", "dmg", "iso", "pkg"].contains(ext)
        case .developer:
            let path = url.path
            let ext = url.pathExtension.lowercased()
            return path.contains("DerivedData") || path.contains("CoreSimulator") || path.contains("Archives") || ext == "xcarchive" || path.contains(".build") || ["swift", "h", "m", "c", "cpp", "py", "js", "ts", "json", "xml", "plist"].contains(ext)
        }
    }
}

struct CategoryGroup: Identifiable {
    var id: String { category.id }
    let category: FileCategory
    let items: [StorageItem]
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}

enum ViewMode: String, CaseIterable, Identifiable, Hashable {
    case hierarchical = "Hierarchisch"
    case flat = "Flache Liste"
    var id: String { rawValue }
}

@MainActor
class FolderScannerViewModel: ObservableObject {
    @Published var items: [StorageItem] = []
    @Published var isScanning = false
    @Published var scanProgress = 0.0
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var currentFolderURL: URL?
    
    @Published var filterType: FilterType = .all
    @Published var viewMode: ViewMode = .hierarchical
    @Published var finderViewMode: FinderViewMode = FinderViewMode.shared {
        didSet {
            if finderViewMode != FinderViewMode.shared {
                FinderViewMode.shared = finderViewMode
            }
        }
    }
    @Published var sortOption: SortOption = .size
    @Published var sortAscending: Bool = false
    @Published var groupByKind: Bool = false
    
    func setSort(_ option: SortOption) {
        if sortOption == option {
            sortAscending.toggle()
        } else {
            sortOption = option
            // Default to descending for size & date, ascending for name & category
            sortAscending = (option == .name || option == .category)
        }
    }
    
    @Published var searchText: String = ""
    
    var sortedItems: [StorageItem] {
        let filtered = items.filter { item in
            guard filterType.matches(url: item.url, size: item.size, date: item.modificationDate) else { return false }
            let query = searchText.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty {
                return item.name.localizedCaseInsensitiveContains(query)
            }
            return true
        }
        return filtered.sorted { a, b in
            switch sortOption {
            case .name:
                let cmp = a.name.localizedStandardCompare(b.name)
                return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            case .size:
                return sortAscending ? (a.size < b.size) : (a.size > b.size)
            case .date:
                let dateA = a.modificationDate ?? Date.distantPast
                let dateB = b.modificationDate ?? Date.distantPast
                return sortAscending ? (dateA < dateB) : (dateA > dateB)
            case .category:
                if a.category == b.category {
                    return a.size > b.size
                }
                return sortAscending ? (a.category < b.category) : (a.category > b.category)
            }
        }
    }
    
    var groupedItems: [CategoryGroup] {
        let itemsList = sortedItems
        let grouped = Dictionary(grouping: itemsList) { $0.category }
        return FileCategory.allCases.compactMap { cat in
            guard let list = grouped[cat], !list.isEmpty else { return nil }
            return CategoryGroup(category: cat, items: list)
        }
    }
    
    private let bookmarkKey = "SavedFolderBookmark"
    
    init() {
        restoreBookmark()
        NotificationCenter.default.addObserver(forName: FinderViewMode.didChangeNotification, object: nil, queue: .main) { [weak self] notif in
            if let mode = notif.object as? FinderViewMode, self?.finderViewMode != mode {
                self?.finderViewMode = mode
            }
        }
    }
    
    func rescan() {
        if let url = currentFolderURL {
            scanFolder(url: url)
        }
    }
    
    func scanFolder(url: URL) {
        currentFolderURL = url
        saveBookmark(for: url)
        isScanning = true
        items = []
        
        let currentFilter = self.filterType
        let currentViewMode = self.viewMode
        
        Task.detached {
            let startAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if startAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let fileManager = FileManager.default
            
            do {
                let topLevelURLs = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
                
                if currentViewMode == .hierarchical {
                    let scannedItems = await withTaskGroup(of: StorageItem?.self) { group in
                        for topURL in topLevelURLs {
                            group.addTask {
                                do {
                                    let resourceValues = try topURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
                                    let isDir = resourceValues.isDirectory ?? false
                                    
                                    var totalSize: Int64 = 0
                                    
                                    if isDir {
                                        let localFileManager = FileManager.default
                                        if let enumerator = localFileManager.enumerator(at: topURL, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                                            var count = 0
                                            while let obj = enumerator.nextObject(), let fileURL = obj as? URL {
                                                count += 1
                                                
                                                if currentFilter.matches(url: fileURL) {
                                                    if let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = res.fileSize {
                                                        totalSize += Int64(size)
                                                    }
                                                }
                                                
                                                if count % 1000 == 0 {
                                                    await Task.yield()
                                                }
                                            }
                                        }
                                    } else {
                                        if currentFilter.matches(url: topURL) {
                                            totalSize = Int64(resourceValues.fileSize ?? 0)
                                        }
                                    }
                                    
                                    if currentFilter != .all && totalSize == 0 {
                                        return nil
                                    }
                                    
                                    return StorageItem(
                                        url: topURL,
                                        isDirectory: isDir,
                                        size: totalSize,
                                        creationDate: resourceValues.creationDate,
                                        modificationDate: resourceValues.contentModificationDate
                                    )
                                } catch {
                                    return nil
                                }
                            }
                        }
                        
                        var results: [StorageItem] = []
                        for await item in group {
                            if let item = item {
                                results.append(item)
                            }
                        }
                        return results
                    }
                    
                    let sortedItems = scannedItems.sorted { $0.size > $1.size }
                    await MainActor.run {
                        self.items = sortedItems
                        self.isScanning = false
                    }
                    
                } else {
                    let scannedItems = await withTaskGroup(of: [StorageItem].self) { group in
                        for topURL in topLevelURLs {
                            group.addTask {
                                var foundItems: [StorageItem] = []
                                let localFileManager = FileManager.default
                                
                                let res = try? topURL.resourceValues(forKeys: [.isDirectoryKey])
                                let isDir = res?.isDirectory ?? false
                                
                                if isDir {
                                    if let enumerator = localFileManager.enumerator(at: topURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey], options: []) {
                                        var count = 0
                                        while let obj = enumerator.nextObject(), let fileURL = obj as? URL {
                                            count += 1
                                            
                                            if let r = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]), !(r.isDirectory ?? false) {
                                                if currentFilter.matches(url: fileURL) {
                                                    if let r2 = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]), let size = r2.fileSize {
                                                        if size > 0 || currentFilter == .all {
                                                            foundItems.append(StorageItem(url: fileURL, isDirectory: false, size: Int64(size), creationDate: r2.creationDate, modificationDate: r2.contentModificationDate))
                                                        }
                                                    }
                                                }
                                            }
                                            
                                            if count % 1000 == 0 { await Task.yield() }
                                        }
                                    }
                                } else {
                                    if currentFilter.matches(url: topURL) {
                                        if let r2 = try? topURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]), let size = r2.fileSize {
                                            foundItems.append(StorageItem(url: topURL, isDirectory: false, size: Int64(size), creationDate: r2.creationDate, modificationDate: r2.contentModificationDate))
                                        }
                                    }
                                }
                                
                                return foundItems
                            }
                        }
                        
                        var allItems: [StorageItem] = []
                        for await array in group {
                            allItems.append(contentsOf: array)
                        }
                        return allItems
                    }
                    
                    let sortedItems = scannedItems.sorted { $0.size > $1.size }
                    await MainActor.run {
                        self.items = sortedItems
                        self.isScanning = false
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Fehler beim Lesen des Verzeichnisses: \(error.localizedDescription)"
                    self.showError = true
                    self.isScanning = false
                }
            }
        }
    }
    
    
    #if os(macOS)
    
    private func robustDelete(url: URL, completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.recycle([url]) { _, error in
            if let err = error {
                let path = url.path.replacingOccurrences(of: "\"", with: "\\\"")
                let scriptSource = "do shell script \"rm -rf \\\"\(path)\\\"\" with administrator privileges"
                if let script = NSAppleScript(source: scriptSource) {
                    DispatchQueue.global().async {
                        var errorInfo: NSDictionary? = nil
                        script.executeAndReturnError(&errorInfo)
                        DispatchQueue.main.async {
                            if let errorInfo = errorInfo {
                                completion(NSError(domain: "iSweep", code: 1, userInfo: ["info": errorInfo]))
                            } else {
                                completion(nil)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async { completion(err) }
                }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    #endif

    func deleteParentFolder(of item: StorageItem) {
        guard let rootURL = currentFolderURL else { return }
        let parentURL = item.url.deletingLastPathComponent()
        
        if parentURL.path == rootURL.path {
            self.errorMessage = "Der Hauptordner kann hier nicht gelöscht werden."
            self.showError = true
            return
        }
        
        #if os(macOS)
        robustDelete(url: parentURL) { error in
            if let _ = error {
                self.errorMessage = "Konnte Ordner nicht löschen (Berechtigung verweigert oder abgebrochen)."
                self.showError = true
            } else {
                self.items.removeAll { $0.url.path.hasPrefix(parentURL.path) }
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
            self.items.removeAll { $0.url.path.hasPrefix(parentURL.path) }
        }
        #endif
    }

    func deleteItems(urls: Set<URL>) {
        let itemsToDelete = self.items.filter { urls.contains($0.url) }
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
                    let reclaimed = itemsToDelete.reduce(Int64(0)) { $0 + $1.size }
                    self.items.removeAll { ids.contains($0.id) }
                    CleanStatisticsManager.shared.recordReclaimed(bytes: reclaimed)
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

    func deleteItem(_ item: StorageItem) {
        #if os(macOS)
        robustDelete(url: item.url) { error in
            if let _ = error {
                self.errorMessage = "Konnte Element nicht löschen (Berechtigung verweigert oder abgebrochen)."
                self.showError = true
            } else {
                self.items.removeAll { $0.id == item.id }
                CleanStatisticsManager.shared.recordReclaimed(bytes: item.size)
            }
        }
        #else
        let parentURL = currentFolderURL ?? item.url
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
            self.items.removeAll { $0.id == item.id }
        }
        #endif
    }
    

    private func saveBookmark(for url: URL) {
        do {
            #if os(macOS)
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            UserDefaults.standard.set(bookmarkData, forKey: "lastFolderBookmark")
        } catch { }
    }
    
    private func restoreBookmark() {
        if let bookmarkData = UserDefaults.standard.data(forKey: "lastFolderBookmark") {
            do {
                var isStale = false
                #if os(macOS)
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                #else
                let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                #endif
                if !isStale {
                    scanFolder(url: url)
                }
            } catch { }
        }
    }
}
