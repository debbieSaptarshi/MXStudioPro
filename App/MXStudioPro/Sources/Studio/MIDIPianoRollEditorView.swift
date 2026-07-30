import SwiftUI

/// Cubasis / GarageBand–lite piano roll editor (Week 55).
///
/// Drag notes to change start (X) and pitch (Y). Tap empty space to add a note;
/// tap a selected note again to delete.
public struct MIDIPianoRollEditorView: View {
    public let notes: [MXMIDINote]
    public let lengthBeats: Double
    public var onMove: (_ id: UUID, _ startBeat: Double, _ pitch: UInt8) -> Void
    public var onMoveEnded: (() -> Void)?
    public var onAdd: (_ startBeat: Double, _ pitch: UInt8) -> Void
    public var onDelete: (_ id: UUID) -> Void

    @State private var selectedNoteID: UUID?
    @State private var didRecordUndoForDrag = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var surfaceHeight: CGFloat { isLandscape ? 120 : 168 }

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
        onMoveEnded: (() -> Void)? = nil,
        onAdd: @escaping (_ startBeat: Double, _ pitch: UInt8) -> Void,
        onDelete: @escaping (_ id: UUID) -> Void
    ) {
        self.notes = notes
        self.lengthBeats = lengthBeats
        self.onMove = onMove
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
                Text("Drag · tap empty to add · tap again to delete")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            GeometryReader { geo in
                let beats = max(lengthBeats, 0.25)
                let w = max(geo.size.width, 1)
                let h = max(geo.size.height, 1)
                let rowH = h / CGFloat(pitchSpan)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(MXColor.layer2.opacity(0.65))

                    // Beat grid
                    ForEach(0..<Int(ceil(beats)), id: \.self) { beat in
                        let x = CGFloat(Double(beat) / beats) * w
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: h))
                        }
                        .stroke(MXColor.grey.opacity(beat % 4 == 0 ? 0.35 : 0.15), lineWidth: 0.5)
                    }

                    ForEach(notes) { note in
                        let x = CGFloat(note.startBeat / beats) * w
                        let noteW = max(8, CGFloat(note.lengthBeats / beats) * w)
                        let row = Int(pitchMax) - Int(note.note)
                        let y = CGFloat(row) * rowH + 1
                        let selected = selectedNoteID == note.id
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(selected ? MXColor.orange : MXColor.orange.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(MXColor.white.opacity(selected ? 0.9 : 0.35), lineWidth: 1)
                            )
                            .frame(width: noteW, height: max(6, rowH - 2))
                            .position(x: x + noteW / 2, y: y + max(6, rowH - 2) / 2)
                            .gesture(
                                DragGesture(minimumDistance: 2)
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
                            .accessibilityValue("Pitch \(note.note) at beat \(String(format: "%.2f", note.startBeat))")
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
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .frame(height: surfaceHeight)
        .background(MXColor.surfaceRaised)
    }
}
