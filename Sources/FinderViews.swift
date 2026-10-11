import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Finder-Style Item Views

struct FinderListItemView: View {
    let item: StorageItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    let onDelete: () -> Void
    @State private var showInspector = false
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Button(action: { onToggleSelect?() }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            #if os(macOS)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            #else
            Image(systemName: item.category.iconName)
                .font(.title3)
                .foregroundColor(item.isDirectory ? .blue : .secondary)
            #endif
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.category.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.formattedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(item.formattedSize)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            if !isSelectionMode {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .hoverGlowTrash()
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleSelect?()
        }
        #if !os(macOS)
        .onLongPressGesture {
            onLongPress?()
        }
        #endif
        .hoverGlowRow()
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(6)
        .padding(.vertical, 2)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Löschen", systemImage: "trash")
            }
            Button {
                showInspector = true
            } label: {
                Label("Informationen", systemImage: "info.circle")
            }
            #if os(macOS)
            Button {
                NSWorkspace.shared.open(item.url)
            } label: {
                Label("Öffnen / Vorschau", systemImage: "arrow.up.right.square")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label("Im Finder zeigen", systemImage: "magnifyingglass")
            }
            #endif
        }
        .sheet(isPresented: $showInspector) {
            StorageItemInspectorView(item: item)
        }
    }
}

struct FinderIconItemView: View {
    let item: StorageItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    let onDelete: () -> Void
    @State private var isHovered = false
    @State private var showInspector = false
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                #if os(macOS)
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                #else
                Image(systemName: item.category.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundColor(item.isDirectory ? .blue : .accentColor)
                #endif
                
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                        .offset(x: 8, y: -6)
                } else {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash.circle.fill")
                            .font(.body)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .hoverGlowTrash()
                    .offset(x: 8, y: -6)
                }
            }
            .frame(height: 52)
            
            Text(item.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 100)
            
            Text(item.formattedSize)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if !isSelectionMode {
                Button(role: .destructive, action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Löschen")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .hoverGlowButton(color: .red, cornerRadius: 5)
            } else {
                Text(isSelected ? "Ausgewählt" : "Wählen")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .padding(.vertical, 3)
            }
        }
        .frame(width: 115, height: 145)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.accentColor.opacity(0.12) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.35) : Color.clear), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? Color.accentColor.opacity(0.25) : Color.clear), radius: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleSelect?()
        }
        #if !os(macOS)
        .onLongPressGesture {
            onLongPress?()
        }
        #endif
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Löschen", systemImage: "trash")
            }
            Button {
                showInspector = true
            } label: {
                Label("Informationen", systemImage: "info.circle")
            }
            #if os(macOS)
            Button {
                NSWorkspace.shared.open(item.url)
            } label: {
                Label("Öffnen / Vorschau", systemImage: "arrow.up.right.square")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label("Im Finder zeigen", systemImage: "magnifyingglass")
            }
            #endif
        }
        .sheet(isPresented: $showInspector) {
            StorageItemInspectorView(item: item)
        }
    }
}

struct FinderCardItemView: View {
    let item: StorageItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Button(action: { onToggleSelect?() }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            #if os(macOS)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
            #else
            Image(systemName: item.category.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundColor(item.isDirectory ? .blue : .accentColor)
            #endif
            
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(item.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                    
                    Text(item.formattedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(item.formattedSize)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            
            Spacer()
            
            if !isSelectionMode {
                Button(role: .destructive, action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.caption)
                        Text("Löschen")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .hoverGlowButton(color: .red, cornerRadius: 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleSelect?()
        }
        #if !os(macOS)
        .onLongPressGesture {
            onLongPress?()
        }
        #endif
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : ThemeHelper.secondaryBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(10)
        .hoverGlowRow(cornerRadius: 10)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Löschen", systemImage: "trash")
            }
            #if os(macOS)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label("Im Finder zeigen", systemImage: "magnifyingglass")
            }
            #endif
        }
    }
}

struct AppIconItemView: View {
    let app: StorageItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    let onUninstall: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                #if os(macOS)
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                #else
                Image(systemName: "app.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.blue)
                #endif
                
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                        .offset(x: 8, y: -6)
                }
            }
            
            Text(app.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 110)
            
            if !isSelectionMode {
                Button(action: onUninstall) {
                    Text("Löschen")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .hoverGlowButton(color: .red, cornerRadius: 6)
            } else {
                Text(isSelected ? "Ausgewählt" : "Wählen")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .padding(.vertical, 4)
            }
        }
        .frame(width: 120, height: 135)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.accentColor.opacity(0.12) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.35) : Color.clear), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? Color.accentColor.opacity(0.25) : Color.clear), radius: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleSelect?()
        }
        #if !os(macOS)
        .onLongPressGesture {
            onLongPress?()
        }
        #endif
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onUninstall) {
                Label("App & Reste löschen", systemImage: "trash")
            }
            #if os(macOS)
            Button {
                NSWorkspace.shared.open(app.url)
            } label: {
                Label("App starten / öffnen", systemImage: "arrow.up.right.square")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            } label: {
                Label("Im Finder zeigen", systemImage: "magnifyingglass")
            }
            #endif
        }
    }
}

