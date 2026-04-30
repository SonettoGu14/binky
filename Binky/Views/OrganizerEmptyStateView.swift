import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Empty organizer activity area: looping "sorting" animation (file cards routed into typed buckets) plus rotating taglines.
struct OrganizerEmptyStateView: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var loopIndex = 0
    @State private var cardIndex = 0
    @State private var cardOffset: CGSize = .zero
    @State private var cardScale: CGFloat = 0.6
    @State private var cardOpacity: Double = 0
    @State private var cardRotation: Double = 0
    @State private var bumpedBucket: SortBucket? = nil
    @State private var bumpTrigger = 0
    @State private var animationID = UUID()

    private var shouldReduceMotion: Bool { prefs.reduceMotion || systemReduceMotion }

    /// Distance from stage center to each side bucket center (matches HStack spacing math).
    private let bucketSpacing: CGFloat = 96
    /// Vertical drop distance from card spawn point down to bucket level.
    private let dropDistance: CGFloat = 130

    var body: some View {
        VStack(spacing: 18) {
            sortingStage
                .frame(maxWidth: 360)
                .frame(height: 220)
                .allowsHitTesting(false)

            VStack(spacing: 8) {
                Text(String(localized: "No sorts yet.", comment: "Organizer empty activity state title."))
                    .font(.headline)

                Text(S.organizerEmptyTagline(loop: loopIndex))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: loopIndex)
            }

            Text(String(localized: "Turn on Watch to tidy new downloads, or run Sort Now. You can also drop files from your inbox here.", comment: "Organizer empty activity hint."))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: animationID) {
            if shouldReduceMotion {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { return }
                    loopIndex += 1
                }
            } else {
                await runSortingLoop()
            }
        }
        .onChange(of: shouldReduceMotion) { _, _ in animationID = UUID() }
    }

    // MARK: - Stage

    @ViewBuilder
    private var sortingStage: some View {
        ZStack {
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(SortBucket.allCases, id: \.self) { bucket in
                        bucketView(bucket)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 4)
            }

            if shouldReduceMotion {
                staticCardFan
                    .offset(y: -52)
            } else {
                let bucket = SortBucket.allCases[cardIndex % SortBucket.allCases.count]
                fileCard(for: bucket.sourceType)
                    .scaleEffect(cardScale)
                    .rotationEffect(.degrees(cardRotation))
                    .opacity(cardOpacity)
                    .offset(cardOffset)
            }
        }
    }

    private func bucketView(_ bucket: SortBucket) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 64, height: 48)
                Image(systemName: bucket.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.bounce, value: bumpedBucket == bucket ? bumpTrigger : 0)
            }
            Text(bucket.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var staticCardFan: some View {
        ZStack {
            fileCard(for: .pdf)
                .rotationEffect(.degrees(8))
                .offset(x: 28, y: 4)
            fileCard(for: .mpeg4Movie)
                .rotationEffect(.degrees(0))
            fileCard(for: .jpeg)
                .rotationEffect(.degrees(-8))
                .offset(x: -28, y: 4)
        }
    }

    // MARK: - File card

    private func fileCard(for type: UTType) -> some View {
        let width: CGFloat = 56
        let height: CGFloat = 76
        let icon = workspaceIcon(for: type)
        return ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            if icon.isTemplate {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color.secondary)
                    .padding(min(width, height) * 0.12)
            } else {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(min(width, height) * 0.12)
            }
        }
        .frame(width: width, height: height)
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        .id("card-\(type.identifier)-\(colorScheme)")
    }

    private func workspaceIcon(for type: UTType) -> NSImage {
        let name: NSAppearance.Name = (colorScheme == .dark) ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: name) else {
            return NSWorkspace.shared.icon(for: type)
        }
        var icon: NSImage!
        appearance.performAsCurrentDrawingAppearance {
            icon = NSWorkspace.shared.icon(for: type)
        }
        return icon
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.38) : Color.black.opacity(0.12)
    }
    private var shadowRadius: CGFloat { colorScheme == .dark ? 10 : 6 }
    private var shadowY: CGFloat { colorScheme == .dark ? 5 : 3 }

    // MARK: - Loop choreography

    private func runSortingLoop() async {
        // Initial appearance: cards begin small + invisible above center; first cycle eases in cleanly.
        cardOffset = CGSize(width: 0, height: -dropDistance + 50)
        cardScale = 0.6
        cardOpacity = 0
        cardRotation = -6

        while !Task.isCancelled {
            for bucketIndex in 0..<SortBucket.allCases.count {
                cardIndex = bucketIndex
                let bucket = SortBucket.allCases[bucketIndex]
                guard !Task.isCancelled else { return }

                // 1) Spawn above stage and settle to "considering" pose
                cardOffset = CGSize(width: 0, height: -dropDistance + 30)
                cardRotation = Double.random(in: -10 ... 10)
                cardScale = 0.55
                cardOpacity = 0
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    cardOffset = CGSize(width: 0, height: -dropDistance + 60)
                    cardScale = 1.0
                    cardOpacity = 1
                    cardRotation = 0
                }
                await sleep(ms: 620)
                guard !Task.isCancelled else { return }

                // 2) Glide diagonally toward the matching bucket
                let destX = bucket.centerOffset(spacing: bucketSpacing)
                let leanAngle: Double = bucket == .videos ? 0 : (bucket == .images ? -8 : 8)
                withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.78)) {
                    cardOffset = CGSize(width: destX, height: 6)
                    cardRotation = leanAngle
                }
                await sleep(ms: 580)
                guard !Task.isCancelled else { return }

                // 3) Drop into bucket — shrink + fade as it lands
                withAnimation(.easeIn(duration: 0.26)) {
                    cardOffset = CGSize(width: destX, height: 30)
                    cardScale = 0.3
                    cardOpacity = 0
                }
                bumpedBucket = bucket
                bumpTrigger &+= 1
                await sleep(ms: 360)
                bumpedBucket = nil
                await sleep(ms: 140)
            }
            loopIndex += 1
        }
    }

    private func sleep(ms: Int) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }
}

// MARK: - Sort buckets

private enum SortBucket: CaseIterable {
    case images, videos, docs

    var symbol: String {
        switch self {
        case .images: return "photo.on.rectangle.angled"
        case .videos: return "play.rectangle.fill"
        case .docs:   return "doc.fill"
        }
    }

    var label: String {
        switch self {
        case .images: return String(localized: "Images", comment: "Organizer empty state: sort destination label.")
        case .videos: return String(localized: "Videos", comment: "Organizer empty state: sort destination label.")
        case .docs:   return String(localized: "Docs", comment: "Organizer empty state: sort destination label.")
        }
    }

    /// UTType used to fetch the on-card Finder-style document icon (matches DropZoneView idle cards).
    var sourceType: UTType {
        switch self {
        case .images: return .jpeg
        case .videos: return .mpeg4Movie
        case .docs:   return .pdf
        }
    }

    /// Horizontal offset (pts) from stage center to this bucket's center.
    func centerOffset(spacing: CGFloat) -> CGFloat {
        switch self {
        case .images: return -spacing
        case .videos: return 0
        case .docs:   return spacing
        }
    }
}

#if DEBUG
#Preview {
    OrganizerEmptyStateView()
        .environmentObject(BinkyPreferences())
        .frame(width: 520, height: 520)
}
#endif
