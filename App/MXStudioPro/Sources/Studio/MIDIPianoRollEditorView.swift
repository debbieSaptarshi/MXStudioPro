import SwiftUI
import MXStudioEngine

/// Cubasis / GarageBand / Logic–lite piano roll editor (Weeks 55 / 58 / 62 / 68).
///
/// Drag notes to change start (X) and pitch (Y). Drag the trailing edge to
/// change length. Velocity lane under the grid edits velocity (1…127).
///
/// Week 62 adds Cubasis-style multi-select (long-press to toggle membership),
/// batch transpose chrome (±1 / ±12), and a musical scale lock that snaps pitch
/// on add and while dragging.
///
/// Week 68 adds Cubasis / FL Mobile **draw mode**: pencil toggle paints or erases
/// snap cells with a drag stroke (first cell sets paint vs erase polarity).
///
/// Tap empty space to add a note (or clear a non-empty selection). Tap a note
/// to make it the sole selection; tap it again to delete.
public struct MIDIPianoRollEditorView: View {
    public let notes: [MXMIDINote]
    public let lengthBeats: Double
    /// Arrange snap cell size in beats (feeds draw-mode paint length).
    public let snapBeats: Double
    public let allowsScaleLock: Bool
    public var onMove: (_ id: UUID, _ startBeat: Double, _ pitch: UInt8) -> Void
    public var onBatchMove: (_ ids: Set<UUID>, _ deltaStartBeats: Double, _ deltaPitch: Int) -> Void
    public var onResize: (_ id: UUID, _ lengthBeats: Double) -> Void
    public var onVelocity: (_ id: UUID, _ velocity: UInt8) -> Void
    public var onMoveEnded: (() -> Void)?
    public var onAdd: (_ startBeat: Double, _ pitch: UInt8) -> Void
    public var onPaintCell: (_ startBeat: Double, _ pitch: UInt8, _ erase: Bool, _ recordUndo: Bool) -> Bool
    public var onTranspose: (_ ids: Set<UUID>, _ semitones: Int) -> Void
    public var onDelete: (_ id: UUID) -> Void

    @Binding public var scaleLockEnabled: Bool
    @Binding public var scale: MXMIDIScale

    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var isDrawMode = false
    /// First cell of a draw stroke sets paint vs erase for the whole stroke.
    @State private var drawStrokeErasing: Bool?
    @State private var drawVisitedCells: Set<DrawCellKey> = []
    @State private var drawStrokeUndoArmed = true

    // Batch-drag bookkeeping. We track the gesture origin note's original
    // start/pitch and the deltas already applied, then feed `onBatchMove`
    // incremental deltas so repeated calls compose correctly.
    @State private var dragOriginNoteID: UUID?
    @State private var dragIDs: Set<UUID> = []
    @State private var dragOriginStart: Double = 0
    @State private var dragOriginPitch: Int = 0
    @State private var dragAppliedDeltaStart: Double = 0
    @State private var dragAppliedDeltaPitch: Int = 0

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private struct DrawCellKey: Hashable {
        let startMillis: Int
        let pitch: UInt8
        init(startBeat: Double, pitch: UInt8) {
            self.startMillis = Int((startBeat * 1000).rounded())
            self.pitch = pitch
        }
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var rollHeight: CGFloat { isLandscape ? 96 : 132 }
    private var velocityHeight: CGFloat { isLandscape ? 28 : 36 }
    private var chromeExtra: CGFloat { isLandscape ? 4 : 8 }
    private var surfaceHeight: CGFloat { rollHeight + velocityHeight + 28 + chromeExtra }

    private var showsScaleChrome: Bool { allowsScaleLock }
    private var scaleActive: Bool { allowsScaleLock && scaleLockEnabled }
    private var effectiveSnapBeats: Double {
        snapBeats > 0 ? snapBeats : MXMIDINoteEdit.defaultLengthBeats
    }

    private var pitchMin: UInt8 {
        let minN = notes.map(\.note).min() ?? 48
        return MXMIDINoteEdit.clampPitch(UInt8(max(0, Int(minN) - 4)))
    }

    private var pitchMax: UInt8 {
        let maxN = notes.map(\.note).max() ?? 72
        return MXMIDINoteEdit.clampPitch(UInt8(min(127, Int(maxN) + 4)))
    }

    private var pitchSpan: Int {
        max(1, Int(pitchMax) - Int(pitchMin) + 1)
    }

    public init(
        notes: [MXMIDINote],
        lengthBeats: Double,
        snapBeats: Double = MXMIDINoteEdit.defaultLengthBeats,
        scaleLockEnabled: Binding<Bool>,
        scale: Binding<MXMIDIScale>,
        allowsScaleLock: Bool = true,
        onMove: @escaping (_ id: UUID, _ startBeat: Double, _ pitch: UInt8) -> Void,
        onBatchMove: @escaping (_ ids: Set<UUID>, _ deltaStartBeats: Double, _ deltaPitch: Int) -> Void = { _, _, _ in },
        onResize: @escaping (_ id: UUID, _ lengthBeats: Double) -> Void = { _, _ in },
        onVelocity: @escaping (_ id: UUID, _ velocity: UInt8) -> Void = { _, _ in },
        onMoveEnded: (() -> Void)? = nil,
        onAdd: @escaping (_ startBeat: Double, _ pitch: UInt8) -> Void,
        onPaintCell: @escaping (_ startBeat: Double, _ pitch: UInt8, _ erase: Bool, _ recordUndo: Bool) -> Bool = { _, _, _, _ in false },
        onTranspose: @escaping (_ ids: Set<UUID>, _ semitones: Int) -> Void = { _, _ in },
        onDelete: @escaping (_ id: UUID) -> Void
    ) {
        self.notes = notes
        self.lengthBeats = lengthBeats
        self.snapBeats = snapBeats
        self._scaleLockEnabled = scaleLockEnabled
        self._scale = scale
        self.allowsScaleLock = allowsScaleLock
        self.onMove = onMove
        self.onBatchMove = onBatchMove
        self.onResize = onResize
        self.onVelocity = onVelocity
        self.onMoveEnded = onMoveEnded
        self.onAdd = onAdd
        self.onPaintCell = onPaintCell
        self.onTranspose = onTranspose
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            rollGrid
                .frame(height: rollHeight)
                .padding(.horizontal, 8)

            velocityLane
                .frame(height: velocityHeight)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
        }
        .frame(height: surfaceHeight)
        .background(MXColor.surfaceRaised)
    }

