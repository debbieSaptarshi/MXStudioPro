import SwiftUI
import UIKit
import MXStudioEngine

/// BandLab-style export / publish sheet (Week 21).
struct StudioExportSheet: View {
    @Bindable var session: StudioSessionController
    var isSignedIn: Bool
    var onDismiss: () -> Void
    var onViewSocials: () -> Void

    @State private var phase: Phase = .options
    @State private var caption: String = ""
    @State private var lastBounce: StudioBounceExporter.Result?
    @State private var publishedPost: MXSocialStore.Post?
    @State private var showShare = false
    @State private var shareURLs: [URL] = []
    /// Reels / TikTok loudness (~−14 LUFS) vs peak normalize (~−1 dBFS).
    @State private var useReelsLoudness = true
    /// CapCut / Instagram vertical MP4 (Week 78).
    @State private var includeReelsVideo = false
    /// 24-bit PCM WAV for stem export (Week 88).
    @State private var use24BitStems = false
    @State private var lastStems: StudioBounceExporter.StemsResult?

    private enum Phase: Equatable {
        case options
        case publishForm
        case working(String)
        case shareSuccess(format: String)
        case publishSuccess
        case linkCopied
        case error(message: String, retry: RetryAction)
    }

    private enum RetryAction: Equatable {
        case share
        case stems
        case reelsVideo
        case publish
        case copyLink
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MXColor.surface.ignoresSafeArea()

                switch phase {
                case .options:
                    optionsContent
                case .publishForm:
                    publishFormContent
                case .working(let label):
                    workingContent(label)
                case .shareSuccess(let format):
                    successContent(
                        title: "Export ready",
                        subtitle: "\(session.project.name) · \(format)",
                        primaryTitle: "Share files",
                        primaryAction: presentShare,
                        secondaryTitle: "Done",
                        secondaryAction: onDismiss,
                        loudnessReport: lastBounce.map(\.loudnessReport),
                        stemResults: lastStems
                    )
                case .publishSuccess:
                    successContent(
                        title: "Published to Socials",
                        subtitle: publishedPost?.title ?? session.project.name,
                        primaryTitle: "View on Socials",
                        primaryAction: {
                            onDismiss()
                            onViewSocials()
                        },
                        secondaryTitle: "Done",
                        secondaryAction: onDismiss
                    )
                case .linkCopied:
                    successContent(
                        title: "Link copied",
                        subtitle: "Paste anywhere to share your mix.",
                        primaryTitle: "Done",
                        primaryAction: onDismiss,
                        secondaryTitle: nil,
                        secondaryAction: nil
                    )
                case .error(let message, let retry):
                    errorContent(message: message, retry: retry)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isWorking {
                        Button("Close", action: onDismiss)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            caption = session.project.name
        }
        .sheet(isPresented: $showShare) {
            StudioShareSheet(urls: shareURLs)
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    // MARK: - Options

    private var optionsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.project.name)
                    .font(MXFont.sectionTitle())
                    .foregroundStyle(MXColor.white)
                Text("Bounce your mix, then share or publish.")
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.grey)
            }
            .padding(.top, 8)

