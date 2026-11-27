import Foundation
import SwiftUI
import UIKit

/// Colours from the Figma file. Each one is a colour set in Assets.xcassets/Colors.
enum Palette {
    static let ink = Color("Ink")                       // #000000 main text
    static let inkSecondary = Color("InkSecondary")     // #3A434D body text
    static let inkTertiary = Color("InkTertiary")       // #616370 labels
    static let inkDisabled = Color("InkDisabled")       // #AFAFAF past days
    static let surface = Color("Surface")               // #F2F4F5 cards, chips, fields
    static let buttonDark = Color("ButtonDark")         // #1F1A17 primary buttons
    static let yellow = Color("BrandYellow")            // #FDF852 brand accent
    static let coach = Color("CoachDark")               // #1B1E29 toasts and tips
    static let danger = Color("Danger")                 // #D70015 passed dates (4.5:1 on white)
    static let dangerBackground = Color("DangerBackground") // #FFE5E5
    static let green = Color("BrandGreen")              // #00463C eaten bars
    static let toggleGreen = Color("ToggleGreen")       // #1F7A4A toggles, checkboxes
    static let chartGray = Color("ChartGray")           // #979799 thrown bars, chevrons
    static let fieldBorder = Color.black.opacity(0.18)
}

extension Font {
    /// "My Food", "Profile" (Figma: 24 Bold)
    static let pfScreenTitle = Font.title2.weight(.bold)
    /// Section headers like "Passed the date" (Figma: 20 Semi Bold)
    static let pfSection = Font.title3.weight(.semibold)
    /// Card titles (Figma: 15 Regular)
    static let pfRowTitle = Font.subheadline
    /// Field labels (Figma: 13 Medium)
    static let pfLabel = Font.footnote.weight(.medium)
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var background: Color = Palette.buttonDark
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(background))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Underlined text button ("Save and add another", "or type it in").
struct LinkButtonStyle: ButtonStyle {
    var color: Color = Palette.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .underline()
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Rounded chip ("Milk", "Today", filter chips). Dark when selected.
struct ChipStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(isSelected ? Color.white : Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isSelected ? Palette.buttonDark : Palette.surface))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Big segment button ("Use By / Best Before / Not sure").
struct SegmentButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(isSelected ? Color.white : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Palette.buttonDark : Palette.surface))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - Small building blocks

/// Small "Frozen" tag on food kept in the freezer, same shape as the date type badge.
struct FrozenBadge: View {
    /// Icon only, for narrow rows.
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "snowflake").font(.system(size: 9, weight: .semibold))
            if !compact { Text("Frozen").font(.caption).lineLimit(1) }
        }
        .fixedSize()
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.surface))
    }
}

/// Lays out the date type badge and the Frozen tag on one line. If the full Frozen tag does not fit,
/// the icon-only one is used. A plain Layout (not ViewThatFits) so the badges slide together with the
/// row when List and Calendar switch.
/// Subviews: [date badge] or [date badge, full Frozen, compact Frozen].
struct BadgeRowLayout: Layout {
    var spacing: CGFloat = 6

    private func showsFull(_ width: CGFloat?, _ s: Subviews) -> Bool {
        guard s.count == 3 else { return true }
        let date = s[0].sizeThatFits(.unspecified).width
        let full = s[1].sizeThatFits(.unspecified).width
        return date + spacing + full <= (width ?? .infinity)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let date = subviews[0].sizeThatFits(.unspecified)
        guard subviews.count == 3 else { return date }
        let tag = subviews[showsFull(proposal.width, subviews) ? 1 : 2].sizeThatFits(.unspecified)
        return CGSize(width: date.width + spacing + tag.width, height: max(date.height, tag.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let date = subviews[0].sizeThatFits(.unspecified)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
        guard subviews.count == 3 else { return }
        let full = showsFull(bounds.width, subviews)
        let shown = full ? 1 : 2, hidden = full ? 2 : 1
        subviews[shown].place(at: CGPoint(x: bounds.minX + date.width + spacing, y: bounds.minY),
                              anchor: .topLeading, proposal: .unspecified)
        // The unused variant is parked far outside the row (the scroll view clips it).
        subviews[hidden].place(at: CGPoint(x: bounds.minX, y: bounds.minY - 5000),
                               anchor: .topLeading, proposal: .unspecified)
    }
}

struct DateTypeBadge: View {
    let type: DateType
    var overdue = false

    private var tint: Color { overdue ? Palette.danger : Palette.ink }

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if type == .useBy {
                    Circle().fill(tint)
                } else {
                    Circle().strokeBorder(tint, lineWidth: 1.4)
                }
            }
            .frame(width: 7, height: 7)
            Text(type == .notSure ? DateType.bestBefore.title : type.title)
                .font(.caption)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .fixedSize()   // always one line: "Best Before" never wraps
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(overdue ? Palette.dangerBackground : Palette.surface))
    }
}