    // MARK: - Header chrome

    private var header: some View {
        HStack(spacing: 6) {
            Text("Piano Roll")
                .font(MXFont.smallButton())
                .foregroundStyle(MXColor.lightGrey)
                .lineLimit(1)

            drawModeToggle

            Spacer(minLength: 4)

            if !isDrawMode {
                transposeControls
            }

            if showsScaleChrome {
                scaleControls
            }
        }
    }

    private var drawModeToggle: some View {
        Button {
            isDrawMode.toggle()
            selectedNoteIDs.removeAll()
            resetDrawStroke()
        } label: {
            Image(systemName: isDrawMode ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isDrawMode ? MXColor.white : MXColor.grey)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isDrawMode ? MXColor.orange.opacity(0.85) : MXColor.layer2.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Draw mode")
        .accessibilityValue(isDrawMode ? "On" : "Off")
    }

    private var transposeControls: some View {
        HStack(spacing: 4) {
            transposeButton("−12", -12)
            transposeButton("−1", -1)
            transposeButton("+1", 1)
            transposeButton("+12", 12)
        }
    }

    private func transposeButton(_ title: String, _ semitones: Int) -> some View {
        let enabled = !selectedNoteIDs.isEmpty
        return Button {
            guard !selectedNoteIDs.isEmpty else { return }
            onTranspose(selectedNoteIDs, semitones)
        } label: {
            Text(title)
                .font(MXFont.caption())
                .foregroundStyle(enabled ? MXColor.lightGrey : MXColor.grey)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(MXColor.layer2.opacity(enabled ? 0.7 : 0.35))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Transpose \(semitones > 0 ? "up" : "down") \(abs(semitones)) semitones")
    }

    private var scaleControls: some View {
        HStack(spacing: 4) {
            Button {
                scaleLockEnabled.toggle()
            } label: {
                Text("Scale")
                    .font(MXFont.caption())
                    .foregroundStyle(scaleLockEnabled ? MXColor.white : MXColor.grey)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(scaleLockEnabled ? MXColor.orange.opacity(0.85) : MXColor.layer2.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scale lock")
            .accessibilityValue(scaleLockEnabled ? "On" : "Off")

            Menu {
                Picker("Root", selection: $scale.rootPitchClass) {
                    ForEach(0..<12, id: \.self) { i in
                        Text(MXMIDIScale.rootNames[i]).tag(UInt8(i))
                    }
                }
                Picker("Mode", selection: $scale.mode) {
                    ForEach(MXMIDIScaleMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } label: {
                Text(scale.displayName)
                    .font(MXFont.caption())
                    .foregroundStyle(scaleLockEnabled ? MXColor.lightGrey : MXColor.grey)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.layer2.opacity(0.6))
                    )
            }
            .disabled(!scaleLockEnabled)
            .accessibilityLabel("Scale root and mode")
        }
    }

    // MARK: - Roll

    private var rollGrid: some View {
        GeometryReader { geo in
            let beats = max(lengthBeats, 0.25)
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            let rowH = h / CGFloat(pitchSpan)

            rollGridContent(beats: beats, width: w, height: h, rowH: rowH)
        }
    }

    @ViewBuilder
    private func rollGridContent(
        beats: Double,
        width w: CGFloat,
        height h: CGFloat,
        rowH: CGFloat
    ) -> some View {
        let grid = ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MXColor.layer2.opacity(0.65))

            ForEach(0..<Int(ceil(beats)), id: \.self) { beat in
                let x = CGFloat(Double(beat) / beats) * w
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                }
                .stroke(MXColor.grey.opacity(beat % 4 == 0 ? 0.35 : 0.15), lineWidth: 0.5)
            }

            ForEach(notes) { note in
                noteBlock(note: note, beats: beats, width: w, rowH: rowH)
                    .allowsHitTesting(!isDrawMode)
            }
        }
        .contentShape(Rectangle())

        if isDrawMode {
            grid.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        paintAt(location: value.location, beats: beats, width: w, rowH: rowH)
                    }
                    .onEnded { _ in
                        resetDrawStroke()
                        onMoveEnded?()
                    }
            )
        } else {
            grid.onTapGesture { location in
                if !selectedNoteIDs.isEmpty {
                    selectedNoteIDs.removeAll()
                    return
                }
                let start = max(0, Double(location.x / w) * beats)
                let pitchRow = min(pitchSpan - 1, max(0, Int(location.y / rowH)))
                var pitch = MXMIDINoteEdit.clampPitch(UInt8(Int(pitchMax) - pitchRow))
                if scaleActive {
                    pitch = scale.snapPitch(pitch)
                }
                onAdd(start, pitch)
            }
        }
    }

    private func paintAt(location: CGPoint, beats: Double, width w: CGFloat, rowH: CGFloat) {
        let start = max(0, Double(location.x / w) * beats)
        let pitchRow = min(pitchSpan - 1, max(0, Int(location.y / rowH)))
        var pitch = MXMIDINoteEdit.clampPitch(UInt8(Int(pitchMax) - pitchRow))
        if scaleActive {
            pitch = scale.snapPitch(pitch)
        }
        let cell = MXMIDINoteEdit.cellStart(beat: start, resolution: effectiveSnapBeats)
        let key = DrawCellKey(startBeat: cell, pitch: pitch)
        guard !drawVisitedCells.contains(key) else { return }
        drawVisitedCells.insert(key)

        let erasing: Bool
        if let existing = drawStrokeErasing {
            erasing = existing
        } else {
            let occupied = MXMIDINoteEdit.cellOccupied(
                notes,
                beat: cell,
                pitch: pitch,
                snapBeats: effectiveSnapBeats,
                scale: scaleActive ? scale : nil
            )
            erasing = occupied
            drawStrokeErasing = occupied
        }

        let recordUndo = drawStrokeUndoArmed
        if onPaintCell(cell, pitch, erasing, recordUndo) {
            drawStrokeUndoArmed = false
        }
    }

    private func resetDrawStroke() {
        drawStrokeErasing = nil
        drawVisitedCells.removeAll()
        drawStrokeUndoArmed = true
    }

    private func noteBlock(
        note: MXMIDINote,
        beats: Double,
        width w: CGFloat,
        rowH: CGFloat
    ) -> some View {
        let x = CGFloat(note.startBeat / beats) * w
        let noteW = max(8, CGFloat(note.lengthBeats / beats) * w)
        let row = Int(pitchMax) - Int(note.note)
        let y = CGFloat(row) * rowH + 1
        let bodyH = max(6, rowH - 2)
        let selected = selectedNoteIDs.contains(note.id)
        let velOpacity = 0.45 + 0.55 * (Double(note.velocity) / 127.0)
        let handleW: CGFloat = max(8, min(14, noteW * 0.25))

        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill((selected ? MXColor.orange : MXColor.orange.opacity(0.75)).opacity(velOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(MXColor.white.opacity(selected ? 0.9 : 0.35), lineWidth: 1)
                )

            // Trailing length handle (Cubasis / Logic) — single-note resize.
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(MXColor.white.opacity(selected ? 0.85 : 0.45))
                .frame(width: 3, height: max(4, bodyH - 4))
                .padding(.trailing, 2)
                .frame(width: handleW, height: bodyH, alignment: .trailing)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            selectedNoteIDs = [note.id]
                            let endX = max(x + 8, min(w, x + noteW + value.translation.width))
                            let length = max(0.0625, Double((endX - x) / w) * beats)
                            onResize(note.id, length)
                        }
                        .onEnded { _ in
                            onMoveEnded?()
                        }
                )
                .accessibilityLabel("Resize note length")
        }
        .frame(width: noteW, height: bodyH)
        .position(x: x + noteW / 2, y: y + bodyH / 2)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    beginBatchDragIfNeeded(note: note)
                    let targetStart = max(0, Double(value.location.x / w) * beats)
                    let pitchRow = min(pitchSpan - 1, max(0, Int(value.location.y / rowH)))
                    var targetPitch = Int(MXMIDINoteEdit.clampPitch(UInt8(Int(pitchMax) - pitchRow)))
                    if scaleActive {
                        targetPitch = Int(scale.snapPitch(UInt8(targetPitch)))
                    }
                    let cumulativeStart = targetStart - dragOriginStart
                    let cumulativePitch = targetPitch - dragOriginPitch
                    let incStart = cumulativeStart - dragAppliedDeltaStart
                    let incPitch = cumulativePitch - dragAppliedDeltaPitch
                    if abs(incStart) > 1e-9 || incPitch != 0 {
                        onBatchMove(dragIDs, incStart, incPitch)
                        dragAppliedDeltaStart = cumulativeStart
                        dragAppliedDeltaPitch = cumulativePitch
                    }
                }
                .onEnded { _ in
                    dragOriginNoteID = nil
                    onMoveEnded?()
                }
        )
        .onLongPressGesture(minimumDuration: 0.4) {
            if selectedNoteIDs.contains(note.id) {
                selectedNoteIDs.remove(note.id)
            } else {
                selectedNoteIDs.insert(note.id)
            }
        }
        .onTapGesture {
            if selectedNoteIDs == [note.id] {
                onDelete(note.id)
                selectedNoteIDs.remove(note.id)
            } else {
                selectedNoteIDs = [note.id]
            }
        }
        .accessibilityLabel("MIDI note")
        .accessibilityValue(
            "Pitch \(note.note), velocity \(note.velocity), length \(String(format: "%.2f", note.lengthBeats)) at beat \(String(format: "%.2f", note.startBeat))"
        )
    }

    /// Initialize batch-drag bookkeeping on the first `onChanged` of a gesture.
    private func beginBatchDragIfNeeded(note: MXMIDINote) {
        guard dragOriginNoteID != note.id else { return }
        // Dragging an unselected note selects it first (single-note drag).
        if selectedNoteIDs.contains(note.id) {
            dragIDs = selectedNoteIDs
        } else {
            dragIDs = [note.id]
            selectedNoteIDs = [note.id]
        }
        dragOriginNoteID = note.id
        dragOriginStart = note.startBeat
        dragOriginPitch = Int(note.note)
        dragAppliedDeltaStart = 0
        dragAppliedDeltaPitch = 0
    }

    // MARK: - Velocity lane

    private var velocityLane: some View {
        GeometryReader { geo in
            let beats = max(lengthBeats, 0.25)
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(MXColor.layer2.opacity(0.45))

                Text("Vel")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .padding(.leading, 4)
                    .padding(.top, 2)

                ForEach(notes) { note in
                    let x = CGFloat(note.startBeat / beats) * w
                    let noteW = max(6, CGFloat(note.lengthBeats / beats) * w)
                    let barH = max(4, h * CGFloat(note.velocity) / 127.0)
                    let selected = selectedNoteIDs.contains(note.id)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(selected ? MXColor.orange : MXColor.orange.opacity(0.7))
                        .frame(width: max(4, noteW - 2), height: barH)
                        .position(x: x + noteW / 2, y: h - barH / 2)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    selectedNoteIDs = [note.id]
                                    let t = 1 - min(1, max(0, value.location.y / h))
                                    let vel = UInt8(min(127, max(1, Int((t * 126 + 1).rounded()))))
                                    onVelocity(note.id, vel)
                                }
                                .onEnded { _ in
                                    onMoveEnded?()
                                }
                        )
                        .accessibilityLabel("Velocity for pitch \(note.note)")
                        .accessibilityValue("\(note.velocity)")
                }
            }
        }
    }
}
