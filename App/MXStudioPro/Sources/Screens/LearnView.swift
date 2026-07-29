import SwiftUI

/// Learn tab home — static lesson cards with links into Studio and the tuner.
struct LearnView: View {
    var onOpenStudio: (StudioPreset) -> Void
    @Binding var openTunerOnAppear: Bool

    @State private var showTuner = false

    init(
        onOpenStudio: @escaping (StudioPreset) -> Void,
        openTunerOnAppear: Binding<Bool> = .constant(false)
    ) {
        self.onOpenStudio = onOpenStudio
        self._openTunerOnAppear = openTunerOnAppear
    }

    private struct Lesson: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color
    }

    private let lessons: [Lesson] = [
        Lesson(
            id: "vocal",
            title: "First vocal take",
            subtitle: "Arm the mic, hit record, and land your first clip on the beat grid.",
            icon: "mic.fill",
            tint: MXColor.pink
        ),
        Lesson(
            id: "beat",
            title: "Layer a beat",
            subtitle: "Add a second track — import a loop or record over your vocal.",
            icon: "waveform",
            tint: MXColor.teal
        ),
        Lesson(
            id: "tuner",
            title: "Tune your guitar",
            subtitle: "Use the built-in chromatic tuner before you record.",
            icon: "tuningfork",
            tint: MXColor.accent
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Short guides to get you recording faster.")
                        .font(MXFont.body2())
                        .foregroundStyle(MXColor.lightGrey)

                    ForEach(lessons) { lesson in
                        lessonCard(lesson)
                    }
                }
                .padding(16)
            }
        }
        .background(MXColor.surface.ignoresSafeArea())
        .sheet(isPresented: $showTuner) {
            TunerView(onClose: { showTuner = false })
                .preferredColorScheme(.dark)
        }
        .onAppear {
            if openTunerOnAppear {
                showTuner = true
                openTunerOnAppear = false
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Learn")
                    .font(MXFont.sectionTitle())
                    .foregroundStyle(MXColor.white)
                Text("3 quick lessons")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            Spacer()
            Button {
                showTuner = true
            } label: {
                Image(systemName: "tuningfork")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MXColor.accent)
                    .frame(width: 20, height: 20)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.layer2)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MXColor.layer2).frame(height: 1)
        }
    }

    private func lessonCard(_ lesson: Lesson) -> some View {
        Button {
            switch lesson.id {
            case "vocal":
                onOpenStudio(.vocal)
            case "beat":
                onOpenStudio(.vocal)
            case "tuner":
                showTuner = true
            default:
                break
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: lesson.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(lesson.tint)
                    .frame(width: 28, height: 28)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.layer2)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title)
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    Text(lesson.subtitle)
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.grey)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MXColor.grey)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MXColor.surfaceRaised)
                    .shadow(color: Color.black.opacity(0.5), radius: 1, x: 1.5, y: -1.5)
                    .shadow(color: Color.white.opacity(0.1), radius: 1, x: -1.5, y: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Learn") {
    LearnView(onOpenStudio: { _ in })
}
