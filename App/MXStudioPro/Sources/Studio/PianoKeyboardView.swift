import SwiftUI

/// GarageBand-lite on-screen keyboard (Figma 95:87783 / Week 33 Virtual Piano).
/// Landscape: compact chrome + shorter keys (Figma Virtual Piano landscape `97:137230`).
/// One octave + top C, with octave shift, hold, and Y→velocity.
struct PianoKeyboardView: View {
    /// note, velocity
    var onNoteOn: (UInt8, UInt8) -> Void
    var onNoteOff: (UInt8) -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var keysHeight: CGFloat { isLandscape ? 72 : 132 }
    private var chromeVerticalPadding: CGFloat { isLandscape ? 4 : 8 }
    private var keysBottomPadding: CGFloat { isLandscape ? 4 : 8 }

    /// Preferred API: velocity is included in `onNoteOn`.
    init(
        onNoteOn: @escaping (UInt8, UInt8) -> Void,
        onNoteOff: @escaping (UInt8) -> Void
    ) {
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
    }

    /// Migration convenience: ignores velocity (call sites can adopt the two-arg form later).
    init(
        onNoteOn: @escaping (UInt8) -> Void,
        onNoteOff: @escaping (UInt8) -> Void
    ) {
        self.onNoteOn = { note, _ in onNoteOn(note) }
        self.onNoteOff = onNoteOff
    }

    private static let minBaseNote: UInt8 = 24 // C1
    private static let maxBaseNote: UInt8 = 96 // C7
    private static let softVelocity: UInt8 = 40
    private static let hardVelocity: UInt8 = 127

    /// Semitone offsets for white keys C…C (one octave + top C).
    private let whiteOffsets: [UInt8] = [0, 2, 4, 5, 7, 9, 11, 12]
    /// (semitone offset, white-key index left of the black key).
    private let blackOffsets: [(UInt8, Int)] = [
        (1, 0), (3, 1), (6, 3), (8, 4), (10, 5),
    ]

    @State private var baseNote: UInt8 = 60 // C4
    @State private var holdEnabled = false
    @State private var activeNotes: Set<UInt8> = []
    /// Notes already handled by the current drag so hold-toggle doesn't flip every frame.
    @State private var gestureArmedNotes: Set<UInt8> = []

    private var whiteNotes: [UInt8] {
        whiteOffsets.map { baseNote &+ $0 }
    }

    private var blackNotes: [(UInt8, Int)] {
        blackOffsets.map { ($0.0 &+ baseNote, $0.1) }
    }

    private var octaveLabel: String {
        "\(noteName(baseNote))–\(noteName(baseNote &+ 12))"
    }

    private var canOctaveDown: Bool {
        Int(baseNote) - 12 >= Int(Self.minBaseNote)
    }

    private var canOctaveUp: Bool {
        Int(baseNote) + 12 <= Int(Self.maxBaseNote)
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeBar
            keysArea
                .frame(height: keysHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.horizontal, isLandscape ? 8 : 12)
                .padding(.bottom, keysBottomPadding)
        }
        .background(MXColor.surfaceRaised)
    }

    // MARK: - Chrome

    private var chromeBar: some View {
        HStack(spacing: 10) {
            octaveControls

            Spacer(minLength: 8)

            Text(octaveLabel)
                .font(MXFont.caption())
                .foregroundStyle(MXColor.lightGrey)
                .monospacedDigit()

            Spacer(minLength: 8)

            holdControls
        }
        .padding(.horizontal, isLandscape ? 8 : 12)
        .padding(.vertical, chromeVerticalPadding)
    }

    private var octaveControls: some View {
        HStack(spacing: isLandscape ? 4 : 6) {
            chromeButton(systemName: "minus", enabled: canOctaveDown) {
                shiftOctave(-1)
            }
            if !isLandscape {
                Text("Oct")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            chromeButton(systemName: "plus", enabled: canOctaveUp) {
                shiftOctave(1)
            }
        }
    }

    private var holdControls: some View {
        HStack(spacing: 6) {
            if !activeNotes.isEmpty && holdEnabled {
                Button {
                    clearHeldNotes()
                } label: {
                    Text("Clear")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(MXColor.layer2)
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                holdEnabled.toggle()
                if !holdEnabled {
                    // Leaving hold: release anything still sounding.
                    clearHeldNotes()
                }
            } label: {
                Text("Hold")
                    .font(MXFont.caption())
                    .foregroundStyle(holdEnabled ? MXColor.black : MXColor.lightGrey)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(holdEnabled ? MXColor.orange : MXColor.layer2)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func chromeButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let side: CGFloat = isLandscape ? 24 : 28
        return Button(action: action) {
            Image(systemName: systemName)
                .font(MXFont.caption())
                .foregroundStyle(enabled ? MXColor.lightGrey : MXColor.grey.opacity(0.45))
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MXColor.layer2)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Keys

    private var keysArea: some View {
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
                    .onChanged { value in
                        handleKeyChanged(note: note, locationY: value.location.y, keyHeight: height)
                    }
                    .onEnded { _ in
                        handleKeyEnded(note: note)
                    }
            )
    }

    private func keyFill(isBlack: Bool, active: Bool) -> Color {
        if active { return MXColor.orange }
        return isBlack ? MXColor.black : MXColor.lightGrey.opacity(0.92)
    }

    // MARK: - Interaction

    private func handleKeyChanged(note: UInt8, locationY: CGFloat, keyHeight: CGFloat) {
        guard !gestureArmedNotes.contains(note) else { return }
        gestureArmedNotes.insert(note)

        if holdEnabled, activeNotes.contains(note) {
            // Tap an already-held note to release it.
            release(note)
            return
        }

        let velocity = velocity(forY: locationY, height: keyHeight)
        press(note, velocity: velocity)
    }

    private func handleKeyEnded(note: UInt8) {
        gestureArmedNotes.remove(note)
        guard !holdEnabled else { return }
        release(note)
    }

    private func press(_ note: UInt8, velocity: UInt8) {
        guard !activeNotes.contains(note) else { return }
        activeNotes.insert(note)
        onNoteOn(note, velocity)
    }

    private func release(_ note: UInt8) {
        guard activeNotes.contains(note) else { return }
        activeNotes.remove(note)
        onNoteOff(note)
    }

    private func clearHeldNotes() {
        let sounding = activeNotes
        activeNotes.removeAll()
        gestureArmedNotes.removeAll()
        for note in sounding {
            onNoteOff(note)
        }
    }

    private func shiftOctave(_ steps: Int) {
        let next = Int(baseNote) + steps * 12
        guard next >= Int(Self.minBaseNote), next <= Int(Self.maxBaseNote) else { return }
        clearHeldNotes()
        baseNote = UInt8(next)
    }

    /// Bottom of key ≈ soft (40), top ≈ hard (127). Uses DragGesture location.y.
    private func velocity(forY y: CGFloat, height: CGFloat) -> UInt8 {
        guard height > 0 else { return 100 }
        let clampedY = min(max(y, 0), height)
        // y=0 (top) → hard; y=height (bottom) → soft
        let t = 1 - Double(clampedY / height)
        let soft = Double(Self.softVelocity)
        let hard = Double(Self.hardVelocity)
        let value = soft + (hard - soft) * t
        return UInt8(min(127, max(1, Int(value.rounded()))))
    }

    private func noteName(_ note: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pitch = Int(note)
        let name = names[pitch % 12]
        let octave = pitch / 12 - 1
        return "\(name)\(octave)"
    }
}
