import AppKit
import SwiftUI

// MARK: - Color Extension

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b, a: CGFloat
        switch hexSanitized.count {
        case 6:
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        case 8:
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - App Theme Palette

enum Theme {
    static func dynamic(light: String, dark: String) -> Color {
        let lightColor = NSColor(hex: light) ?? .white
        let darkColor = NSColor(hex: dark) ?? .black
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? darkColor : lightColor
        }))
    }

    // Core Brand Colors
    static let sidebar = dynamic(light: "#F1EEE5", dark: "#182638")
    static let contentBackground = dynamic(light: "#FAF8F2", dark: "#1C222B")
    static let card = dynamic(light: "#FFFFFF", dark: "#252D38")
    static let textPrimary = dynamic(light: "#102040", dark: "#EEECE5")
    static let textSecondary = dynamic(light: "#626771", dark: "#ADB5C0")
    static let accent = dynamic(light: "#D4960E", dark: "#E5AD35")
    static let textOnAccent = Color(nsColor: NSColor(hex: "#102040")!)
    static let divider = dynamic(light: "#DED8CC", dark: "#394352")
    static let success = dynamic(light: "#1A756B", dark: "#66C5B5")
    static let warning = dynamic(light: "#D4960E", dark: "#E5AD35")
    static let error = dynamic(light: "#D9383A", dark: "#E05355")

    // Component surface tints
    static let rowHover = dynamic(light: "#EAE6DB", dark: "#202833")
    static let keyCapBackground = dynamic(light: "#EFECE4", dark: "#2C3542")
}

// MARK: - View Modifiers & Styles

struct FlatCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.divider, lineWidth: 0.8)
            )
    }
}

extension View {
    func flatCard(cornerRadius: CGFloat = 8) -> some View {
        modifier(FlatCardStyle(cornerRadius: cornerRadius))
    }
}

// MARK: - Reusable Setting Row Components

struct SettingRow<Content: View>: View {
    let title: String
    var description: String? = nil
    var indented: Bool = false
    @ViewBuilder let control: Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                if indented {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textPrimary)

                    if let description = description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 12)

            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct SettingToggleRow: View {
    let title: String
    var description: String? = nil
    var indented: Bool = false
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, description: description, indented: indented) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
        }
    }
}

struct SettingSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.bottom, 2)
    }
}

struct FlatKeyCap: View {
    let text: String

    private var displayText: String {
        switch text {
        case "⌃": "⌃ control"
        case "⌥": "⌥ option"
        case "⇧": "⇧ shift"
        case "⌘": "⌘ command"
        case "fn": "fn"
        case "Esc", "⎋": "⎋ esc"
        case "Tab", "⇥": "⇥ tab"
        case "Space", "␣": "␣ space"
        case "Return", "↩": "↩ return"
        case "Delete", "⌫": "⌫ delete"
        default: text
        }
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.keyCapBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.divider, lineWidth: 0.8)
            )
    }
}
