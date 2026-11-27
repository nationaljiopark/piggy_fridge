//
//  PigPeekSplashView.swift
//  Plays the pig-peek splash exactly as keyed in After Effects (fridge copy.aepx):
//  same keyframe times, values and bezier easing, evaluated every frame.
//
//  Setup
//  1. Add pigsplash_fridge.png, pigsplash_head.png, pigsplash_hand.png to Assets.xcassets
//     (all share one 568x556 canvas = the AE layer size).
//  2. In your App file:
//
//  @main
//  struct FreshMateApp: App {
//      @State private var showSplash = true
//      var body: some Scene {
//          WindowGroup {
//              ZStack {
//                  ContentView()
//                  if showSplash {
//                      PigPeekSplashView { showSplash = false }
//                          .zIndex(1)
//                  }
//              }
//          }
//      }
//  }
//

import SwiftUI

// MARK: - Keyframe engine (AE-style temporal bezier, speed 0)

private struct Key {
    let t: Double
    let v: [Double]
    let inEase: Bool, outEase: Bool
    let inInf: Double, outInf: Double
}

private struct Track {
    let keys: [Key]

    func value(at t: Double) -> [Double] {
        guard let first = keys.first, let last = keys.last else { return [] }
        if t <= first.t { return first.v }
        if t >= last.t { return last.v }
        for i in 0..<(keys.count - 1) {
            let a = keys[i], b = keys[i + 1]
            guard t >= a.t && t <= b.t else { continue }
            let x1 = a.outEase ? a.outInf : 1.0 / 3, y1 = a.outEase ? 0 : 1.0 / 3
            let x2 = b.inEase ? 1 - b.inInf : 2.0 / 3, y2 = b.inEase ? 1 : 2.0 / 3
            let u = Track.bezier((t - a.t) / (b.t - a.t), x1, y1, x2, y2)
            return zip(a.v, b.v).map { $0 + ($1 - $0) * u }
        }
        return last.v
    }

    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        var lo = 0.0, hi = 1.0, s = x
        for _ in 0..<32 {
            s = (lo + hi) / 2
            let xs = 3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s
            if xs < x { lo = s } else { hi = s }
        }
        return 3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s
    }
}

private func K(_ t: Double, _ v: [Double], _ inE: Bool, _ outE: Bool, _ inInf: Double, _ outInf: Double) -> Key {
    Key(t: t, v: v, inEase: inE, outEase: outE, inInf: inInf, outInf: outInf)
}

/// Values copied from "fridge copy.aepx". Positions are AE pixels relative to the comp centre (SCENE null).
private enum Timeline {
    static let duration = 3.5

    static let fridgePos = Track(keys: [
        K(0.0,    [-116, 132],     true, true, 0.33,  0.75),
        K(0.27,   [-116, 274],     true, true, 0.001, 0.5),
        K(0.52,   [-116, 222],     true, true, 0.5,   0.5),
        K(0.67,   [-116, 274],     true, true, 0.75,  0.001),
        K(2.6333, [-116, 274],     true, true, 0.75,  0.1667),
        K(2.8667, [4.251, 274],    true, true, 0.75,  0.1667)
    ])
    static let fridgeScale = Track(keys: [
        K(0.27, [1.0, 1.0],    true, true,  0.5,    0.5),
        K(0.36, [1.12, 0.86],  true, true,  0.5,    0.5),
        K(0.52, [0.95, 1.06],  true, true,  0.5,    0.5),
        K(0.67, [1.0, 1.0],    true, true,  0.5,    0.5),
        K(0.74, [1.05, 0.737], true, true,  0.5,    0.5),
        K(0.9,  [1.0, 1.0],    true, false, 0.6332, 0.5)
    ])
    static let fridgeOpacity = Track(keys: [
        K(0.0, [0], false, false, 0, 0), K(0.08, [1], false, false, 0, 0),
        K(3.1, [1], false, false, 0, 0), K(3.45, [0], false, false, 0, 0)
    ])
    static let headPos = Track(keys: [
        K(0.7333, [-240, 67],          true, true, 0.9, 0.1),
        K(1.3333, [0, 0],              true, true, 0.9, 0.1),
        K(2.6333, [0, 0],              true, true, 0.9, 0.1),
        K(2.8333, [-228.476, 44.092],  true, true, 0.9, 0.1)
    ])
    static let headScale = Track(keys: [
        K(2.55,   [1.0, 1.0],   true, true, 0.1667, 0.3333),
        K(2.6333, [1.06, 1.06], true, true, 0.3333, 0.3333),
        K(2.7,    [1.0, 1.0],   true, true, 0.3333, 0.3333)
    ])
    static let headOpacity = Track(keys: [
        K(0.7333, [0], false, false, 0, 0), K(0.8333, [1], false, false, 0, 0),
        K(2.6667, [1], false, false, 0, 0), K(2.7667, [0], true, false, 0.3333, 0.1667)
    ])
    static let handPos = Track(keys: [
        K(0.7333, [-59.532, 78.683], false, false, 0, 0),
        K(1.3333, [64.726, 90.708],  true, true, 0.3333, 0.3333)
    ])
    static let sceneScale = Track(keys: [
        K(3.1,  [1.0, 1.0],   true, true, 0.33, 0.75),
        K(3.45, [0.85, 0.85], true, true, 0.33, 0.75)
    ])
}