struct AppCardItemView: View {
    let app: StorageItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    let onUninstall: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Button(action: { onToggleSelect?() }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            #if os(macOS)
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
            #else
            Image(systemName: "app.fill")
                .font(.system(size: 36))
                .foregroundColor(.blue)
            #endif
            
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(app.url.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if !isSelectionMode {
                Button(action: onUninstall) {
                    Text("App & Reste löschen")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .hoverGlowButton(color: .red, cornerRadius: 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleSelect?()
        }
        #if !os(macOS)
        .onLongPressGesture {
            onLongPress?()
        }
        #endif
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : ThemeHelper.secondaryBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(10)
        .hoverGlowRow(cornerRadius: 10)
        .contextMenu {
            Button(role: .destructive, action: onUninstall) {
                Label("App & Reste löschen", systemImage: "trash")
            }
            #if os(macOS)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            } label: {
                Label("Im Finder zeigen", systemImage: "magnifyingglass")
            }
            #endif
        }
    }
}

// MARK: - Finder-Style Column Browser (Miller Columns)

struct FinderColumnBrowserView: View {
    let rootItems: [StorageItem]
    let sortOption: SortOption
    let sortAscending: Bool
    let onDelete: (StorageItem) -> Void
    var childrenProvider: ((StorageItem) -> [StorageItem]?)? = nil
    var onItemSelected: ((StorageItem) -> Void)? = nil
    var isSelectionMode: Bool = false
    var selectedURLs: Set<URL> = []
    var onToggleSelect: ((StorageItem) -> Void)? = nil
    var onSelectRange: ((StorageItem, [StorageItem]) -> Void)? = nil
    
    // Tracks the chain of folders opened: [level 0 folder, level 1 folder, ...]
    @State private var folderChain: [StorageItem] = []
    // The leaf item selected (either a file or a bundle whose preview is shown)
    @State private var selectedLeafItem: StorageItem? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Level 0 Column (Root)
                    columnView(
                        items: rootItems.sorted(by: sortOption, ascending: sortAscending),
                        level: 0,
                        selectedItem: folderChain.first ?? (folderChain.isEmpty ? selectedLeafItem : nil),
                        onSelect: { item in
                            handleSelection(item: item, level: 0)
                        }
                    )
                    .id("col_0")
                    
                    // Child Columns for each open folder in folderChain
                    ForEach(0..<folderChain.count, id: \.self) { index in
                        let parentItem = folderChain[index]
                        let childItems = (childrenProvider?(parentItem) ?? getContents(of: parentItem.url))
                        let nextSelected = (index + 1 < folderChain.count) ? folderChain[index + 1] : ((index == folderChain.count - 1) ? selectedLeafItem : nil)
                        
                        Divider()
                        
                        columnView(
                            items: childItems.sorted(by: sortOption, ascending: sortAscending),
                            level: index + 1,
                            selectedItem: nextSelected,
                            onSelect: { item in
                                handleSelection(item: item, level: index + 1)
                            }
                        )
                        .id("col_\(index + 1)")
                    }
                    
                    // Preview Inspector Column (if a file or app is selected)
                    if let leaf = selectedLeafItem {
                        Divider()
                        
                        previewColumnView(item: leaf)
                            .id("preview_col")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .background(ThemeHelper.secondaryBackground.opacity(0.15))
            .onChange(of: folderChain.count) { newCount in
                withAnimation(.easeInOut(duration: 0.25)) {
                    if selectedLeafItem != nil {
                        proxy.scrollTo("preview_col", anchor: .trailing)
                    } else {
                        proxy.scrollTo("col_\(newCount)", anchor: .trailing)
                    }
                }
            }
            .onChange(of: selectedLeafItem) { leaf in
                if leaf != nil {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("preview_col", anchor: .trailing)
                    }
                }
            }
        }
    }
    
    private func handleSelection(item: StorageItem, level: Int) {
        onItemSelected?(item)
        let hasCustomChildren = (childrenProvider?(item) != nil)
        let isRegularDir = item.isDirectory && (item.category != .apps || childrenProvider == nil)
        
        if isRegularDir || hasCustomChildren {
            var newChain = Array(folderChain.prefix(level))
            newChain.append(item)
            folderChain = newChain
            selectedLeafItem = nil
        } else {
            folderChain = Array(folderChain.prefix(level))
            selectedLeafItem = item
        }
    }
    
