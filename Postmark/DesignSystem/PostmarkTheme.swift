//
//  PostmarkTheme.swift
//  Postmark
//
//  Triage Deck design system: adaptive color tokens, typography, and
//  shared surface styling. Mirrors the Claude Design "Postmark Flows"
//  spec — warm neutral surfaces, a single confident violet accent, and
//  a coral archive affordance, in both light and dark.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Color tokens

extension Color {
    /// Page background behind the deck.
    static let pmBackground = Color.pmAdaptive(light: 0xFBFAF8, dark: 0x16161B)
    /// Raised card / sheet surface.
    static let pmSurface = Color.pmAdaptive(light: 0xFFFFFF, dark: 0x222229)
    /// Secondary fill (chips, icon wells, soft buttons).
    static let pmSoft = Color.pmAdaptive(light: 0xF4F2EC, dark: 0x1F1F26)
    /// Primary text.
    static let pmInk = Color.pmAdaptive(light: 0x191A1E, dark: 0xF4F3F0)
    /// Secondary text.
    static let pmMuted = Color.pmAdaptive(light: 0x74757E, dark: 0x9A9AA2)
    /// Tertiary text / timestamps.
    static let pmFaint = Color.pmAdaptive(light: 0xA6A7AE, dark: 0x6B6B73)
    /// Hairline borders.
    static let pmLine = Color.pmAdaptive(light: 0xECECE6, dark: 0x2C2C35)
    /// Confident violet accent.
    static let pmAccent = Color.pmAdaptive(light: 0x5B4DF0, dark: 0x8B7EFF)
    /// Coral — the archive affordance.
    static let pmCoral = Color.pmAdaptive(light: 0xFF6B5E, dark: 0xFF7E73)
    /// Success green.
    static let pmOk = Color.pmAdaptive(light: 0x1F9D6B, dark: 0x34C28A)
    /// Warning amber.
    static let pmWarn = Color.pmAdaptive(light: 0xE0913B, dark: 0xF0A85A)

    static var pmAccentSoft: Color { pmAccent.opacity(0.12) }
    static var pmCoralSoft: Color { pmCoral.opacity(0.13) }
    static var pmOkSoft: Color { pmOk.opacity(0.13) }

    /// Avatar palette — stable, characterful tints keyed off the sender.
    static let pmAvatarPalette: [Color] = [
        Color(hex: 0x5B4DF0), Color(hex: 0xE0613C), Color(hex: 0x2BB6A3),
        Color(hex: 0x5E6AD2), Color(hex: 0x635BFF), Color(hex: 0xC2557B),
        Color(hex: 0x3B8C5A), Color(hex: 0xB8702E)
    ]

    static func pmAvatar(for seed: String) -> Color {
        let hash = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return pmAvatarPalette[abs(hash) % pmAvatarPalette.count]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Builds a color that resolves differently in light vs dark appearance.
    static func pmAdaptive(light: UInt32, dark: UInt32) -> Color {
#if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(
                from: [.darkAqua, .aqua]
            ) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
#else
        return Color(hex: light)
#endif
    }
}

#if canImport(AppKit)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

// MARK: - Typography

/// Resolves the bundled display/body type with graceful fallback to the
/// system font when the custom faces are unavailable.
enum PMFont {
    private static let displayFamilyCandidates = [
        "Bricolage Grotesque", "BricolageGrotesque"
    ]
    private static let bodyFamilyCandidates = [
        "Schibsted Grotesk", "SchibstedGrotesk"
    ]

    private static let displayFamily: String? =
        firstAvailable(displayFamilyCandidates)
    private static let bodyFamily: String? =
        firstAvailable(bodyFamilyCandidates)

    private static func firstAvailable(_ names: [String]) -> String? {
#if canImport(AppKit)
        return names.first { NSFont(name: $0, size: 12) != nil }
#else
        return names.first
#endif
    }

    /// Characterful display type (Bricolage Grotesque) for headings.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if let family = displayFamily {
            return .custom(family, fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    /// Body / UI type (Schibsted Grotesk).
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = bodyFamily {
            return .custom(family, fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }
}

/// Registers the bundled fonts at launch so `PMFont` can resolve them
/// regardless of how the resources are flattened into the app bundle.
enum PMFontRegistrar {
    private static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
#if canImport(AppKit)
        let names = ["BricolageGrotesque", "SchibstedGrotesk"]
        for name in names {
            guard let url = Bundle.main.url(
                forResource: name,
                withExtension: "ttf"
            ) ?? Bundle.main.url(
                forResource: name,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
#endif
    }
}

// MARK: - Shared surface styling

extension View {
    /// Rounded, bordered card surface used throughout the deck.
    func pmCard(
        cornerRadius: CGFloat = 18,
        fill: Color = .pmSurface,
        shadow: Bool = false
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.pmLine, lineWidth: 1)
        )
        .shadow(
            color: shadow
                ? Color.black.opacity(0.10)
                : Color.clear,
            radius: shadow ? 14 : 0,
            x: 0,
            y: shadow ? 8 : 0
        )
    }
}
