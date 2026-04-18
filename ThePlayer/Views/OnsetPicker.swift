import Foundation

enum OnsetPicker {
    /// Returns the onset time nearest to `time`, or `nil` if the nearest
    /// onset is farther than `maxPx` in screen pixels at zoom `pxPerSec`.
    /// Assumes `onsets` is sorted ascending. Ties resolve to the earlier onset.
    static func nearestOnset(
        to time: Float,
        in onsets: [Float],
        pxPerSec: Double,
        maxPx: Double
    ) -> Float? {
        guard !onsets.isEmpty else { return nil }

        // Binary-search the insertion point of `time`.
        var lo = 0
        var hi = onsets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if onsets[mid] < time { lo = mid + 1 } else { hi = mid }
        }

        // Compare the neighbor on either side. `lo` is the first index whose
        // onset is >= time (may be == onsets.count). The earlier candidate is
        // at lo - 1 (if it exists).
        let right: Float? = lo < onsets.count ? onsets[lo] : nil
        let left: Float? = lo > 0 ? onsets[lo - 1] : nil

        let best: Float
        switch (left, right) {
        case let (l?, r?):
            let dL = abs(time - l)
            let dR = abs(r - time)
            // Tie → earlier onset (the left one).
            best = dL <= dR ? l : r
        case let (l?, nil): best = l
        case let (nil, r?): best = r
        default: return nil
        }

        let distancePx = Double(abs(best - time)) * pxPerSec
        return distancePx <= maxPx ? best : nil
    }
}
