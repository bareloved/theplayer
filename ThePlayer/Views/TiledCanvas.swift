import SwiftUI

/// A Canvas that splits its drawing surface into multiple horizontal tiles so
/// that no single SwiftUI render texture exceeds the Metal size limit
/// (~16384pt). The `draw` closure receives:
///   - a `GraphicsContext` already translated so the origin is at the start
///     of the total content (callers draw in "total width" coordinates)
///   - the full content size
///   - the tile's x-range in total-width coordinates, so callers can skip
///     work for geometry that falls outside the current tile
struct TiledCanvas: View {
    let totalWidth: CGFloat
    let height: CGFloat
    /// Maximum per-tile width. Must stay well under the GPU texture cap.
    var maxTileWidth: CGFloat = 4096
    let draw: (inout GraphicsContext, CGSize, ClosedRange<CGFloat>) -> Void

    var body: some View {
        let tileCount = max(1, Int(ceil(totalWidth / maxTileWidth)))
        let tileWidth = totalWidth / CGFloat(tileCount)
        HStack(spacing: 0) {
            ForEach(0..<tileCount, id: \.self) { i in
                let xStart = CGFloat(i) * tileWidth
                let xEnd = xStart + tileWidth
                Canvas { context, _ in
                    var ctx = context
                    ctx.translateBy(x: -xStart, y: 0)
                    draw(&ctx, CGSize(width: totalWidth, height: height), xStart...xEnd)
                }
                .frame(width: tileWidth, height: height)
                .clipped()
            }
        }
        .frame(width: totalWidth, height: height, alignment: .leading)
    }
}
