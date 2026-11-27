import SwiftUI

/// Draws one food from PixelFoodArt: 32 x 32 squares, each filled with its own colour.
/// Squares are drawn with no smoothing, so the edges stay sharp at any size.
struct PixelFoodView: View {
    let asset: String

    var body: some View {
        Canvas { context, size in
            guard let grid = PixelFoodGrid.grid(for: asset) else { return }
            let n = PixelFoodArt.size
            let cell = min(size.width, size.height) / CGFloat(n)
            for y in 0..<n {
                var x = 0
                while x < n {
                    guard let color = grid[y * n + x] else { x += 1; continue }
                    // Join neighbours of the same colour into one rectangle (fewer shapes to draw).
                    var run = 1
                    while x + run < n, grid[y * n + x + run] == color { run += 1 }
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: CGFloat(run) * cell, height: cell)
                    context.fill(Path(rect), with: .color(color.swiftUI), style: FillStyle(antialiased: false))
                    x += run
                }
            }
        }
    }

    static func has(_ asset: String) -> Bool { PixelFoodArt.pixels(for: asset) != nil }
}

/// One pixel colour.
struct PixelRGB: Equatable {
    let r: UInt8, g: UInt8, b: UInt8
    var swiftUI: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
}

/// Reads the hex text once per food and keeps the result.
@MainActor
enum PixelFoodGrid {
    private static var cache: [String: [PixelRGB?]] = [:]

    static func grid(for asset: String) -> [PixelRGB?]? {
        if let hit = cache[asset] { return hit }
        guard let text = PixelFoodArt.pixels(for: asset) else { return nil }
        let bytes = Array(text.utf8)
        let count = PixelFoodArt.size * PixelFoodArt.size
        guard bytes.count == count * 6 else { return nil }
        func hex(_ c: UInt8) -> UInt8 {
            switch c {
            case 48...57: c - 48
            case 65...70: c - 55
            case 97...102: c - 87
            default: 0
            }
        }
        var out = [PixelRGB?](repeating: nil, count: count)
        for i in 0..<count {
            let o = i * 6
            if bytes[o] == 46 { continue }   // "." = see-through
            out[i] = PixelRGB(r: hex(bytes[o]) << 4 | hex(bytes[o + 1]),
                              g: hex(bytes[o + 2]) << 4 | hex(bytes[o + 3]),
                              b: hex(bytes[o + 4]) << 4 | hex(bytes[o + 5]))
        }
        cache[asset] = out
        return out
    }
}
