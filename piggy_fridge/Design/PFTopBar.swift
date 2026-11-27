import Foundation
import SwiftUI
import UIKit

// The app's own top bar. It replaces the system navigation bar, whose buttons turn into glass capsules.
// Back, close and check are drawn with the same simple round-ended strokes as the Figma icons.

enum PFBarLeading {
    case back, close, none
}

struct PFBackIcon: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 15, y: 5))
            p.addLine(to: CGPoint(x: 8, y: 12))
            p.addLine(to: CGPoint(x: 15, y: 19))
        }
        .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 24, height: 24)
    }
}

struct PFCloseIcon: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 6, y: 6))
            p.addLine(to: CGPoint(x: 18, y: 18))
            p.move(to: CGPoint(x: 18, y: 6))
            p.addLine(to: CGPoint(x: 6, y: 18))
        }
        .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 24, height: 24)
    }
}

struct PFCheckIcon: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 5, y: 12.5))
            p.addLine(to: CGPoint(x: 10, y: 17.5))
            p.addLine(to: CGPoint(x: 19, y: 7))
        }
        .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 24, height: 24)
    }
}

struct PFTopBarModifier<Trailing: View>: ViewModifier {
    let title: String
    let leading: PFBarLeading
    let trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 72)
                    HStack(spacing: 0) {
                        switch leading {
                        case .back:
                            Button { dismiss() } label: { PFBackIcon().frame(width: 44, height: 44) }
                                .accessibilityLabel("Back")
                        case .close:
                            Button { dismiss() } label: { PFCloseIcon().frame(width: 44, height: 44) }
                                .accessibilityLabel("Close")
                        case .none:
                            Color.clear.frame(width: 44, height: 44)
                        }
                        Spacer(minLength: 0)
                        trailing
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 48)
                .background(Color(.systemBackground))
            }
    }
}

extension View {
    func pfTopBar(_ title: String, leading: PFBarLeading = .back) -> some View {
        modifier(PFTopBarModifier(title: title, leading: leading, trailing: EmptyView()))
    }

    func pfTopBar<Trailing: View>(_ title: String, leading: PFBarLeading = .back,
                                  @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(PFTopBarModifier(title: title, leading: leading, trailing: trailing()))
    }
}

/// Title row of the two tab screens (My Food, My Record). Same height and same y as the pushed-screen bar,
/// so the title sits at exactly the same place on every screen.
struct PFTabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.pfScreenTitle).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }
}