    private func getContents(of url: URL) -> [StorageItem] {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        return entries.compactMap { itemURL -> StorageItem? in
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let size = (try? itemURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? 0
            let modDate = (try? itemURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let createDate = (try? itemURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            return StorageItem(url: itemURL, isDirectory: isDir, size: size, creationDate: createDate, modificationDate: modDate)
        }
    }
    
    // MARK: - Single Miller Column
    @ViewBuilder
    private func columnView(
        items: [StorageItem],
        level: Int,
        selectedItem: StorageItem?,
        onSelect: @escaping (StorageItem) -> Void
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if items.isEmpty {
                    Text("Leer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    ForEach(items) { item in
                        let isSelected = selectedItem?.url == item.url
                        let isBatchSelected = selectedURLs.contains(item.url)
                        let hasCustomChildren = (childrenProvider?(item) != nil)
                        let isDrillable = (item.isDirectory && item.category != .apps) || hasCustomChildren
                        
                        HStack(spacing: 6) {
                            if isSelectionMode {
                                Button {
                                    #if os(macOS)
                                    let isShift = KeyboardModifierTracker.shared.currentIsShift
                                    #else
                                    let isShift = false
                                    #endif
                                    if isShift {
                                        onSelectRange?(item, items)
                                    } else {
                                        onToggleSelect?(item)
                                    }
                                } label: {
                                    Image(systemName: isBatchSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundColor(isBatchSelected ? .accentColor : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Button {
                                #if os(macOS)
                                let isShift = KeyboardModifierTracker.shared.currentIsShift
                                let isCommand = KeyboardModifierTracker.shared.currentIsCommand
                                #else
                                let isShift = false
                                let isCommand = false
                                #endif
                                
                                if isShift {
                                    onSelectRange?(item, items)
                                } else if isCommand {
                                    onToggleSelect?(item)
                                } else if isSelectionMode {
                                    onToggleSelect?(item)
                                    onSelect(item)
                                } else {
                                    onSelectRange?(item, items)
                                    onSelect(item)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    #if os(macOS)
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 18, height: 18)
                                    #else
                                    Image(systemName: item.category.iconName)
                                        .font(.system(size: 14))
                                        .foregroundColor(item.isDirectory ? .blue : .secondary)
                                    #endif
                                    
                                    Text(item.name)
                                        .font(.subheadline)
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    
                                    Spacer()
                                    
                                    if isDrillable {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                    } else {
                                        Text(item.formattedSize)
                                            .font(.caption2)
                                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(role: .destructive) {
                                onDelete(item)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .hoverGlowTrash()
                            }
                            .buttonStyle(.plain)
                            .help("Löschen")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor : (isSelectionMode && isBatchSelected ? Color.accentColor.opacity(0.22) : Color.clear))
                        )
                        .hoverGlowRow(cornerRadius: 6)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(item)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            #if os(macOS)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: {
                                Label("Im Finder zeigen", systemImage: "magnifyingglass")
                            }
                            #endif
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .frame(width: 250)
    }
    
    // MARK: - Preview / Inspector Column
    @ViewBuilder
    private func previewColumnView(item: StorageItem) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Large Preview Image
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(ThemeHelper.secondaryBackground.opacity(0.5))
                    
                    #if os(macOS)
                    if item.category == .images, let nsImg = NSImage(contentsOf: item.url) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                            .padding(8)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .padding(16)
                    }
                    #else
                    if item.category == .images, let uiImg = UIImage(contentsOfFile: item.url.path) {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                            .padding(8)
                    } else {
                        Image(systemName: item.category.iconName)
                            .font(.system(size: 72))
                            .foregroundColor(.accentColor)
                            .padding(16)
                    }
                    #endif
                }
                .frame(width: 260, height: 200)
                
                // File Name
                VStack(spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    
                    Text(item.category.rawValue)
                        .font(.caption2.bold())
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(6)
                }
                .padding(.horizontal, 8)
                
                Divider()
                
                // Info Grid
                VStack(spacing: 8) {
                    infoRow(title: "Art", value: item.kindDescription)
                    infoRow(title: "Größe", value: item.formattedSize)
                    infoRow(title: "Erstellt", value: item.formattedCreationDate)
                    infoRow(title: "Geändert", value: item.formattedDate)
                    infoRow(title: "Pfad", value: item.url.path)
                }
                .padding(.horizontal, 8)
                
                Divider()
                
                // Action Buttons
                VStack(spacing: 10) {
                    #if os(macOS)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Label("Im Finder zeigen", systemImage: "magnifyingglass")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .hoverGlowButton(cornerRadius: 8)
                    #endif
                    
                    Button(role: .destructive) {
                        onDelete(item)
                    } label: {
                        Label("Löschen", systemImage: "trash.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .hoverGlowButton(color: .red, cornerRadius: 8)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .padding(.vertical, 12)
        }
        .frame(width: 290)
    }
    
    @ViewBuilder
    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(title == "Pfad" ? 4 : 1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}
