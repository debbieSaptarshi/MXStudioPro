import SwiftUI

/// BandLab-lite drum pads (Figma Drum Midi 95:88141 / Week 34 Drum Studio).
/// Landscape: shorter pad grid so arrange + pads fit Figma 812×375.
/// 8 GM-ish pads in a 2×4 grid with Y→velocity and brief hit flash.
public struct DrumPadView: View {
    /// MIDI note, velocity
    public var onPadHit: (UInt8, UInt8) -> Void
    public var onPadRelease: ((UInt8) -> Void)?

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var padSurfaceHeight: CGFloat { isLandscape ? 110 : 172 }

    public init(
        onPadHit: @escaping (UInt8, UInt8) -> Void,
        onPadRelease: ((UInt8) -> Void)? = nil
    ) {
        self.onPadHit = onPadHit
        self.onPadRelease = onPadRelease
    }

    private static let softVelocity: UInt8 = 40
    private static let hardVelocity: UInt8 = 127
    private static let flashNanoseconds: UInt64 = 120_000_000

    private struct PadDef: Identifiable {
        let note: UInt8
        let label: String
        var id: UInt8 { note }
    }

    private let pads: [[PadDef]] = [
        [
            PadDef(note: 36, label: "Kick"),
            PadDef(note: 38, label: "Snare"),
            PadDef(note: 39, label: "Clap"),
            PadDef(note: 42, label: "Closed HH"),
        ],
        [
            PadDef(note: 46, label: "Open HH"),
            PadDef(note: 45, label: "Tom"),
            PadDef(note: 37, label: "Perc"),
            PadDef(note: 51, label: "Ride"),
        ],
    ]

    @State private var activePads: Set<UInt8> = []
    /// Pads already fired for the current drag so velocity isn't retriggered every frame.
    @State private var gestureArmedPads: Set<UInt8> = []

    public var body: some View {
        VStack(spacing: 0) {
            headerRow
            padGrid
                .padding(.horizontal, isLandscape ? 8 : 12)
                .padding(.bottom, isLandscape ? 4 : 8)
        }
        .frame(height: padSurfaceHeight)
        .background(MXColor.surfaceRaised)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Drums")
                .font(MXFont.smallButton())
                .foregroundStyle(MXColor.lightGrey)

            Spacer(minLength: 8)

            if !isLandscape {
                Text("Tap pads · Play to capture")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, isLandscape ? 8 : 12)
        .padding(.vertical, isLandscape ? 4 : 8)
    }

    // MARK: - Grid

    private var padGrid: some View {
        GeometryReader { geo in
            let rows = CGFloat(pads.count)
            let cols = CGFloat(pads.first?.count ?? 4)
            let spacing: CGFloat = 6
            let padW = (geo.size.width - spacing * (cols - 1)) / cols
            let padH = (geo.size.height - spacing * (rows - 1)) / rows

            VStack(spacing: spacing) {
                ForEach(0..<pads.count, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(pads[row]) { pad in
                            padCell(pad, width: padW, height: padH)
                        }
                    }
                }
            }
        }
    }

    private func padCell(_ pad: PadDef, width: CGFloat, height: CGFloat) -> some View {
        let active = activePads.contains(pad.note)
        return Text(pad.label)
            .font(MXFont.caption())
            .foregroundStyle(active ? MXColor.black : MXColor.lightGrey)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? MXColor.orange : MXColor.layer2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handlePadChanged(note: pad.note, locationY: value.location.y, padHeight: height)
                    }
                    .onEnded { _ in
                        handlePadEnded(note: pad.note)
                    }
            )
    }

    // MARK: - Interaction

    private func handlePadChanged(note: UInt8, locationY: CGFloat, padHeight: CGFloat) {
        guard !gestureArmedPads.contains(note) else { return }
        gestureArmedPads.insert(note)

        let velocity = velocity(forY: locationY, height: padHeight)
        hit(note, velocity: velocity)
    }

    private func handlePadEnded(note: UInt8) {
        gestureArmedPads.remove(note)
        onPadRelease?(note)
    }

    private func hit(_ note: UInt8, velocity: UInt8) {
        activePads.insert(note)
        onPadHit(note, velocity)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.flashNanoseconds)
            activePads.remove(note)
        }
    }

    /// Top of pad ≈ hard (127), bottom ≈ soft (40). Matches PianoKeyboardView.
    private func velocity(forY y: CGFloat, height: CGFloat) -> UInt8 {
        guard height > 0 else { return 100 }
        let clampedY = min(max(y, 0), height)
        let t = 1 - Double(clampedY / height)
        let soft = Double(Self.softVelocity)
        let hard = Double(Self.hardVelocity)
        let value = soft + (hard - soft) * t
        return UInt8(min(127, max(1, Int(value.rounded()))))
    }
}
