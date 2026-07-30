import SwiftUI
import MXStudioEngine

/// BandLab / FL Mobile–style drum step sequencer (Weeks 49 / 53 / 57).
///
/// Rows = Kick → Ride; columns = 16ths × bars (1–4). Tap toggles hits;
/// vertical drag on an active cell sets velocity (cell opacity). **Add to timeline**
/// places a MIDI clip at the playhead; **Load** pulls from the selected drums clip.
/// Week 57: pattern library, bar copy/paste, live step cursor during playback.
public struct DrumStepSequencerView: View {
    @Binding var velocityGrid: [[UInt8]]
    @Binding var bars: Int
    /// Highlighted step column while transport plays (`nil` when stopped).
    public var activeStep: Int?
    public var onPreviewHit: ((UInt8, UInt8) -> Void)?
    public var onApply: () -> Void
    public var onClear: () -> Void
    public var onLoadFromClip: (() -> Void)?
    public var canApply: Bool
    public var canLoadFromClip: Bool

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Clipboard for one-bar copy/paste (session-local, not persisted).
    @State private var copiedBar: [[UInt8]]?
    @State private var selectedBarIndex: Int = 0

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var surfaceHeight: CGFloat { isLandscape ? 140 : 200 }

    private let parts = MXDrumStepSequencer.rowParts
    private var stepCount: Int { MXDrumStepSequencer.stepCount(bars: bars) }

    public init(
        velocityGrid: Binding<[[UInt8]]>,
        bars: Binding<Int>,
        activeStep: Int? = nil,
        canApply: Bool = true,
        canLoadFromClip: Bool = false,
        onPreviewHit: ((UInt8, UInt8) -> Void)? = nil,
        onApply: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onLoadFromClip: (() -> Void)? = nil
    ) {
        self._velocityGrid = velocityGrid
        self._bars = bars
        self.activeStep = activeStep
        self.canApply = canApply
        self.canLoadFromClip = canLoadFromClip
        self.onPreviewHit = onPreviewHit
        self.onApply = onApply
        self.onClear = onClear
        self.onLoadFromClip = onLoadFromClip
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerRow
            toolbarRow
            stepGrid
                .padding(.horizontal, isLandscape ? 6 : 10)
                .padding(.bottom, isLandscape ? 4 : 8)
        }
        .frame(height: surfaceHeight)
        .background(MXColor.surfaceRaised)
        .onChange(of: bars) { _, newBars in
            let clamped = MXDrumStepSequencer.clampBars(newBars)
            if clamped != newBars { bars = clamped }
            velocityGrid = MXDrumStepSequencer.resizing(velocityGrid, toBars: clamped)
            if selectedBarIndex >= clamped {
                selectedBarIndex = max(0, clamped - 1)
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("Steps")
                .font(MXFont.smallButton())
                .foregroundStyle(MXColor.lightGrey)

            barPicker

            Spacer(minLength: 2)

            libraryMenu

            if onLoadFromClip != nil {
                Button("Load") {
                    onLoadFromClip?()
                }
                .font(MXFont.caption())
                .foregroundStyle(canLoadFromClip ? MXColor.lightGrey : MXColor.grey)
                .disabled(!canLoadFromClip)
                .accessibilityLabel("Load step pattern from selected clip")
            }

            Button("Clear", action: onClear)
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
                .disabled(!MXDrumStepSequencer.hasHits(velocityGrid))

            Button(action: onApply) {
                Text("Add to timeline")
                    .font(MXFont.caption())
                    .foregroundStyle(
                        canApply && MXDrumStepSequencer.hasHits(velocityGrid)
                            ? MXColor.orange
                            : MXColor.grey
                    )
            }
            .disabled(!canApply || !MXDrumStepSequencer.hasHits(velocityGrid))
            .accessibilityLabel("Add step pattern to timeline")
        }
        .padding(.horizontal, isLandscape ? 8 : 12)
        .padding(.vertical, isLandscape ? 4 : 6)
    }

    private var toolbarRow: some View {
        HStack(spacing: 6) {
            Text("Bar")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)

            ForEach(0..<bars, id: \.self) { index in
                Button {
                    selectedBarIndex = index
                } label: {
                    Text("\(index + 1)")
                        .font(MXFont.caption())
                        .foregroundStyle(selectedBarIndex == index ? MXColor.orange : MXColor.grey)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(selectedBarIndex == index ? MXColor.orange.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select bar \(index + 1)")
                .accessibilityAddTraits(selectedBarIndex == index ? .isSelected : [])
            }

            Spacer(minLength: 2)

            Button("Copy") {
                copiedBar = MXDrumStepSequencer.extractBar(velocityGrid, barIndex: selectedBarIndex)
            }
            .font(MXFont.caption())
            .foregroundStyle(MXColor.lightGrey)
            .accessibilityLabel("Copy bar \(selectedBarIndex + 1)")

            Button("Paste") {
                guard let copiedBar else { return }
                velocityGrid = MXDrumStepSequencer.replacingBar(
                    velocityGrid,
                    barIndex: selectedBarIndex,
                    with: copiedBar
                )
            }
            .font(MXFont.caption())
            .foregroundStyle(copiedBar != nil ? MXColor.lightGrey : MXColor.grey)
            .disabled(copiedBar == nil)
            .accessibilityLabel("Paste into bar \(selectedBarIndex + 1)")
        }
        .padding(.horizontal, isLandscape ? 8 : 12)
        .padding(.bottom, isLandscape ? 2 : 4)
    }

    private var libraryMenu: some View {
        Menu {
            ForEach(MXDrumStepSequencer.PatternPreset.allCases) { preset in
                Button(preset.displayName) {
                    velocityGrid = MXDrumStepSequencer.pattern(preset, bars: bars)
                }
            }
        } label: {
            Text("Library")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.lightGrey)
        }
        .accessibilityLabel("Step pattern library")
    }

