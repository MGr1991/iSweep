import SwiftUI
#if os(macOS)
import AppKit
#endif

struct FolderScannerMainView: View {
    @StateObject private var viewModel = FolderScannerViewModel()
    @State private var showFileImporter = false
    @State private var itemToDelete: StorageItem?
    @State private var pathBarText: String = "" 
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
                    SidebarAppHeaderView(subtitle: "Speicher-Scanner")
                    SystemStorageGaugeView()
                }
                
                Section("Speicherfresser & Schnell-Scan") {
                    Button(action: {
                        showFileImporter = true
                    }) {
                        Label("Ordner auswählen…", systemImage: "folder.badge.plus")
                    }
                    
                    #if os(macOS)
                    Button(action: { scanSystemFolder(path: "~/Downloads") }) {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    Button(action: { scanSystemFolder(path: "~/Library/Developer/Xcode/DerivedData") }) {
                        Label("Xcode DerivedData", systemImage: "hammer")
                    }
                    Button(action: { scanSystemFolder(path: "~/Library/Caches") }) {
                        Label("System- & App-Caches", systemImage: "trash")
                    }
                    Button(action: { scanSystemFolder(path: "~/Library/Logs") }) {
                        Label("Diagnose-Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    Button(action: { scanSystemFolder(path: "~/Library/Application Support/MobileSync/Backup") }) {
                        Label("iOS Backups", systemImage: "iphone")
                    }
                    Button(action: { scanSystemFolder(path: "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads") }) {
                        Label("Mail-Anhänge", systemImage: "envelope")
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
                        Label(isSelectionMode ? "Auswahl beenden" : "Dateien auswählen", systemImage: isSelectionMode ? "checkmark.circle.fill" : "checklist")
                    }
                }
                
                #if os(macOS)
                SidebarTrashSectionView()
                #endif
                
                if let currentURL = viewModel.currentFolderURL {
                    Section("Aktueller Pfad") {
                        Text(currentURL.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Erneut scannen") {
                            viewModel.rescan()
                        }
                        .hoverGlowButton(cornerRadius: 6)
                    }
                }
                
                Section("Erscheinungsbild") {
                    ThemeSwitchView()
                }
            }
            .navigationTitle("Speicher-Scanner")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    AppHeaderIconView()
                }
            }
            .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 400)
        } detail: {
            VStack(spacing: 0) {
                FilePathBarView(
                    pathText: $pathBarText,
                    placeholder: "Ordner- oder Dateipfad eingeben (z. B. ~/Downloads oder ~/Library/Caches)...",
                    onCommitPath: { url in
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                            viewModel.scanFolder(url: url.deletingLastPathComponent())
                        } else {
                            viewModel.scanFolder(url: url)
                        }
                    },
                    currentItemURL: viewModel.currentFolderURL
                )
                .onChange(of: viewModel.currentFolderURL) { newURL in
                    if let u = newURL {
                        pathBarText = u.path
                    }
                }
                .onAppear {
                    if let u = viewModel.currentFolderURL {
                        pathBarText = u.path
                    }
                }
                
                if viewModel.isScanning {
                    ProgressView("Scanne Dateien...")
                        .padding()
                } else if viewModel.items.isEmpty {
                    if #available(iOS 17.0, macOS 14.0, *) {
                        ContentUnavailableView(
                            "Keine Treffer",
                            systemImage: "folder.magnifyingglass",
                            description: Text("Es wurden keine passenden Dateien gefunden.")
                        )
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "folder.magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Keine Treffer")
                                .font(.title2.bold())
                            Text("Es wurden keine passenden Dateien gefunden.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                } else {
                    StorageChartView(items: viewModel.items)
                        .padding(.top)
                    
                    Divider()
                    
                    if viewModel.finderViewMode == .columns {
                        FinderColumnBrowserView(
                            rootItems: viewModel.sortedItems,
                            sortOption: viewModel.sortOption,
                            sortAscending: viewModel.sortAscending,
                            onDelete: { item in
                                itemToDelete = item
                            },
                            isSelectionMode: isSelectionMode,
                            selectedURLs: selectedURLs,
                            onToggleSelect: { item in
                                performMultiSelectClick(
                                    item: item,
                                    in: viewModel.sortedItems,
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
                    } else if viewModel.finderViewMode == .list {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(viewModel.sortedItems) { item in
                                    FinderListItemView(
                                        item: item,
                                        isSelectionMode: isSelectionMode,
                                        isSelected: selectedURLs.contains(item.url),
                                        onToggleSelect: {
                                            performMultiSelectClick(
                                                item: item,
                                                in: viewModel.sortedItems,
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
                                        onDelete: { itemToDelete = item }
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    } else if viewModel.finderViewMode == .icons {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 16)], spacing: 16) {
                                ForEach(viewModel.sortedItems) { item in
                                    FinderIconItemView(
                                        item: item,
                                        isSelectionMode: isSelectionMode,
                                        isSelected: selectedURLs.contains(item.url),
                                        onToggleSelect: {
                                            performMultiSelectClick(
                                                item: item,
                                                in: viewModel.sortedItems,
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
                                        onDelete: { itemToDelete = item }
                                    )
                                }
                            }
                            .padding()
                        }
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 12)], spacing: 12) {
                                ForEach(viewModel.sortedItems) { item in
                                    FinderCardItemView(
                                        item: item,
                                        isSelectionMode: isSelectionMode,
                                        isSelected: selectedURLs.contains(item.url),
                                        onToggleSelect: {
                                            performMultiSelectClick(
                                                item: item,
                                                in: viewModel.sortedItems,
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
                                        onDelete: { itemToDelete = item }
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                }
                
                if isSelectionMode {
                    let selectedItems = viewModel.sortedItems.filter { selectedURLs.contains($0.url) }
                    let totalBytes = selectedItems.reduce(Int64(0)) { $0 + $1.size }
                    let formatter = ByteCountFormatter()
                    let sizeStr = formatter.string(fromByteCount: totalBytes)
                    
                    BatchSelectionActionBar(
                        selectedCount: selectedURLs.count,
                        totalSizeText: sizeStr,
                        allSelected: !viewModel.sortedItems.isEmpty && selectedURLs.count == viewModel.sortedItems.count,
                        onToggleSelectAll: {
                            if selectedURLs.count == viewModel.sortedItems.count {
                                selectedURLs.removeAll()
                            } else {
                                selectedURLs = Set(viewModel.sortedItems.map { $0.url })
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
            .navigationTitle(viewModel.currentFolderURL?.lastPathComponent ?? "Details")
            .searchable(text: $viewModel.searchText, prompt: "Dateien filtern…")
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    TrashQuickBarButton()
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        ApplePencilManager.shared.showPencilCanvasSheet = true
                    } label: {
                        Label("Pencil Notizen", systemImage: "pencil.tip.crop.circle")
                    }
                }
                #endif

                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        MacTrashManager.shared.promptEmptyTrash()
                    } label: {
                        Label("Papierkorb leeren", systemImage: "trash.slash.fill")
                    }
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
                                    if viewModel.sortOption == .name {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                viewModel.setSort(.size)
                            } label: {
                                HStack {
                                    Text("Größe")
                                    if viewModel.sortOption == .size {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                viewModel.setSort(.date)
                            } label: {
                                HStack {
                                    Text("Änderungsdatum")
                                    if viewModel.sortOption == .date {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                viewModel.setSort(.category)
                            } label: {
                                HStack {
                                    Text("Kategorie / Art")
                                    if viewModel.sortOption == .category {
                                        Image(systemName: "checkmark")
                                    }
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
                                    if viewModel.sortAscending {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                viewModel.sortAscending = false
                            } label: {
                                HStack {
                                    Text(viewModel.sortOption == .size ? "Größte zuerst" : (viewModel.sortOption == .date ? "Neueste zuerst" : "Absteigend (Z-A)"))
                                    if !viewModel.sortAscending {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Section("Gruppierung") {
                            Button {
                                viewModel.groupByKind.toggle()
                            } label: {
                                HStack {
                                    Text("Nach Art gruppieren")
                                    if viewModel.groupByKind {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Sortieren", systemImage: "arrow.up.arrow.down")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Dateitypen") {
                            ForEach(FilterType.allCases) { filter in
                                Button {
                                    viewModel.filterType = filter
                                } label: {
                                    HStack {
                                        Text(filter.rawValue)
                                        if viewModel.filterType == filter {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Section("Scan-Ebene") {
                            Button {
                                viewModel.viewMode = .hierarchical
                                viewModel.rescan()
                            } label: {
                                HStack {
                                    Text("Hierarchisch (Ordner)")
                                    if viewModel.viewMode == .hierarchical {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                viewModel.viewMode = .flat
                                viewModel.rescan()
                            } label: {
                                HStack {
                                    Text("Flache Liste (Alle Dateien)")
                                    if viewModel.viewMode == .flat {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.scanFolder(url: url)
                }
            case .failure(let error):
                viewModel.errorMessage = "Fehler bei der Ordnerauswahl: \(error.localizedDescription)"
                viewModel.showError = true
            }
        }
        .alert(isPresented: $viewModel.showError) {
            Alert(
                title: Text("Fehler"),
                message: Text(viewModel.errorMessage ?? "Unbekannter Fehler"),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Möchtest du '\(itemToDelete?.name ?? "")' wirklich löschen?",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let item = itemToDelete {
                    viewModel.deleteItem(item)
                    itemToDelete = nil
                }
            }
            Button("Abbrechen", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("Das Element belegt \(itemToDelete?.formattedSize ?? "") Speicherplatz. Dieser Vorgang kann nicht rückgängig gemacht werden.")
        }
        .confirmationDialog(
            "Möchtest du \(selectedURLs.count) ausgewählte Elemente wirklich löschen?",
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
            let selectedItems = viewModel.sortedItems.filter { selectedURLs.contains($0.url) }
            let totalBytes = selectedItems.reduce(Int64(0)) { $0 + $1.size }
            let formatter = ByteCountFormatter()
            let sizeStr = formatter.string(fromByteCount: totalBytes)
            Text("Gesamtgröße: \(sizeStr). Die \(selectedURLs.count) Elemente werden in den Papierkorb verschoben.")
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            columnVisibility = .all
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
    private func renderCollection(items: [StorageItem]) -> some View {
        switch viewModel.finderViewMode {
        case .list:
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    FinderListItemView(
                        item: item,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedURLs.contains(item.url),
                        onToggleSelect: { toggleSelection(for: item.url) },
                        onDelete: { itemToDelete = item }
                    )
                }
            }
            .padding(.horizontal)
        case .icons:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 16)], spacing: 16) {
                ForEach(items) { item in
                    FinderIconItemView(
                        item: item,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedURLs.contains(item.url),
                        onToggleSelect: { toggleSelection(for: item.url) },
                        onDelete: { itemToDelete = item }
                    )
                }
            }
            .padding(.horizontal)
        case .columns:
            FinderColumnBrowserView(
                rootItems: items,
                sortOption: viewModel.sortOption,
                sortAscending: viewModel.sortAscending,
                onDelete: { itemToDelete = $0 },
                onItemSelected: { item in
                    pathBarText = item.url.path
                },
                isSelectionMode: isSelectionMode,
                selectedURLs: selectedURLs,
                onToggleSelect: { item in
                    toggleSelection(for: item.url)
                }
            )
        case .gallery:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    FinderCardItemView(
                        item: item,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedURLs.contains(item.url),
                        onToggleSelect: { toggleSelection(for: item.url) },
                        onDelete: { itemToDelete = item }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    #if os(macOS)
    private func scanSystemFolder(path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        viewModel.scanFolder(url: url)
    }
    #endif
}