// MARK: - View

struct PigPeekSplashView: View {
    var background: Color = Color(red: 1.0, green: 0.992, blue: 0.957) // #FFFDF4
    var onFinished: () -> Void = {}

    @State private var start = Date()
    @State private var finished = false

    // Shared art canvas (AE layer size, px)
    private let canvas = CGSize(width: 568, height: 556)
    private let compWidth: CGFloat = 1080

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / compWidth          // AE px -> points, same framing as the 1080-wide comp
            TimelineView(.animation(paused: finished)) { context in
                let t = min(context.date.timeIntervalSince(start), Timeline.duration)
                let ss = Timeline.sceneScale.value(at: t)

                ZStack {
                    // bottom -> top, same order as the AE comp
                    if t >= 0.7333 {
                        layer("pigsplash_head", k: k, anchor: CGPoint(x: 284, y: 278), rotation: 0,
                              pos: Timeline.headPos.value(at: t),
                              scale: Timeline.headScale.value(at: t),
                              opacity: Timeline.headOpacity.value(at: t)[0])
                    }
                    if t >= 0.7333 && t < 2.6667 {
                        layer("pigsplash_hand", k: k, anchor: CGPoint(x: 301.323, y: 396.183), rotation: 119,
                              pos: Timeline.handPos.value(at: t), scale: [1, 1], opacity: 1)
                    }
                    layer("pigsplash_fridge", k: k, anchor: CGPoint(x: 168, y: 552), rotation: 0,
                          pos: Timeline.fridgePos.value(at: t),
                          scale: Timeline.fridgeScale.value(at: t),
                          opacity: Timeline.fridgeOpacity.value(at: t)[0])
                }
                .scaleEffect(x: ss[0], y: ss[1])
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(background.ignoresSafeArea())
        .ignoresSafeArea()
        .task {
            start = Date()
            try? await Task.sleep(nanoseconds: UInt64(Timeline.duration * 1_000_000_000))
            finished = true
            onFinished()
        }
        .accessibilityLabel("App loading")
    }

    /// AE transform: anchor (layer px) is moved to `pos` (comp-centre space), scaled and rotated around the anchor.
    private func layer(_ name: String, k: CGFloat, anchor: CGPoint, rotation: Double,
                       pos: [Double], scale: [Double], opacity: Double) -> some View {
        let unit = UnitPoint(x: anchor.x / canvas.width, y: anchor.y / canvas.height)
        let dx = (CGFloat(pos[0]) - (anchor.x - canvas.width / 2)) * k
        let dy = (CGFloat(pos[1]) - (anchor.y - canvas.height / 2)) * k
        return Image(name)
            .resizable()
            .interpolation(.none)
            .frame(width: canvas.width * k, height: canvas.height * k)
            .scaleEffect(x: scale[0], y: scale[1], anchor: unit)
            .rotationEffect(.degrees(rotation), anchor: unit)
            .offset(x: dx, y: dy)
            .opacity(opacity)
    }
}

#Preview {
    PigPeekSplashView()
}
