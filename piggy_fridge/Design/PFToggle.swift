import Foundation
import SwiftUI
import UIKit

/// On/off switch with a plain sliding knob. It does not grow or bounce like the newer system switch,
/// and slides with the same ease in as the List / Calendar switch.
struct PFToggle: View {
    @Binding var isOn: Bool
    var label: String
    /// Local copy so the knob starts sliding the instant you tap, even if the real value updates later.
    @State private var shown: Bool? = nil

    private var on: Bool { shown ?? isOn }

    var body: some View {
        Button {
            let next = !on
            withAnimation(.easeIn(duration: 0.3)) { shown = next }
            isOn = next
        } label: {
            ZStack(alignment: .leading) {
                Capsule().fill(on ? Palette.toggleGreen : Palette.chartGray.opacity(0.35))
                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: on ? 22 : 2)
            }
            .frame(width: 51, height: 31)
            .onChange(of: isOn) { _, v in
                withAnimation(.easeIn(duration: 0.3)) { shown = v }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
