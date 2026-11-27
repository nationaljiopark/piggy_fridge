import Foundation
import SwiftUI
import UIKit

/// The pixel fridge opening animation (Assets.xcassets/FridgeLoading, 55 frames at 24 fps).
/// To use a different animation, replace the fridge_open_000...054 image sets and update `frameCount`.
struct FridgeLoadingView: View {
    var onFinish: () -> Void

    private let frameCount = 55
    private let fps = 24.0
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let index = min(max(Int(elapsed * fps), 0), frameCount - 1)
            Image(String(format: "fridge_open_%03d", index))
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 260)
                .accessibilityLabel("Piggy Fridge")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            start = .now
            try? await Task.sleep(for: .seconds(Double(frameCount) / fps + 0.15))
            onFinish()
        }
    }
}

#Preview {
    FridgeLoadingView {}
}
