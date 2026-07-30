import SwiftUI

/// Profile + local project library (Week 8 / Week 23 polish).
struct MyMixView: View {
    var onOpenProject: (MXProject) -> Void
    var onLogin: () -> Void

    @State private var auth = MXAuthSession.shared
    @State private var cloudSync = MXCloudSyncSpine.shared
    @State private var items: [MyMixItem] = []
    @State private var social = MXSocialStore.shared
    @State private var mixCount = 0
    @State private var publishedCount = 0
    @State private var collaboratorCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                profileHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                statsRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                Text("My Mix")
                    .font(MXFont.displayTitle())
                    .foregroundStyle(MXColor.white)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                if items.isEmpty {
                    emptyMixes
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            mixRow(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MXColor.surface.ignoresSafeArea())
        .onAppear { reload() }
    }

    // MARK: - Profile

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if auth.isSignedIn {
                HStack(spacing: 14) {
                    profileAvatar(initial: profileInitial)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.displayName ?? "Creator")
                            .font(MXFont.sectionTitle())
                            .foregroundStyle(MXColor.white)
                        if let email = auth.email {
                            Text(email)
                                .font(MXFont.caption())
                                .foregroundStyle(MXColor.grey)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Button("Sign out") {
                    auth.signOut()
                    reload()
                }
                .font(MXFont.smallButton())
                .foregroundStyle(MXColor.grey)

                // Week 72 — BandLab-style cloud sync status (stub, no network).
                cloudSyncRow
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        profileAvatar(initial: "?")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Guest")
                                .font(MXFont.sectionTitle())
                                .foregroundStyle(MXColor.white)
                            Text("Sign in to publish and sync your profile.")
                                .font(MXFont.caption())
                                .foregroundStyle(MXColor.grey)
                        }
                    }
                    Text("Local only — projects stay on this device.")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey.opacity(0.85))
                    MXButton("Sign in", systemImage: "person.crop.circle", kind: .prime, size: .big, icon: .leading) {
                        onLogin()
                    }
                }
            }
        }
    }

    private var cloudSyncRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: auth.cloudLinked ? "icloud" : "icloud.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(auth.cloudLinked ? MXColor.accent : MXColor.grey)
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.cloudLinked ? "Cloud sync" : "Local only")
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.white)
                    Text(cloudSync.statusLine(cloudLinked: auth.cloudLinked))
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if auth.cloudLinked {
                    Button {
                        _ = cloudSync.syncNow(cloudLinked: auth.cloudLinked)
                    } label: {
                        Text(cloudSync.status == .syncing ? "…" : "Sync now")
                            .font(MXFont.smallButton())
                            .foregroundStyle(MXColor.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(cloudSync.status == .syncing)
                    .accessibilityLabel("Sync now")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MXColor.layer2)
            )
            Text("Stub sync — no remote backend yet")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey.opacity(0.7))
        }
    }

    private var profileInitial: String {
        let source = auth.displayName ?? auth.email ?? "?"
        return String(source.prefix(1)).uppercased()
    }

    private func profileAvatar(initial: String) -> some View {
        Circle()
            .fill(auth.isSignedIn ? MXColor.accent.opacity(0.2) : MXColor.layer2)
            .frame(width: 52, height: 52)
            .overlay {
                Text(initial)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(auth.isSignedIn ? MXColor.accent : MXColor.grey)
            }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(value: "\(mixCount)", label: "Mixes")
            statTile(value: "\(publishedCount)", label: "Published")
            statTile(value: "\(collaboratorCount)", label: "Collabs")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)
            Text(label)
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MXColor.surfaceRaised)
        )
    }

    private var emptyMixes: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.square")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(MXColor.accent)
            Text("No mixes yet")
                .font(MXFont.mediumButton())
                .foregroundStyle(MXColor.white)
            Text("Create → record or import, export, then your projects show up here.")
                .font(MXFont.body2())
                .foregroundStyle(MXColor.grey)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func mixRow(_ item: MyMixItem) -> some View {
        Button {
            if let project = item.project {
                onOpenProject(project)
            } else if let projectID = item.projectID,
                      let project = try? MXProjectStore.shared.load(id: projectID) {
                onOpenProject(project)
            }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.layer2)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: item.isPublished ? "globe" : "waveform")
                            .foregroundStyle(item.isPublished ? MXColor.teal : MXColor.accent)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(MXFont.mediumButton())
                            .foregroundStyle(MXColor.white)
                            .lineLimit(1)
                        if item.isPublished {
                            Text("Published")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MXColor.teal)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(MXColor.teal.opacity(0.15))
                                )
                        }
                    }
                    Text(item.subtitle)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.project != nil || item.projectID != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MXColor.grey)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MXColor.surfaceRaised)
            )
        }
        .buttonStyle(.plain)
        .disabled(item.project == nil && item.projectID == nil)
    }

    private func reload() {
        auth.load()
        social.load()
        let projects = MXProjectStore.shared.listProjects()
        items = Self.buildItems(
            projects: projects,
            posts: social.posts,
            authorID: auth.userID
        )
        mixCount = projects.count
        publishedCount = items.filter(\.isPublished).count
        collaboratorCount = projects.reduce(0) { $0 + $1.collaborators.count }
    }
}

// MARK: - Item model

struct MyMixItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var project: MXProject?
    var projectID: UUID?
    var isPublished: Bool
    var sortDate: Date
}

extension MyMixView {
    static func buildItems(
        projects: [MXProject],
        posts: [MXSocialStore.Post],
        authorID: String?
    ) -> [MyMixItem] {
        let userPosts = authorID.map { id in posts.filter { $0.authorID == id } } ?? []
        let publishedProjectIDs = Set(userPosts.compactMap(\.projectID))

        var items: [MyMixItem] = projects.map { project in
            let post = userPosts.first { $0.projectID == project.id }
            return MyMixItem(
                id: project.id.uuidString,
                title: project.name,
                subtitle: "\(project.tracks.count) tracks · \(Int(project.bpm)) BPM · \(project.modifiedAt.formatted(date: .abbreviated, time: .shortened))",
                project: project,
                projectID: project.id,
                isPublished: post != nil || publishedProjectIDs.contains(project.id),
                sortDate: post?.createdAt ?? project.modifiedAt
            )
        }

        let knownProjectIDs = Set(projects.map(\.id))
        for post in userPosts where post.projectID.map({ !knownProjectIDs.contains($0) }) ?? true {
            guard !items.contains(where: { $0.id == post.id.uuidString }) else { continue }
            items.append(
                MyMixItem(
                    id: post.id.uuidString,
                    title: post.title,
                    subtitle: "Published · \(post.durationLabel) · \(post.createdAt.formatted(date: .abbreviated, time: .shortened))",
                    project: nil,
                    projectID: post.projectID,
                    isPublished: true,
                    sortDate: post.createdAt
                )
            )
        }

        return items.sorted { $0.sortDate > $1.sortDate }
    }
}
