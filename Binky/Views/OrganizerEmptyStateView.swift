import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Empty organizer activity area: taglines plus a bucket animation driven by real sort events when a batch is active.
struct OrganizerEmptyStateView: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var sortProgress = SortProgressTracker.shared

    @State private var loopIndex = 0
    @State private var cardOffset: CGSize = .zero
    @State private var cardScale: CGFloat = 0.6
    @State private var cardOpacity: Double = 0
    @State private var cardRotation: Double = 0
    @State private var bumpedDestination: SortDestination? = nil
    @State private var bumpTrigger = 0
    @State private var taglineTaskID = UUID()
    @State private var flightTask: Task<Void, Never>?

    private var shouldReduceMotion: Bool { prefs.reduceMotion || systemReduceMotion }

    /// Distance from stage center to each side destination center (matches HStack spacing math).
    private let destinationSpacing: CGFloat = 96
    /// Vertical drop distance from card spawn point down to destination row.
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

            Text(String(localized: "Turn on Watch to tidy new files, or run Sort Now. You can also drop files from your watch folder here.", comment: "Organizer empty activity hint."))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Text(String(localized: "Files mid-download wait until they settle.", comment: "Organizer empty state: incomplete download hint."))
                .font(.caption)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: taglineTaskID) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                loopIndex += 1
            }
        }
        .onChange(of: shouldReduceMotion) { _, _ in taglineTaskID = UUID() }
        .onChange(of: sortProgress.latestAnimationPulse?.id) { _, _ in
            guard !shouldReduceMotion else { return }
            guard sortProgress.isActive, let pulse = sortProgress.latestAnimationPulse else { return }
            let dest = sortDestination(for: pulse.bucket)
            flightTask?.cancel()
            flightTask = Task { await runFlightCycle(to: dest) }
        }
        .onChange(of: sortProgress.isActive) { _, active in
            if active {
                resetCardPose()
            } else {
                flightTask?.cancel()
                flightTask = nil
                resetCardPose()
            }
        }
        .onDisappear {
            flightTask?.cancel()
            flightTask = nil
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private var sortingStage: some View {
        ZStack {
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(SortDestination.allCases, id: \.self) { dest in
                        destinationView(dest)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 4)
            }

            if shouldReduceMotion || !sortProgress.isActive {
                staticCardFan
                    .offset(y: -52)
            } else {
                let dest = sortDestination(for: sortProgress.latestAnimationPulse?.bucket ?? .documents)
                fileCard(for: dest.sourceType)
                    .scaleEffect(cardScale)
                    .rotationEffect(.degrees(cardRotation))
                    .opacity(cardOpacity)
                    .offset(cardOffset)
            }
        }
    }

    private func sortDestination(for bucket: SortAnimationBucket) -> SortDestination {
        switch bucket {
        case .images: return .images
        case .videos: return .videos
        case .documents: return .docs
        }
    }

    private func destinationView(_ dest: SortDestination) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 64, height: 48)
                Image(systemName: dest.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.bounce, value: bumpedDestination == dest ? bumpTrigger : 0)
            }
            Text(dest.label)
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

    // MARK: - Flight (real sort pulses)

    private func resetCardPose() {
        cardOffset = CGSize(width: 0, height: -dropDistance + 50)
        cardScale = 0.6
        cardOpacity = 0
        cardRotation = -6
        bumpedDestination = nil
    }

    private func runFlightCycle(to dest: SortDestination) async {
        // If cancelled before we start, bail quietly.
        guard !Task.isCancelled else { return }

        // Initial appearance: cards begin small + invisible above center; cycle eases in cleanly.
        cardOffset = CGSize(width: 0, height: -dropDistance + 50)
        cardScale = 0.6
        cardOpacity = 0
        cardRotation = -6

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

        // 2) Glide diagonally toward the matching destination
        let destX = dest.centerOffset(spacing: destinationSpacing)
        let leanAngle: Double = dest == .videos ? 0 : (dest == .images ? -8 : 8)
        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.78)) {
            cardOffset = CGSize(width: destX, height: 6)
            cardRotation = leanAngle
        }
        await sleep(ms: 580)
        guard !Task.isCancelled else { return }

        // 3) Drop into destination — shrink + fade as it lands
        withAnimation(.easeIn(duration: 0.26)) {
            cardOffset = CGSize(width: destX, height: 30)
            cardScale = 0.3
            cardOpacity = 0
        }
        bumpedDestination = dest
        bumpTrigger &+= 1
        await sleep(ms: 360)
        bumpedDestination = nil
        await sleep(ms: 140)
    }

    private func sleep(ms: Int) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }
}

// MARK: - Sort destinations

private enum SortDestination: CaseIterable {
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

    /// Horizontal offset (pts) from stage center to this destination's center.
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
