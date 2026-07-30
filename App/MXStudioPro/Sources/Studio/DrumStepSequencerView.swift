import SwiftUI

/// BandLab-lite 16-step × kit-part drum sequencer (Week 49 / Figma Drum Midi).
///
/// Rows = Kick → Ride; columns = 16ths in one bar. Tap cells to toggle hits;
/// **Add to timeline** places a MIDI clip at the playhead.
public struct DrumStepSequencerView: View {
    @Binding var grid: [[Bool]]
    public var onPreviewHit: ((UInt8, UInt8) -> Void)?
    public var onApply: () -> Void
    public var onClear: () -> Void
    public var canApply: Bool

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var surfaceHeight: CGFloat { isLandscape ? 132 : 200 }

    private let parts = MXDrumStepSequencer.rowParts
    private let stepCount = MXDrumStepSequencer.stepCount

    public init(
        grid: Binding<[[Bool]]>,
        canApply: Bool = true,
        onPreviewHit: ((UInt8, UInt8) -> Void)? = nil,
        onApply: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) {
        self._grid = grid
        self.canApply = canApply
        self.onPreviewHit = onPreviewHit
        self.onApply = onApply
        self.onClear = onClear
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerRow
            stepGrid
                .padding(.horizontal, isLandscape ? 6 : 10)
                .padding(.bottom, isLandscape ? 4 : 8)
        }
        .frame(height: surfaceHeight)
        .background(MXColor.surfaceRaised)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Steps")
                .font(MXFont.smallButton())
                .foregroundStyle(MXColor.lightGrey)

            Spacer(minLength: 4)

            Button("Clear", action: onClear)
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
                .disabled(!MXDrumStepSequencer.hasHits(grid))

            Button(action: onApply) {
                Text("Add to timeline")
                    .font(MXFont.caption())
                    .foregroundStyle(canApply && MXDrumStepSequencer.hasHits(grid) ? MXColor.orange : MXColor.grey)
            }
            .disabled(!canApply || !MXDrumStepSequencer.hasHits(grid))
            .accessibilityLabel("Add step pattern to timeline")
        }
        .padding(.horizontal, isLandscape ? 8 : 12)
        .padding(.vertical, isLandscape ? 4 : 6)
    }

    // MARK: - Grid

    private var stepGrid: some View {
        GeometryReader { geo in
            let labelW: CGFloat = isLandscape ? 36 : 44
            let spacing: CGFloat = 2
            let rows = CGFloat(parts.count)
            let cols = CGFloat(stepCount)
            let availW = max(0, geo.size.width - labelW - spacing)
            let cellW = (availW - spacing * (cols - 1)) / cols
            let cellH = (geo.size.height - spacing * (rows - 1)) / rows

            VStack(spacing: spacing) {
                ForEach(Array(parts.enumerated()), id: \.element.id) { row, part in
                    HStack(spacing: spacing) {
                        Text(part.shortLabel)
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                            .frame(width: labelW, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        ForEach(0..<stepCount, id: \.self) { step in
                            stepCell(
                                row: row,
                                step: step,
                                part: part,
                                width: cellW,
                                height: cellH
                            )
                        }
                    }
                }
            }
        }
    }

    private func stepCell(
        row: Int,
        step: Int,
        part: MXDrumPart,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let on = isOn(row: row, step: step)
        let beatAccent = step % 4 == 0
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(on ? MXColor.orange : (beatAccent ? MXColor.layer2 : MXColor.layer2.opacity(0.55)))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        on ? MXColor.orange.opacity(0.9) : MXColor.grey.opacity(beatAccent ? 0.35 : 0.15),
                        lineWidth: 0.5
                    )
            )
            .frame(width: max(4, width), height: max(6, height))
            .contentShape(Rectangle())
            .onTapGesture {
                toggle(row: row, step: step, part: part)
            }
            .accessibilityLabel("\(part.shortLabel) step \(step + 1)")
            .accessibilityValue(on ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Helpers

    private func isOn(row: Int, step: Int) -> Bool {
        guard row < grid.count, step < grid[row].count else { return false }
        return grid[row][step]
    }

    private func toggle(row: Int, step: Int, part: MXDrumPart) {
        let wasOn = isOn(row: row, step: step)
        grid = MXDrumStepSequencer.toggling(grid, row: row, step: step)
        // Preview only when turning a step on (BandLab pad click feel).
        if !wasOn {
            let note = MXDrumStepSequencer.primaryNote(for: part)
            onPreviewHit?(note, MXDrumStepSequencer.defaultVelocity)
        }
    }
}
