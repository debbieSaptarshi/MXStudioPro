import SwiftUI

/// Lightweight email sign-in sheet (Week 9 magic-email stub).
struct EmailSignInView: View {
    var onCancel: () -> Void
    var onContinue: (String) -> Void

    @State private var email = ""
    @FocusState private var focused: Bool

    private var isValid: Bool {
        let t = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("@") && t.contains(".")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Continue with Email")
                    .font(MXFont.displayTitle())
                    .foregroundStyle(MXColor.white)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MXColor.white)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(MXColor.layer2)
                        )
                }
                .buttonStyle(.plain)
            }

            Text("We’ll keep you signed in on this device. No password for now.")
                .font(MXFont.body2())
                .foregroundStyle(MXColor.grey)

            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                TextField("you@email.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.white)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(MXColor.layer2)
                    )
            }

            Button {
                onContinue(email)
            } label: {
                Text("Continue")
                    .font(MXFont.bigButton())
                    .foregroundStyle(isValid ? MXColor.black : MXColor.grey)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isValid ? MXColor.accent : MXColor.layer2)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isValid)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MXColor.surface.ignoresSafeArea())
        .onAppear { focused = true }
    }
}
