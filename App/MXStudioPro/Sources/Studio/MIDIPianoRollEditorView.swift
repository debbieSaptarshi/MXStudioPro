import SwiftUI

/// Cubasis / GarageBand / Logic–lite piano roll editor (Weeks 55 / 58).
///
/// Drag notes to change start (X) and pitch (Y). Drag the trailing edge to
/// change length. Velocity lane under the grid edits velocity (1…127).
/// Tap empty space to add a note; tap a selected note again to delete.
public struct MIDIPianoRollEditorView: View {
    public let notes: [MXMIDINote]
    public let lengthBeats: Double
    public var onMove: (_ id: UUID, _ startBeat: Double, _ pitch: UInt8) -> Void
    public var onResize: (_ id: UUID, _ lengthBeats: Double) -> Void
    public var onVelocity: (_ id: UUID, _ velocity: UInt8) -> Void
    public var onMoveEnded: (() -> Void)?
    public var onAdd: (_ startBeat: Double, _ pitch: UInt8) -> Void
    public var onDelete: (_ id: UUID) -> Void

    @State private var selectedNoteID: UUID?
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var rollHeight: CGFloat { isLandscape ? 96 : 132 }
    private var velocityHeight: CGFloat { isLandscape ? 28 : 36 }
    private var surfaceHeight: CGFloat { rollHeight + velocityHeight + 28 }

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
        onMove: @escaping (_ id: UUID, _ startBeat: Double, _ pitch: UInt8) -> Void,
        onResize: @escaping (_ id: UUID, _ lengthBeats: Double) -> Void = { _, _ in },
        onVelocity: @escaping (_ id: UUID, _ velocity: UInt8) -> Void = { _, _ in },
        onMoveEnded: (() -> Void)? = nil,
        onAdd: @escaping (_ startBeat: Double, _ pitch: UInt8) -> Void,
        onDelete: @escaping (_ id: UUID) -> Void
    ) {
        self.notes = notes
        self.lengthBeats = lengthBeats
        self.onMove = onMove
        self.onResize = onResize
        self.onVelocity = onVelocity
        self.onMoveEnded = onMoveEnded
        self.onAdd = onAdd
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Piano Roll")
                    .font(MXFont.smallButton())
                    .foregroundStyle(MXColor.lightGrey)
                Spacer()
                Text("Drag · edge = length · Vel lane")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
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

    // MARK: - Roll

    private var rollGrid: some View {
        GeometryReader { geo in
            let beats = max(lengthBeats, 0.25)
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            let rowH = h / CGFloat(pitchSpan)

            ZStack(alignment: .topLeading) {
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
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let start = max(0, Double(location.x / w) * beats)
                let pitchRow = min(pitchSpan - 1, max(0, Int(location.y / rowH)))
                let pitch = MXMIDINoteEdit.clampPitch(UInt8(Int(pitchMax) - pitchRow))
                onAdd(start, pitch)
            }
        }
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
        let selected = selectedNoteID == note.id
        let velOpacity = 0.45 + 0.55 * (Double(note.velocity) / 127.0)
        let handleW: CGFloat = max(8, min(14, noteW * 0.25))

        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill((selected ? MXColor.orange : MXColor.orange.opacity(0.75)).opacity(velOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(MXColor.white.opacity(selected ? 0.9 : 0.35), lineWidth: 1)
                )

            // Trailing length handle (Cubasis / Logic).
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(MXColor.white.opacity(selected ? 0.85 : 0.45))
                .frame(width: 3, height: max(4, bodyH - 4))
                .padding(.trailing, 2)
                .frame(width: handleW, height: bodyH, alignment: .trailing)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            selectedNoteID = note.id
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
                    selectedNoteID = note.id
                    let start = max(0, Double(value.location.x / w) * beats)
                    let pitchRow = min(
                        pitchSpan - 1,
                        max(0, Int(value.location.y / rowH))
                    )
                    let pitch = MXMIDINoteEdit.clampPitch(
                        UInt8(Int(pitchMax) - pitchRow)
                    )
                    onMove(note.id, start, pitch)
                }
                .onEnded { _ in
                    onMoveEnded?()
                }
        )
        .onTapGesture {
            if selectedNoteID == note.id {
                onDelete(note.id)
                selectedNoteID = nil
            } else {
                selectedNoteID = note.id
            }
        }
        .accessibilityLabel("MIDI note")
        .accessibilityValue(
            "Pitch \(note.note), velocity \(note.velocity), length \(String(format: "%.2f", note.lengthBeats)) at beat \(String(format: "%.2f", note.startBeat))"
        )
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
                    let selected = selectedNoteID == note.id
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(selected ? MXColor.orange : MXColor.orange.opacity(0.7))
                        .frame(width: max(4, noteW - 2), height: barH)
                        .position(x: x + noteW / 2, y: h - barH / 2)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    selectedNoteID = note.id
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
