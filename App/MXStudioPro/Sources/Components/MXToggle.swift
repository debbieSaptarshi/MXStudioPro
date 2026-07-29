import SwiftUI

/// Figma Toggle (`90:52051`) — 40×18 capsule track, capsule knob.
public struct MXToggle: View {
    @Binding public var isOn: Bool

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(MXColor.layer2)

                Capsule(style: .continuous)
                    .fill(isOn ? MXColor.accent : MXColor.grey)
                    .frame(width: 24, height: 14)
                    .padding(2)
            }
            .frame(width: 40, height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityLabel("Toggle")
    }
}

/// Larger toggle-switch (`43:20561`) — 49×22.
public struct MXToggleSwitch: View {
    @Binding public var isOn: Bool

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(MXColor.layer2)

                Capsule(style: .continuous)
                    .fill(isOn ? MXColor.accent : MXColor.grey)
                    .frame(width: 29, height: 16)
                    .padding(3)
            }
            .frame(width: 49, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityLabel("Switch")
    }
}
