import SwiftUI

/// One-octave + C on-screen keyboard for Week 15 Virtual Instrument.
struct PianoKeyboardView: View {
    var onNoteOn: (UInt8) -> Void
    var onNoteOff: (UInt8) -> Void

    private let whiteNotes: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72] // C4…C5
    private let blackNotes: [(UInt8, Int)] = [
        (61, 0), (63, 1), (66, 3), (68, 4), (70, 5),
    ] // relative to white index before gap

    @State private var activeNotes: Set<UInt8> = []

    var body: some View {
        GeometryReader { geo in
            let whiteW = geo.size.width / CGFloat(whiteNotes.count)
            let blackW = whiteW * 0.62
            let blackH = geo.size.height * 0.58

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(whiteNotes, id: \.self) { note in
                        keyView(
                            note: note,
                            isBlack: false,
                            width: whiteW,
                            height: geo.size.height
                        )
                    }
                }

                ForEach(blackNotes, id: \.0) { note, whiteIndex in
                    keyView(
                        note: note,
                        isBlack: true,
                        width: blackW,
                        height: blackH
                    )
                    .offset(x: CGFloat(whiteIndex + 1) * whiteW - blackW / 2)
                }
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MXColor.surfaceRaised)
    }

    private func keyView(note: UInt8, isBlack: Bool, width: CGFloat, height: CGFloat) -> some View {
        let active = activeNotes.contains(note)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(keyFill(isBlack: isBlack, active: active))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(MXColor.layer2, lineWidth: isBlack ? 0 : 0.5)
            }
            .frame(width: width - (isBlack ? 0 : 1), height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press(note) }
                    .onEnded { _ in release(note) }
            )
    }

    private func keyFill(isBlack: Bool, active: Bool) -> Color {
        if active { return MXColor.accent }
        return isBlack ? MXColor.black : MXColor.lightGrey.opacity(0.92)
    }

    private func press(_ note: UInt8) {
        guard !activeNotes.contains(note) else { return }
        activeNotes.insert(note)
        onNoteOn(note)
    }

    private func release(_ note: UInt8) {
        guard activeNotes.contains(note) else { return }
        activeNotes.remove(note)
        onNoteOff(note)
    }
}
