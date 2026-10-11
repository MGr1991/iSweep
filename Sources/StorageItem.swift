import Foundation

enum FileCategory: String, CaseIterable, Identifiable, Comparable, Sendable {
    case folder = "Ordner"
    case images = "Bilder"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Dokumente"
    case archives = "Archive & Zips"
    case apps = "Programme"
    case developer = "Entwickler-Dateien"
    case other = "Sonstige"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .folder: return "folder.fill"
        case .images: return "photo.fill"
        case .videos: return "film.fill"
        case .audio: return "music.note"
        case .documents: return "doc.text.fill"
        case .archives: return "archivebox.fill"
        case .apps: return "app.fill"
        case .developer: return "hammer.fill"
        case .other: return "doc.fill"
        }
    }
    
    static func < (lhs: FileCategory, rhs: FileCategory) -> Bool {
        let order: [FileCategory] = [.folder, .images, .videos, .audio, .documents, .archives, .apps, .developer, .other]
        let idx1 = order.firstIndex(of: lhs) ?? 99
        let idx2 = order.firstIndex(of: rhs) ?? 99
        return idx1 < idx2
    }
}

enum FinderViewMode: String, CaseIterable, Identifiable, Sendable {
    case list = "Liste"
    case icons = "Symbole"
    case columns = "Spalten"
    case gallery = "Kacheln"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .icons: return "square.grid.3x3.fill"
        case .columns: return "rectangle.split.3x1"
        case .gallery: return "rectangle.grid.2x2.fill"
        }
    }
}

enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case name = "Name"
    case size = "Größe"
    case date = "Änderungsdatum"
    case category = "Kategorie / Art"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .size: return "arrow.up.and.down"
        case .date: return "calendar"
        case .category: return "square.grid.2x2"
        }
    }
}

struct StorageItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let creationDate: Date?
    let modificationDate: Date?
    
    var name: String {
        url.lastPathComponent
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var formattedDate: String {
        guard let date = modificationDate else { return "Unbekannt" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedCreationDate: String {
        guard let date = creationDate else { return "Unbekannt" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var kindDescription: String {
        if isDirectory {
            let ext = url.pathExtension.lowercased()
            if ext == "app" { return "macOS Anwendung" }
            return "Ordner"
        }
        let ext = url.pathExtension.uppercased()
        if ext.isEmpty { return "Datei" }
        return "\(ext)-Datei"
    }
    
    var category: FileCategory {
        if isDirectory {
            let ext = url.pathExtension.lowercased()
            if ["app", "framework", "bundle", "plugin"].contains(ext) {
                return .apps
            }
            return .folder
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "svg", "raw", "cr2", "nef":
            return .images
        case "mp4", "mov", "mkv", "avi", "m4v", "wmv", "flv", "webm":
            return .videos
        case "mp3", "wav", "m4a", "flac", "aac", "aiff", "ogg":
            return .audio
        case "pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "txt", "rtf", "pages", "numbers", "keynote", "csv", "md":
            return .documents
        case "zip", "tar", "gz", "bz2", "7z", "rar", "dmg", "iso", "pkg":
            return .archives
        case "app":
            return .apps
        case "swift", "h", "m", "c", "cpp", "py", "js", "ts", "json", "xml", "plist", "xcarchive", "xcodeproj", "xcworkspace":
            return .developer
        default:
            return .other
        }
    }
}

// MARK: - Array Sorting Extension

extension Array where Element == StorageItem {
    func sorted(by option: SortOption, ascending: Bool) -> [StorageItem] {
        return self.sorted { a, b in
            switch option {
            case .name:
                let cmp = a.name.localizedStandardCompare(b.name)
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            case .size:
                return ascending ? (a.size < b.size) : (a.size > b.size)
            case .date:
                let dateA = a.modificationDate ?? Date.distantPast
                let dateB = b.modificationDate ?? Date.distantPast
                return ascending ? (dateA < dateB) : (dateA > dateB)
            case .category:
                if a.category == b.category {
                    return a.size > b.size
                }
                return ascending ? (a.category < b.category) : (a.category > b.category)
            }
        }
    }
}

// MARK: - Global Finder View Mode Synchronization

extension FinderViewMode {
    public static let didChangeNotification = Notification.Name("FinderViewModeDidChange")
    
    public static var shared: FinderViewMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: "iSweep_global_finderViewMode"),
               let mode = FinderViewMode(rawValue: raw) {
                return mode
            }
            return .columns
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "iSweep_global_finderViewMode")
            NotificationCenter.default.post(name: didChangeNotification, object: newValue)
        }
    }
}
