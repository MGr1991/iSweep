import SwiftUI

#if canImport(AppKit)
import AppKit
typealias SystemColor = NSColor
#elseif canImport(UIKit)
import UIKit
typealias SystemColor = UIColor
#endif

// MARK: - Theme Mode

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }
    
    var titleDescription: String {
        switch self {
        case .system: return "Systemstandard"
        case .light: return "Hellmodus"
        case .dark: return "Dunkelmodus"
        }
    }
    
    var subtitleDescription: String {
        switch self {
        case .system: return "Folgt Systemeinstellung"
        case .light: return "Helles Design erzwungen"
        case .dark: return "Dunkles Design erzwungen"
        }
    }
    
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Theme Manager

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @AppStorage("selectedThemeMode") var rawThemeMode: String = AppThemeMode.system.rawValue {
        didSet {
            #if os(macOS)
            updateAppearance()
            #endif
            objectWillChange.send()
        }
    }
    
    var themeMode: AppThemeMode {
        get {
            AppThemeMode(rawValue: rawThemeMode) ?? .system
        }
        set {
            rawThemeMode = newValue.rawValue
        }
    }
    
    var colorScheme: ColorScheme? {
        themeMode.colorScheme
    }
    
    init() {
        #if os(macOS)
        DispatchQueue.main.async { [weak self] in
            self?.updateAppearance()
        }
        #endif
    }
    
    #if os(macOS)
    func updateAppearance() {
        switch themeMode {
        case .system:
            NSApp?.appearance = nil
        case .light:
            NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
    #endif
}

// MARK: - Theme Switch View

struct ThemeSwitchView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: themeManager.themeMode.iconName)
                    .foregroundColor(iconColor)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(themeManager.themeMode.titleDescription)
                        .font(.subheadline)
                    Text(themeManager.themeMode.subtitleDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Picker("Erscheinungsbild", selection: $themeManager.themeMode) {
                ForEach(AppThemeMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.iconName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
    
    private var iconColor: Color {
        switch themeManager.themeMode {
        case .system:
            return .accentColor
        case .light:
            return .orange
        case .dark:
            return .purple
        }
    }
}

// MARK: - Theme Helper

struct ThemeHelper {
    static var secondaryBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
    
    static var primaryBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}

// MARK: - Hover Glow Visual Effects

struct HoverGlowRowModifier: ViewModifier {
    @State private var isHovered = false
    var cornerRadius: CGFloat = 8
    var glowColor: Color = Color.accentColor
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? glowColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isHovered ? glowColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .shadow(color: isHovered ? glowColor.opacity(0.3) : Color.clear, radius: isHovered ? 5 : 0)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.18)) {
                    isHovered = hovering
                }
            }
    }
}

struct HoverGlowTrashModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(isHovered ? .red : .secondary)
            .scaleEffect(isHovered ? 1.2 : 1.0)
            .padding(6)
            .background(
                Circle()
                    .fill(isHovered ? Color.red.opacity(0.2) : Color.clear)
            )
            .shadow(color: isHovered ? Color.red.opacity(0.7) : Color.clear, radius: isHovered ? 6 : 0)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

struct HoverGlowButtonModifier: ViewModifier {
    @State private var isHovered = false
    var glowColor: Color = Color.accentColor
    var cornerRadius: CGFloat = 8
    var scale: CGFloat = 1.03
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .shadow(color: isHovered ? glowColor.opacity(0.7) : Color.clear, radius: isHovered ? 8 : 0)
            .brightness(isHovered ? 0.08 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isHovered ? glowColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func hoverGlowRow(color: Color = Color.accentColor, cornerRadius: CGFloat = 8) -> some View {
        self.modifier(HoverGlowRowModifier(cornerRadius: cornerRadius, glowColor: color))
    }
    
    func hoverGlowTrash() -> some View {
        self.modifier(HoverGlowTrashModifier())
    }
    
    func hoverGlowButton(color: Color = Color.accentColor, cornerRadius: CGFloat = 8, scale: CGFloat = 1.03) -> some View {
        self.modifier(HoverGlowButtonModifier(glowColor: color, cornerRadius: cornerRadius, scale: scale))
    }
}
