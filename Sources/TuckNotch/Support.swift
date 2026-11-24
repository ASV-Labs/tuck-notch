import AppKit
import SwiftUI

// MARK: - Notch geometry

struct NotchMetrics: Equatable {
    /// True when the screen has a physical camera housing.
    let hasNotch: Bool
    /// Width of the hardware notch (or the simulated pill on other displays).
    let width: CGFloat
    /// Height of the hardware notch / menu bar.
    let height: CGFloat
}

extension NSScreen {
    var notchMetrics: NotchMetrics {
        if safeAreaInsets.top > 0,
           let left = auxiliaryTopLeftArea,
           let right = auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchMetrics(hasNotch: true, width: max(width, 150), height: safeAreaInsets.top)
        }
        // No notch: draw a floating pill the height of the menu bar.
        let menuBar = frame.maxY - visibleFrame.maxY
        let height = menuBar > 18 ? min(menuBar, 32) : 24
        return NotchMetrics(hasNotch: false, width: 180, height: height)
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 }

    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

// MARK: - Notch shape

/// The island outline: flat top that flares into the menu bar, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, rect.height - t)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Accessibility

@MainActor
enum A11y {
    /// Ask VoiceOver to speak a short status update (the macOS equivalent of a live region).
    static func announce(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var islandAnimation: Animation { DS.Motion.island }
}

// MARK: - Shared styling

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    /// Tighter padding for buttons inside Home cards.
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typeface.bodyMedium)
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.black : DS.Palette.textPrimary)
            .padding(.horizontal, compact ? DS.Space.s : DS.Space.m)
            .frame(minHeight: DS.Size.hit)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(prominent
                          ? Color.white.opacity(configuration.isPressed ? 0.75 : 0.95)
                          : (configuration.isPressed ? DS.Palette.elevatedPressed : DS.Palette.elevated))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(DS.Palette.stroke, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = DS.Size.hit
    var active = false
    var tint: Color? = nil
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(tint ?? (active ? DS.Palette.textPrimary : DS.Palette.textSecondary))
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? DS.Palette.elevatedPressed
                          : (active ? DS.Palette.elevated : Color.clear))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

enum Format {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func ago(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 10 { return "now" }
        return relative.localizedString(for: date, relativeTo: Date())
    }
}


// MARK: - Host matching

enum HostMatch {
    /// True when `host` is `domain` or a subdomain of it ("evilzoom.us" does not match "zoom.us").
    static func host(_ host: String, isOrIsUnder domain: String) -> Bool {
        let h = host.lowercased(), d = domain.lowercased()
        return h == d || h.hasSuffix("." + d)
    }

    static func host(_ host: String, isOrIsUnderAnyOf domains: [String]) -> Bool {
        domains.contains { self.host(host, isOrIsUnder: $0) }
    }
}