/// Pixel-art food icon with nearest-neighbour scaling so pixels stay crisp.
struct FoodIconView: View {
    let asset: String
    var size: CGFloat = 62
    var framed = true

    @Environment(\.displayScale) private var displayScale

    private var resolvedAsset: String {
        UIImage(named: asset) == nil ? "food_unknown_food" : asset
    }

    /// The food art is a true 32 x 32 pixel grid. Draw it at a whole number of screen pixels per art pixel,
    /// so every art pixel is the same size and the edges stay sharp (no blur, no uneven pixels).
    private var artSide: CGFloat {
        let available = framed ? size * 0.72 : size
        let scale = max(displayScale, 1)
        let k = max(1, (available * scale / 32).rounded())
        return 32 * k / scale
    }

    /// Drawn in code from PixelFoodArt (same pixels as the Higgsfield images). The PNG is only a fallback.
    @ViewBuilder private var art: some View {
        if PixelFoodView.has(asset) {
            PixelFoodView(asset: asset)
        } else if PixelFoodView.has("food_unknown_food") && UIImage(named: asset) == nil {
            PixelFoodView(asset: "food_unknown_food")
        } else {
            Image(resolvedAsset).resizable().interpolation(.none).antialiased(false)
        }
    }

    var body: some View {
        art
            .frame(width: artSide, height: artSide)
            .frame(width: size, height: size)
            .background {
                if framed {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white)
                }
            }
            .overlay {
                if framed {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

struct SectionHeaderRow: View {
    let title: String
    let count: Int
    var note: String? = nil
    /// Red title, used only for "Don't eat" (Use by passed).
    var alert: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.pfSection)
                Spacer()
                Text("\(count)").font(.pfSection)
            }
            .foregroundStyle(alert ? Palette.danger : Palette.ink)
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

/// Grey rounded container used for settings groups and stat tiles.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
    }
}

extension View {
    func pfCard(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Label + value row ("Category · Dairy").
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Palette.ink)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
        }
        .padding(.vertical, 18)
    }
}

/// Text field with a label, grey border and an error message under it.
struct LabeledField<Field: View>: View {
    let label: String
    var error: String?
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.pfLabel).foregroundStyle(Palette.ink)
            field
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(error == nil ? Palette.fieldBorder : Palette.danger, lineWidth: 1))
            if let error {
                Text(error).font(.footnote).foregroundStyle(Palette.danger)
            }
        }
    }
}

/// Password field with a Show / Hide toggle.
struct PasswordField: View {
    let placeholder: String
    @Binding var text: String
    @State private var reveal = false

    var body: some View {
        HStack {
            Group {
                if reveal {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button(reveal ? "Hide" : "Show") { reveal.toggle() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
    }
}

/// Side-to-side shake for validation errors.
nonisolated struct Shake: GeometryEffect {
    var travel: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

/// Toast pill drawn above the content.
struct ToastHost: View {
    @Environment(ToastCenter.self) private var toasts
    var bottomPadding: CGFloat = 104

    var body: some View {
        VStack {
            Spacer()
            if let toast = toasts.current {
                HStack(spacing: 12) {
                    // Line break rule: the first line is the food name or the main message (one line, cut with ...).
                    // Anything after a line break is the result, shown on the second line in a lighter colour.
                    let lines = toast.message.components(separatedBy: "\n")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lines[0])
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if lines.count > 1 {
                            Text(lines.dropFirst().joined(separator: " "))
                                .font(.footnote)
                                .foregroundStyle(Color.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if let title = toast.actionTitle {
                        Button(title) { toasts.performAction() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.yellow)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.coach))
                .padding(.horizontal, 20)
                .padding(.bottom, bottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(toasts.current != nil)
    }
}
