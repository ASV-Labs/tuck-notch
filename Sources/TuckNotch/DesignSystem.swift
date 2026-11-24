import SwiftUI
import AppKit
import os

/// Design tokens. Exterior is always pure black so the island merges with the hardware notch;
/// interior surfaces and text step up in contrast when Increase Contrast is on.
enum DS {
    static var highContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }

    /// Opacity of the open island's background. Forced solid for Reduce Transparency / Increase Contrast.
    static var panelAlpha: Double {
        (reduceTransparency || highContrast) ? 1 : min(1, max(0.3, settings.panelOpacity))
    }
    /// Cards fade a little less than the panel so text on them stays readable.
    static var cardAlpha: Double { 0.35 + 0.65 * panelAlpha }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private static var settings: AppSettings { AppSettings.shared }

    /// Mixes a base grey with the accent for the "Tinted" surface style.
    private static func tinted(_ hex: UInt32, _ fraction: CGFloat) -> Color {
        let base = NSColor(Color(hex: hex))
        let accent = NSColor(settings.accent.color)
        return Color(nsColor: base.blended(withFraction: fraction, of: accent) ?? base)
    }

    private static func surfaceColor(graphite: UInt32, black: UInt32, tint: CGFloat) -> Color {
        switch settings.surface {
        case .graphite: return Color(hex: graphite)
        case .black: return Color(hex: black)
        case .tinted: return tinted(graphite, tint)
        }
    }

    enum Palette {
        static let exterior = Color.black
        static var surface: Color {
            highContrast ? Color(hex: 0x1F1F1F) : surfaceColor(graphite: 0x171717, black: 0x0B0B0B, tint: 0.10)
        }
        static var elevated: Color {
            highContrast ? Color(hex: 0x3A3A3A) : surfaceColor(graphite: 0x282828, black: 0x1A1A1A, tint: 0.16)
        }
        static var elevatedPressed: Color {
            highContrast ? Color(hex: 0x4A4A4A) : surfaceColor(graphite: 0x333333, black: 0x262626, tint: 0.22)
        }
        static var textPrimary: Color { highContrast ? .white : Color(hex: 0xF5F5F7) }
        static var textSecondary: Color { Color(hex: highContrast ? 0xD4D4D8 : 0xA1A1AA) }
        static var separator: Color { Color.white.opacity(highContrast ? 0.35 : 0.08) }
        static var stroke: Color { Color.white.opacity(highContrast ? 0.45 : 0.0) }
        static var accent: Color { settings.accent.color }
        /// Colour of live activities (timer, progress, wings).
        static var live: Color { settings.activityColor.color }
        static let success = Color(hex: 0x30D158)
        static let warning = Color(hex: 0xFFD60A)
        static let danger = Color(hex: 0xFF453A)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static var control: CGFloat { settings.corners.control }
        static var card: CGFloat { settings.corners.card }
        static var panel: CGFloat { settings.corners.panel }
        static let flare: CGFloat = 6
    }

    enum Size {
        static let hit: CGFloat = 28
        static var expandedWidth: CGFloat { settings.panelSize.width }
        static var expandedContentHeight: CGFloat {
            settings.panelSize.contentHeight + (settings.textSize == .large ? 20 : 0)
        }
        static let peekWidth: CGFloat = 450
        static let attentionWidth: CGFloat = 470
        static let tabBarHeight: CGFloat = 36
    }

    enum Typeface {
        private static var d: CGFloat { settings.textSize.delta }
        static var title: Font { .system(size: 15 + d, weight: .semibold) }
        static var body: Font { .system(size: 13 + d) }
        static var bodyMedium: Font { .system(size: 13 + d, weight: .medium) }
        static var caption: Font { .system(size: 11 + d) }
        static var captionMedium: Font { .system(size: 11 + d, weight: .medium) }
        static var metric: Font { .system(size: 22 + d, weight: .semibold, design: .rounded) }
        static var display: Font { .system(size: 34 + d, weight: .semibold, design: .rounded) }
    }

    enum Motion {
        /// ~250 ms spring; a short fade when Reduce Motion is on.
        static var island: Animation {
            if reduceMotion { return .easeInOut(duration: 0.18) }
            switch settings.motion {
            case .spring: return .spring(response: 0.3, dampingFraction: 0.86)
            case .smooth: return .easeInOut(duration: 0.26)
            case .minimal: return .easeOut(duration: 0.14)
            }
        }
        static var content: Animation {
            reduceMotion || settings.motion == .minimal ? .linear(duration: 0.12) : .easeOut(duration: 0.2)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// A card surface used throughout the panels.
struct Card<Content: View>: View {
    var padding: CGFloat = DS.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface.opacity(DS.cardAlpha))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Palette.stroke, lineWidth: 1)
            )
    }
}

/// Structured logging (Console.app, subsystem com.asvlabs.tucknotch).
enum Log {
    static let app = Logger(subsystem: "com.asvlabs.tucknotch", category: "app")
    static let activity = Logger(subsystem: "com.asvlabs.tucknotch", category: "activity")
    static let media = Logger(subsystem: "com.asvlabs.tucknotch", category: "media")
    static let inbox = Logger(subsystem: "com.asvlabs.tucknotch", category: "inbox")
    static let audio = Logger(subsystem: "com.asvlabs.tucknotch", category: "audio")
}


/// Frosts what's behind the window (desktop, other apps) under a translucent island. Its own
/// strength follows the opacity slider, so low opacity stays mostly clear even when frosted.
struct BehindWindowBlur: NSViewRepresentable {
    var strength: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.alphaValue = strength
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { nsView.alphaValue = strength }
}
