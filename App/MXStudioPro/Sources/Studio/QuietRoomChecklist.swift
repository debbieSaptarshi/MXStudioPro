import Foundation

/// First-record quiet-room checklist items (GarageBand / BandLab-style onboarding).
public enum QuietRoomChecklistItem: Int, CaseIterable, Identifiable, Sendable {
    case quietSpace = 0
    case silenceNotifications
    case headphones
    case micLevel
    case steadyPhone

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .quietSpace: return "Find a quiet space"
        case .silenceNotifications: return "Silence notifications"
        case .headphones: return "Use headphones"
        case .micLevel: return "Check mic level"
        case .steadyPhone: return "Keep the phone steady"
        }
    }

    public var detail: String {
        switch self {
        case .quietSpace:
            return "Close windows and pause fans, AC, or TV before you hit Rec."
        case .silenceNotifications:
            return "Turn on Do Not Disturb so alerts don’t land mid-take."
        case .headphones:
            return "Monitor without speaker feedback — best for vocals and guitar."
        case .micLevel:
            return "Speak or play until the meter moves; back off if it turns red."
        case .steadyPhone:
            return "About a hand’s length from the mic — don’t cover the bottom edge."
        }
    }

    public var systemImage: String {
        switch self {
        case .quietSpace: return "house.lodge"
        case .silenceNotifications: return "bell.slash"
        case .headphones: return "headphones"
        case .micLevel: return "waveform"
        case .steadyPhone: return "iphone"
        }
    }
}
