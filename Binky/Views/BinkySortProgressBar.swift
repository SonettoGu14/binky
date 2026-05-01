import SwiftUI

private struct SortBarPercentLabel: View, Animatable {
    var frac: CGFloat
    var compact: Bool

    nonisolated var animatableData: CGFloat {
        get { frac }
        set { frac = newValue }
    }

    private var percent: Int {
        Int((max(frac, 0) * 100).rounded(.towardZero))
    }

    var body: some View {
        Text("\(percent)%")
            .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .contentTransition(.numericText(countsDown: false))
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// Bar track + magenta fill + animated `%`, aligned with batch fraction.
struct BinkySortProgressBar: View {
    /// 0 … 1
    let fraction: Double
    var caption: String? = nil
    var compact: Bool = false
    var showsCaption: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var clampedFrac: CGFloat {
        CGFloat(min(max(fraction, 0), 1))
    }

    private var fillWidthMultiplier: CGFloat { clampedFrac }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if showsCaption, let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(alignment: .center, spacing: compact ? 6 : 10) {
                GeometryReader { geo in
                    let barH = compact ? CGFloat(6) : CGFloat(9)
                    let w = geo.size.width
                    let filled = clampedFrac > 0 ? max(4, w * fillWidthMultiplier) : 0
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                        Capsule()
                            .fill(binkyTintColor)
                            .frame(width: min(w, filled), height: barH)
                            .shadow(color: binkyTintColor.opacity(0.22), radius: 2, y: 0)
                    }
                    .frame(height: barH)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.32), value: clampedFrac)
                }
                .frame(height: compact ? 6 : 9)

                SortBarPercentLabel(frac: clampedFrac, compact: compact)
                    .animation(.easeInOut(duration: 0.42), value: clampedFrac)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