    private var barPicker: some View {
        HStack(spacing: 2) {
            ForEach([1, 2, 4], id: \.self) { count in
                Button {
                    bars = count
                } label: {
                    Text("\(count)b")
                        .font(MXFont.caption())
                        .foregroundStyle(bars == count ? MXColor.orange : MXColor.grey)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(bars == count ? MXColor.orange.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(count) bar pattern")
                .accessibilityAddTraits(bars == count ? .isSelected : [])
            }
        }
    }

    // MARK: - Grid

    private var stepGrid: some View {
        GeometryReader { geo in
            let labelW: CGFloat = isLandscape ? 36 : 44
            let spacing: CGFloat = 2
            let rows = CGFloat(parts.count)
            let cols = CGFloat(max(1, stepCount))
            let availW = max(0, geo.size.width - labelW - spacing)
            let cellW = (availW - spacing * (cols - 1)) / cols
            let cellH = (geo.size.height - spacing * (rows - 1)) / rows

            ScrollView(.horizontal, showsIndicators: bars > 1) {
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
                                    width: max(4, cellW),
                                    height: max(6, cellH)
                                )
                            }
                        }
                    }
                }
                .frame(minWidth: geo.size.width)
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
        let vel = velocity(row: row, step: step)
        let on = vel > 0
        let beatAccent = step % 4 == 0
        let barAccent = step % MXDrumStepSequencer.stepsPerBar == 0
        let isCursor = activeStep == step
        let fillOpacity = on ? Double(vel) / 127.0 : 0
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(
                on
                    ? MXColor.orange.opacity(0.35 + 0.65 * fillOpacity)
                    : (beatAccent ? MXColor.layer2 : MXColor.layer2.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        isCursor
                            ? MXColor.white.opacity(0.95)
                            : (on
                                ? MXColor.orange.opacity(0.9)
                                : MXColor.grey.opacity(barAccent ? 0.45 : (beatAccent ? 0.35 : 0.15))),
                        lineWidth: isCursor ? 1.5 : (barAccent ? 1 : 0.5)
                    )
            )
            .overlay(alignment: .top) {
                if isCursor {
                    Capsule()
                        .fill(MXColor.white.opacity(0.9))
                        .frame(width: max(2, width * 0.35), height: 2)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        // FL Mobile: vertical position in the cell sets velocity (top = loud).
                        let h = max(height, 1)
                        let t = 1 - min(1, max(0, value.location.y / h))
                        let clamped = UInt8(min(127, max(1, Int((t * 126 + 1).rounded()))))
                        velocityGrid = MXDrumStepSequencer.settingVelocity(
                            velocityGrid,
                            row: row,
                            step: step,
                            velocity: clamped
                        )
                    }
            )
            .onTapGesture {
                toggle(row: row, step: step, part: part)
            }
            .accessibilityLabel("\(part.shortLabel) step \(step + 1)")
            .accessibilityValue(stepAccessibilityValue(on: on, velocity: vel, isCursor: isCursor))
            .accessibilityAddTraits(.isButton)
    }

    private func stepAccessibilityValue(on: Bool, velocity: UInt8, isCursor: Bool) -> String {
        var parts: [String] = []
        parts.append(on ? "Velocity \(velocity)" : "Off")
        if isCursor { parts.append("Playhead") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    private func velocity(row: Int, step: Int) -> UInt8 {
        guard row < velocityGrid.count, step < velocityGrid[row].count else { return 0 }
        return velocityGrid[row][step]
    }

    private func toggle(row: Int, step: Int, part: MXDrumPart) {
        let wasOn = velocity(row: row, step: step) > 0
        velocityGrid = MXDrumStepSequencer.toggling(velocityGrid, row: row, step: step)
        if !wasOn {
            let note = MXDrumStepSequencer.primaryNote(for: part)
            let vel = velocity(row: row, step: step)
            onPreviewHit?(note, vel > 0 ? vel : MXDrumStepSequencer.defaultVelocity)
        }
    }
}
