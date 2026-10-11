import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
import PencilKit
#endif

// MARK: - Keyboard Modifier Tracker (macOS)

#if os(macOS)
@MainActor
final class KeyboardModifierTracker: ObservableObject {
    static let shared = KeyboardModifierTracker()
    
    @Published var isShiftPressed: Bool = false
    @Published var isCommandPressed: Bool = false
    
    private var monitor: Any?
    
    init() {
        self.isShiftPressed = NSEvent.modifierFlags.contains(.shift)
        self.isCommandPressed = NSEvent.modifierFlags.contains(.command)
        
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let shift = flags.contains(.shift)
            let cmd = flags.contains(.command)
            DispatchQueue.main.async {
                self?.isShiftPressed = shift
                self?.isCommandPressed = cmd
            }
            return event
        }
    }
    
    var currentIsShift: Bool {
        isShiftPressed || NSEvent.modifierFlags.contains(.shift) || (NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
    }
    
    var currentIsCommand: Bool {
        isCommandPressed || NSEvent.modifierFlags.contains(.command) || (NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
    }
}
#endif

// MARK: - Apple Pencil Support (iPadOS)

#if !os(macOS)
@MainActor
final class ApplePencilManager: NSObject, ObservableObject, UIPencilInteractionDelegate {
    static let shared = ApplePencilManager()
    
    @Published var isPencilModeActive: Bool = false
    @Published var hudNoticeText: String? = nil
    @Published var showHUDNotice: Bool = false
    @Published var showPencilCanvasSheet: Bool = false
    
    override init() {
        super.init()
    }
    
    nonisolated func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            
            NotificationCenter.default.post(name: .toggleMultiSelectionMode, object: nil)
            self.isPencilModeActive.toggle()
            let notice = self.isPencilModeActive ? "✏️ Apple Pencil: Auswahlmodus aktiviert" : "✏️ Apple Pencil: Normaler Modus"
            self.presentNotice(notice)
        }
    }
    
    @available(iOS 17.5, *)
    nonisolated func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            self.showPencilCanvasSheet.toggle()
            let notice = self.showPencilCanvasSheet ? "✏️ Apple Pencil Pro: Notizen geöffnet" : "✏️ Notizen geschlossen"
            self.presentNotice(notice)
        }
    }
    
    func presentNotice(_ text: String) {
        self.hudNoticeText = text
        withAnimation(.spring()) {
            self.showHUDNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.hudNoticeText == text {
                withAnimation(.easeOut) {
                    self.showHUDNotice = false
                }
            }
        }
    }
}

struct ApplePencilInteractionBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let interaction = UIPencilInteraction()
        interaction.delegate = ApplePencilManager.shared
        view.addInteraction(interaction)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct ApplePencilHUDBanner: View {
    @ObservedObject var manager = ApplePencilManager.shared
    
    var body: some View {
        if manager.showHUDNotice, let text = manager.hudNoticeText {
            VStack {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.tip")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                    Text(text)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                
                Spacer()
            }
            .padding(.top, 8)
            .zIndex(999)
        }
    }
}

struct PencilKitCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @State private var toolPicker = PKToolPicker()
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

struct ApplePencilNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var canvasView = PKCanvasView()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                PencilKitCanvasView(canvasView: $canvasView)
                    .ignoresSafeArea()
            }
            .navigationTitle("Apple Pencil Notizen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Leeren") {
                        canvasView.drawing = PKDrawing()
                    }
                }
            }
        }
    }
}
#endif

// MARK: - Multi-Select Helper (Keyboard + Mouse + Touch)

@MainActor
func performMultiSelectClick(
    item: StorageItem,
    in pool: [StorageItem],
    selectedURLs: inout Set<URL>,
    lastSelectedURL: inout URL?,
    isSelectionMode: inout Bool
) {
    #if os(macOS)
    let isShift = KeyboardModifierTracker.shared.currentIsShift
    let isCommand = KeyboardModifierTracker.shared.currentIsCommand
    #else
    let isShift = false
    let isCommand = false
    #endif
    
    if isShift {
        isSelectionMode = true
        let anchorURL = lastSelectedURL ?? pool.first?.url ?? item.url
        if let fromIdx = pool.firstIndex(where: { $0.url == anchorURL }),
           let toIdx = pool.firstIndex(where: { $0.url == item.url }) {
            let range = min(fromIdx, toIdx)...max(fromIdx, toIdx)
            for i in range {
                selectedURLs.insert(pool[i].url)
            }
        } else {
            selectedURLs.insert(item.url)
        }
        lastSelectedURL = item.url
    } else if isCommand {
        isSelectionMode = true
        if selectedURLs.contains(item.url) {
            selectedURLs.remove(item.url)
        } else {
            selectedURLs.insert(item.url)
        }
        lastSelectedURL = item.url
    } else if isSelectionMode {
        if selectedURLs.contains(item.url) {
            selectedURLs.remove(item.url)
        } else {
            selectedURLs.insert(item.url)
        }
        lastSelectedURL = item.url
    } else {
        lastSelectedURL = item.url
    }
}
