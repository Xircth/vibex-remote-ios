import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(light: Color(red: 0.950, green: 0.955, blue: 0.965), dark: Color(red: 0.039, green: 0.043, blue: 0.051))
    static let bgElevated = Color(light: .white, dark: Color(red: 0.078, green: 0.085, blue: 0.098))
    static let surfaceStroke = Color(light: .black.opacity(0.10), dark: .white.opacity(0.09))
    static let hairline = Color(light: .black.opacity(0.07), dark: .white.opacity(0.055))
    static let codeSurface = Color(light: .black.opacity(0.045), dark: .black.opacity(0.30))
    static let rail = Color(light: .black.opacity(0.20), dark: .white.opacity(0.16))
    static let surface = Color.primary.opacity(0.05)
    static let surfaceNested = Color.primary.opacity(0.035)
    static let textPrimary = Color(light: Color(white: 0.11), dark: Color(white: 0.97))
    static let textSecondary = Color(light: Color(white: 0.38), dark: Color(white: 0.64))
    static let textTertiary = Color(light: Color(white: 0.55), dark: Color(white: 0.44))
    static let danger = Color(light: Color(red: 0.80, green: 0.18, blue: 0.18), dark: Color(red: 0.96, green: 0.46, blue: 0.46))
    static let warning = Color(light: Color(red: 0.80, green: 0.54, blue: 0.06), dark: Color(red: 0.96, green: 0.74, blue: 0.36))
    static let pass = Color(light: Color(red: 0.13, green: 0.52, blue: 0.31), dark: Color(red: 0.55, green: 0.90, blue: 0.62))
    static let accent = Color(UIColor { tc in UIColor(tc.accentPalette.fill(dark: tc.userInterfaceStyle != .light)) })
    static let onAccent = Color(UIColor { tc in UIColor(tc.accentPalette.onColor(dark: tc.userInterfaceStyle != .light)) })
    static var accentDim: Color { accent.opacity(0.16) }

    enum Radius {
        static let xl: CGFloat = 26
        static let lg: CGFloat = 20
        static let md: CGFloat = 14
        static let sm: CGFloat = 10
    }

    enum Motion {
        static let chrome = Animation.snappy(duration: 0.24)
        static let content = Animation.smooth(duration: 0.26)
        static let expand = Animation.snappy(duration: 0.22)
        static let press = Animation.snappy(duration: 0.12)
        static let scroll = Animation.snappy(duration: 0.30)
    }

    enum Layout {
        static let screenHMargin: CGFloat = 16
        static let sectionSpacing: CGFloat = 20
        static let screenTopInset: CGFloat = 8
        static let screenBottomInset: CGFloat = 28
    }
}

enum AccentPalette: Int, CaseIterable, Identifiable {
    case mint = 0, blue = 1, indigo = 2, purple = 3, pink = 4, orange = 5, teal = 6, red = 7
    case neutral = 8, mocha = 9, butter = 10, dusk = 11
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .neutral: "Neutral"
        case .mint: "Mint"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .orange: "Orange"
        case .teal: "Teal"
        case .red: "Red"
        case .mocha: "Mocha"
        case .butter: "Butter"
        case .dusk: "Dusk"
        }
    }

    private var rgb: (dark: (Double, Double, Double), light: (Double, Double, Double)) {
        switch self {
        case .neutral: ((0.90, 0.91, 0.93), (0.16, 0.17, 0.20))
        case .mint: ((0.40, 0.88, 0.70), (0.06, 0.58, 0.42))
        case .blue: ((0.39, 0.66, 1.00), (0.00, 0.45, 0.92))
        case .indigo: ((0.56, 0.60, 0.99), (0.29, 0.31, 0.86))
        case .purple: ((0.76, 0.55, 1.00), (0.52, 0.26, 0.83))
        case .pink: ((1.00, 0.45, 0.71), (0.86, 0.16, 0.49))
        case .orange: ((1.00, 0.62, 0.30), (0.85, 0.42, 0.05))
        case .teal: ((0.30, 0.82, 0.86), (0.00, 0.52, 0.58))
        case .red: ((1.00, 0.45, 0.45), (0.82, 0.19, 0.20))
        case .mocha: ((0.82, 0.64, 0.54), (0.51, 0.36, 0.29))
        case .butter: ((0.98, 0.84, 0.42), (0.70, 0.53, 0.05))
        case .dusk: ((0.60, 0.55, 0.80), (0.35, 0.31, 0.54))
        }
    }

    func fill(dark: Bool) -> Color {
        let c = dark ? rgb.dark : rgb.light
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    func onColor(dark: Bool) -> Color {
        let c = dark ? rgb.dark : rgb.light
        let luminance = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
        return luminance > 0.6 ? Color(white: 0.06) : .white
    }
}

struct AccentPaletteTrait: UITraitDefinition {
    static let defaultValue = AccentPalette.neutral.rawValue
}

extension UITraitCollection {
    var accentPalette: AccentPalette {
        AccentPalette(rawValue: self[AccentPaletteTrait.self]) ?? .neutral
    }
}

struct CodegAccentKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue: AccentPalette = .neutral
    static func read(from traitCollection: UITraitCollection) -> AccentPalette { traitCollection.accentPalette }
    static func write(to mutableTraits: inout UIMutableTraits, value: AccentPalette) {
        mutableTraits[AccentPaletteTrait.self] = value.rawValue
    }
}

extension EnvironmentValues {
    var codegAccent: AccentPalette {
        get { self[CodegAccentKey.self] }
        set { self[CodegAccentKey.self] = newValue }
    }
}

extension Color {
    init(light: Color, dark: Color) {
        self = Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(light) : UIColor(dark) })
    }
}

extension View {
    func hairlineBorder(_ cornerRadius: CGFloat, color: Color = Theme.surfaceStroke) -> some View {
        overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(color, lineWidth: 0.75))
    }

    func companionGlass(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        modifier(CompanionGlassModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

private struct CompanionGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(Theme.bgElevated, in: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}