            Toggle(isOn: $useReelsLoudness) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reels loudness (−14 LUFS)")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    Text(useReelsLoudness
                         ? "Target social platforms; peak-capped after."
                         : "Peak normalize to ~−1 dBFS instead.")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                }
            }
            .tint(MXColor.accent)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MXColor.layer2)
            )

            Toggle(isOn: $includeReelsVideo) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reels video (9:16 MP4)")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    Text("Gradient + title over bounced mix for Instagram / TikTok.")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                }
            }
            .tint(MXColor.accent)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MXColor.layer2)
            )

            Toggle(isOn: $use24BitStems) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("24-bit stem WAV")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    Text("Higher bit depth for stem export; M4A stays AAC.")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                }
            }
            .tint(MXColor.accent)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MXColor.layer2)
            )

            VStack(spacing: 10) {
                exportOption(
                    title: "Share File",
                    subtitle: includeReelsVideo
                        ? "WAV + M4A + vertical MP4…"
                        : "WAV + M4A to Files, AirDrop, Messages…",
                    systemImage: "square.and.arrow.up",
                    tint: MXColor.accent
                ) {
                    Task { await shareFiles() }
                }

                exportOption(
                    title: "Share Reels video",
                    subtitle: "720×1280 MP4 with mix audio",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    tint: MXColor.orange
                ) {
                    Task { await shareReelsVideo() }
                }

                exportOption(
                    title: "Export stems",
                    subtitle: use24BitStems
                        ? "One 24-bit WAV + M4A per track with loudness cards"
                        : "One WAV + M4A per track (ignores mute/solo)",
                    systemImage: "square.stack.3d.up",
                    tint: MXColor.teal
                ) {
                    Task { await shareStems() }
                }

                exportOption(
                    title: "Publish to Socials",
                    subtitle: isSignedIn ? "Post to your feed with optional caption" : "Sign in required",
                    systemImage: "globe",
                    tint: MXColor.teal,
                    disabled: !isSignedIn
                ) {
                    phase = .publishForm
                }

                if copyLinkURL != nil {
                    exportOption(
                        title: "Copy link",
                        subtitle: "Local share URL for this mix",
                        systemImage: "link",
                        tint: MXColor.orange
                    ) {
                        copyLink()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func exportOption(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    Text(subtitle)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MXColor.grey)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MXColor.layer2)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    // MARK: - Publish form

    private var publishFormContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Publish to Socials")
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Caption (optional)")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                TextField("What's this mix about?", text: $caption, axis: .vertical)
                    .lineLimit(3...6)
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.white)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MXColor.layer2)
                    )
            }

            Button {
                Task { await publishToSocials() }
            } label: {
                Text("Publish")
                    .font(MXFont.mediumButton())
                    .foregroundStyle(MXColor.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MXColor.accent)
                    )
            }
            .buttonStyle(.plain)

            Button("Back") {
                phase = .options
            }
            .font(MXFont.body2())
            .foregroundStyle(MXColor.grey)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    // MARK: - Working / success / error

    private func workingContent(_ label: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(MXColor.accent)
                .scaleEffect(1.2)
            Text(label)
                .font(MXFont.mediumButton())
                .foregroundStyle(MXColor.white)
            Text(session.project.name)
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func successContent(
        title: String,
        subtitle: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?,
        loudnessReport: MXLoudness.Report? = nil,
        stemResults: StudioBounceExporter.StemsResult? = nil
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(MXColor.accent)
            VStack(spacing: 8) {
                Text(title)
                    .font(MXFont.sectionTitle())
                    .foregroundStyle(MXColor.white)
                Text(subtitle)
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.grey)
                    .multilineTextAlignment(.center)
                if let report = loudnessReport {
                    loudnessReportCard(report)
                }
                if let stems = stemResults {
                    stemLoudnessCards(stems)
                }
            }
            Spacer()
            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MXColor.accent)
                        )
                }
                .buttonStyle(.plain)

                if let secondaryTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(MXFont.body2())
                            .foregroundStyle(MXColor.lightGrey)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// Week 71 — YouTube / Reels-style loudness readout after bounce (approx, not certified).
    private func loudnessReportCard(_ report: MXLoudness.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Loudness report")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
            HStack {
                Text("Integrated")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.lightGrey)
                Spacer()
                Text(report.integratedLUFS.isFinite
                     ? String(format: "%.1f LUFS", report.integratedLUFS)
                     : "—")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.white)
                    .monospacedDigit()
            }
            if let target = report.targetLUFS {
                HStack {
                    Text("Target")
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.lightGrey)
                    Spacer()
                    Text(String(format: "%.0f LUFS", target))
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.white)
                        .monospacedDigit()
                }
                if let headroom = report.headroomLU, headroom.isFinite {
                    HStack {
                        Text("Headroom")
                            .font(MXFont.body3())
                            .foregroundStyle(MXColor.lightGrey)
                        Spacer()
                        Text(String(format: "%+.1f LU", headroom))
                            .font(MXFont.body3())
                            .foregroundStyle(headroom >= 0 ? MXColor.accent : MXColor.orange)
                            .monospacedDigit()
                    }
                }
            }
            HStack {
                Text("True peak")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.lightGrey)
                Spacer()
                Text(report.truePeakDBFS.isFinite
                     ? String(format: "%.1f dBFS", report.truePeakDBFS)
                     : "—")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.white)
                    .monospacedDigit()
            }
            Text("K-weighted LUFS · not broadcast-certified")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey.opacity(0.75))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.layer2)
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loudness report")
    }

    /// Week 88 — per-stem integrated LUFS cards (BandLab / Ableton stem export).
    private func stemLoudnessCards(_ result: StudioBounceExporter.StemsResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stem loudness")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
            ForEach(result.stems, id: \.trackID) { stem in
                HStack {
                    Text(stem.trackName)
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.white)
                        .lineLimit(1)
                    Spacer()
                    if let lufs = stem.integratedLUFS, lufs.isFinite {
                        Text(String(format: "%.1f LUFS", lufs))
                            .font(MXFont.body3())
                            .foregroundStyle(MXColor.lightGrey)
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(MXFont.body3())
                            .foregroundStyle(MXColor.grey)
                    }
                }
            }
            Text("K-weighted per stem · not broadcast-certified")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey.opacity(0.75))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.layer2)
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func errorContent(message: String, retry: RetryAction) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(MXColor.red)
            VStack(spacing: 8) {
                Text("Export failed")
                    .font(MXFont.sectionTitle())
                    .foregroundStyle(MXColor.white)
                Text(message)
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.grey)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            VStack(spacing: 10) {
                Button {
                    switch retry {
                    case .share: Task { await shareFiles() }
                    case .stems: Task { await shareStems() }
                    case .reelsVideo: Task { await shareReelsVideo() }
                    case .publish: Task { await publishToSocials() }
                    case .copyLink: copyLink()
                    }
                } label: {
                    Text("Try again")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MXColor.accent)
                        )
                }
                .buttonStyle(.plain)

                Button("Back") {
                    phase = retry == .publish ? .publishForm : .options
                }
                .font(MXFont.body2())
                .foregroundStyle(MXColor.grey)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Actions

    private var copyLinkURL: URL? {
        if let post = MXSocialStore.shared.post(forProjectID: session.project.id),
           let url = MXSocialStore.shared.publicURL(for: post) {
            return url
        }
        if let m4a = session.lastExportURLs.last(where: { $0.pathExtension.lowercased() == "m4a" }) {
            return m4a
        }
        if let wav = session.lastExportURLs.first(where: { $0.pathExtension.lowercased() == "wav" }) {
            return wav
        }
        return nil
    }

    @MainActor
    private func shareFiles() async {
        phase = .working(includeReelsVideo ? "Bouncing + rendering Reels…" : "Bouncing mix…")
        do {
            let mode: StudioBounceExporter.LoudnessMode = useReelsLoudness ? .reelsLUFS : .peakNormalize
            if includeReelsVideo {
                let pair = try await session.exportReelsVideo(normalize: true, loudnessMode: mode)
                lastBounce = pair.bounce
                shareURLs = [pair.bounce.wavURL, pair.bounce.m4aURL, pair.video.mp4URL]
                let loud = mode == .reelsLUFS ? "−14 LUFS" : "peak"
                phase = .shareSuccess(
                    format: "\(pair.video.size.width)×\(pair.video.size.height) MP4 + WAV/M4A · \(loud)"
                )
            } else {
                let result = try await session.bounceMix(normalize: true, loudnessMode: mode)
                lastBounce = result
                shareURLs = [result.wavURL, result.m4aURL]
                let format = mode == .reelsLUFS ? "WAV + M4A · −14 LUFS" : "WAV + M4A · peak"
                phase = .shareSuccess(format: format)
            }
        } catch {
            phase = .error(message: error.localizedDescription, retry: .share)
        }
    }

    @MainActor
    private func shareReelsVideo() async {
        phase = .working("Rendering Reels video…")
        do {
            let mode: StudioBounceExporter.LoudnessMode = useReelsLoudness ? .reelsLUFS : .peakNormalize
            let pair = try await session.exportReelsVideo(normalize: true, loudnessMode: mode)
            lastBounce = pair.bounce
            shareURLs = [pair.video.mp4URL]
            let loud = mode == .reelsLUFS ? "−14 LUFS" : "peak"
            phase = .shareSuccess(
                format: "\(pair.video.size.width)×\(pair.video.size.height) MP4 · \(loud)"
            )
        } catch {
            phase = .error(message: error.localizedDescription, retry: .reelsVideo)
        }
    }

    @MainActor
    private func shareStems() async {
        phase = .working("Exporting stems…")
        do {
            let mode: StudioBounceExporter.LoudnessMode = useReelsLoudness ? .reelsLUFS : .peakNormalize
            let bitDepth: StudioBounceExporter.WAVBitDepth = use24BitStems ? .bit24 : .bit16
            let result = try await session.bounceStems(
                normalize: true,
                loudnessMode: mode,
                wavBitDepth: bitDepth
            )
            lastStems = result
            lastBounce = nil
            shareURLs = result.allURLs
            let count = result.stems.count
            let loud = mode == .reelsLUFS ? "−14 LUFS" : "peak"
            let depth = use24BitStems ? "24-bit WAV" : "WAV"
            phase = .shareSuccess(
                format: "\(count) stem\(count == 1 ? "" : "s") · \(depth) + M4A · \(loud)"
            )
        } catch {
            phase = .error(message: error.localizedDescription, retry: .stems)
        }
    }

    @MainActor
    private func publishToSocials() async {
        guard isSignedIn else {
            phase = .error(message: "Sign in to publish.", retry: .publish)
            return
        }
        phase = .working("Bouncing & publishing…")
        let pendingRemix = pendingRemixOfPostID
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = trimmedCaption.isEmpty ? session.project.name : trimmedCaption
        do {
            let mode: StudioBounceExporter.LoudnessMode = useReelsLoudness ? .reelsLUFS : .peakNormalize
            let result = try await session.bounceMix(normalize: true, loudnessMode: mode)
            lastBounce = result
            let post = try MXSocialStore.shared.publish(
                project: session.project,
                audioSourceURL: result.m4aURL,
                caption: finalCaption,
                auth: MXAuthSession.shared,
                remixOfPostID: pendingRemix
            )
            publishedPost = post
            UserDefaults.standard.removeObject(forKey: "mxstudio.pendingRemixOfPostID")
            phase = .publishSuccess
        } catch {
            phase = .error(message: error.localizedDescription, retry: .publish)
        }
    }

    private func copyLink() {
        guard let url = copyLinkURL else {
            phase = .error(message: "No shareable link yet — export or publish first.", retry: .copyLink)
            return
        }
        UIPasteboard.general.url = url
        phase = .linkCopied
    }

    private func presentShare() {
        showShare = true
    }

    private var pendingRemixOfPostID: UUID? {
        guard let raw = UserDefaults.standard.string(forKey: "mxstudio.pendingRemixOfPostID") else {
            return nil
        }
        return UUID(uuidString: raw)
    }
}

// MARK: - Share sheet (shared with StudioView)

struct StudioShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
