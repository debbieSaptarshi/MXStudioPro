import SwiftUI

/// Local notifications list (Week 22).
public struct NotificationsView: View {
    public var onOpenProject: (UUID) -> Void
    public var onDismiss: () -> Void

    @State private var store = MXNotificationStore.shared

    public init(
        onOpenProject: @escaping (UUID) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.onOpenProject = onOpenProject
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    notificationList
                }
            }
            .background(MXColor.surface.ignoresSafeArea())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: onDismiss)
                        .foregroundStyle(MXColor.grey)
                }
                if !store.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") {
                            store.markAllRead()
                        }
                        .font(MXFont.smallButton())
                        .foregroundStyle(MXColor.accent)
                    }
                }
            }
            .onAppear {
                store.load()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36))
                .foregroundStyle(MXColor.grey)
            Text("No notifications yet")
                .font(MXFont.body2())
                .foregroundStyle(MXColor.white)
            Text("Collab invites and remix alerts will show up here when someone interacts with your mixes.")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notificationList: some View {
        List {
            ForEach(store.items) { item in
                Button {
                    store.markRead(id: item.id)
                    if let projectID = item.relatedProjectID {
                        onDismiss()
                        onOpenProject(projectID)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: item.kind))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(MXColor.accent)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(MXColor.accent.opacity(0.12))
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.message)
                                .font(MXFont.body3())
                                .foregroundStyle(MXColor.white)
                                .multilineTextAlignment(.leading)
                            Text(relativeTime(item.createdAt))
                                .font(MXFont.caption())
                                .foregroundStyle(MXColor.grey)
                        }

                        if !item.isRead {
                            Circle()
                                .fill(MXColor.accent)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(MXColor.surfaceRaised)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func icon(for kind: MXNotificationStore.Item.Kind) -> String {
        switch kind {
        case .collabInvite: return "person.2.fill"
        case .remix: return "arrow.triangle.2.circlepath"
        case .general: return "bell.fill"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        guard date.timeIntervalSince1970 > 0 else { return "recently" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
