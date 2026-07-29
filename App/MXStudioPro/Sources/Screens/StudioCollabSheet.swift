import SwiftUI
import UIKit

/// BandLab-style collab lite sheet (Week 22).
struct StudioCollabSheet: View {
    @Bindable var session: StudioSessionController
    var ownerName: String
    var onDismiss: () -> Void

    @State private var inviteEmail = ""
    @State private var inviteRole: MXCollaboratorRole = .viewer
    @State private var inviteError: String?
    @State private var didCopyLink = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inviteSection
                    collaboratorsSection
                    copyLinkSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(MXColor.surface.ignoresSafeArea())
            .navigationTitle("Collaborators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .foregroundStyle(MXColor.accent)
                }
            }
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite by email")
                .font(MXFont.body2())
                .foregroundStyle(MXColor.white)

            MXInput(
                text: $inviteEmail,
                kind: .oneIcon,
                caption: "Email",
                placeholder: "collaborator@email.com"
            )

            Picker("Role", selection: $inviteRole) {
                ForEach(MXCollaboratorRole.allCases, id: \.self) { role in
                    Text(role.title).tag(role)
                }
            }
            .pickerStyle(.segmented)

            if let inviteError {
                Text(inviteError)
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.accent)
            }

            MXButton("Send invite", systemImage: "person.badge.plus", kind: .prime, size: .big, icon: .leading) {
                sendInvite()
            }
            .disabled(!isValidEmail(inviteEmail))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MXColor.surfaceRaised)
        )
    }

    private var collaboratorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On this project")
                .font(MXFont.body2())
                .foregroundStyle(MXColor.white)

            collaboratorRow(
                email: ownerName,
                subtitle: "Owner",
                role: nil,
                canRemove: false
            )

            ForEach(session.project.collaborators) { collab in
                collaboratorRow(
                    email: collab.email,
                    subtitle: invitedLabel(collab.invitedAt),
                    role: collab.role,
                    canRemove: true,
                    onRemove: { session.removeCollaborator(id: collab.id) }
                )
            }

            if session.project.collaborators.isEmpty {
                Text("No collaborators yet — invite someone above.")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
        }
    }

    private func collaboratorRow(
        email: String,
        subtitle: String,
        role: MXCollaboratorRole?,
        canRemove: Bool,
        onRemove: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(MXColor.layer2)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String(email.prefix(1)).uppercased())
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(email)
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }

            Spacer(minLength: 8)

            if let role {
                MXBadge(role.title, icon: .none)
            }

            if canRemove, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MXColor.grey)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.surfaceRaised)
        )
    }

    private var copyLinkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite link")
                .font(MXFont.body2())
                .foregroundStyle(MXColor.white)

            Text(session.collabInviteURL.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MXColor.grey)
                .lineLimit(2)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MXColor.black)
                )

            MXButton(
                didCopyLink ? "Link copied" : "Copy invite link",
                systemImage: didCopyLink ? "checkmark" : "link",
                kind: .secondary,
                size: .big,
                icon: .leading
            ) {
                UIPasteboard.general.string = session.collabInviteURL.absoluteString
                didCopyLink = true
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MXColor.surfaceRaised)
        )
    }

    private func sendInvite() {
        inviteError = nil
        guard session.addCollaborator(email: inviteEmail, role: inviteRole) else {
            inviteError = "Enter a valid email that isn’t already invited."
            return
        }
        inviteEmail = ""
        inviteRole = .viewer
    }

    private func isValidEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private func invitedLabel(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "Invited just now" }
        if seconds < 3600 { return "Invited \(seconds / 60)m ago" }
        if seconds < 86_400 { return "Invited \(seconds / 3600)h ago" }
        return "Invited \(seconds / 86_400)d ago"
    }
}
