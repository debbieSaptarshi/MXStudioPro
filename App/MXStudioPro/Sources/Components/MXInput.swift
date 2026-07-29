import SwiftUI

/// Figma Input family (`37:21153`).
/// Types: oneIcon / twoIcons / writePost / tags / code
/// States: empty / filled / onNotice (green focus border)
public struct MXInput: View {
    public enum Kind: String, CaseIterable, Identifiable {
        case oneIcon
        case twoIcons
        case writePost
        case tags
        case code
        public var id: String { rawValue }
    }

    public enum FieldState: String, CaseIterable, Identifiable {
        case empty
        case filled
        case onNotice
        public var id: String { rawValue }
    }

    @Binding public var text: String
    @Binding public var tags: [String]
    public var kind: Kind
    public var caption: String
    public var placeholder: String
    public var isSecureVisible: Bool
    public var onToggleSecure: () -> Void
    public var onAdd: () -> Void

    @FocusState private var focused: Bool

    public init(
        text: Binding<String>,
        tags: Binding<[String]> = .constant([]),
        kind: Kind = .oneIcon,
        caption: String = "Captions",
        placeholder: String = "email address",
        isSecureVisible: Bool = true,
        onToggleSecure: @escaping () -> Void = {},
        onAdd: @escaping () -> Void = {}
    ) {
        self._text = text
        self._tags = tags
        self.kind = kind
        self.caption = caption
        self.placeholder = placeholder
        self.isSecureVisible = isSecureVisible
        self.onToggleSecure = onToggleSecure
        self.onAdd = onAdd
    }

    private var showsNotice: Bool { focused || derivedState == .onNotice }

    private var derivedState: FieldState {
        if focused { return .onNotice }
        if kind == .tags { return tags.isEmpty ? .empty : .filled }
        if kind == .code { return text.isEmpty ? .empty : .filled }
        return text.isEmpty ? .empty : .filled
    }

    public var body: some View {
        Group {
            if kind == .code {
                codeField
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if kind == .tags {
                        tagsField
                    } else {
                        textFieldRow
                    }
                    Text(caption)
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.grey)
                }
            }
        }
    }

    private var textFieldRow: some View {
        HStack(spacing: 8) {
            if kind == .oneIcon || kind == .twoIcons {
                Image(systemName: "envelope")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconTint)
                    .frame(width: 20, height: 20)
            }

            TextField(placeholder, text: $text)
                .font(MXFont.body2())
                .foregroundStyle(text.isEmpty ? MXColor.grey : MXColor.white)
                .tint(MXColor.accent)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if kind == .writePost {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconTint)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            if kind == .twoIcons || kind == .writePost {
                Button(action: onToggleSecure) {
                    Image(systemName: isSecureVisible ? "eye" : "eye.slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconTint)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(fieldBackground)
    }

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                FlowTags(tags: tags) { tag in
                    tags.removeAll { $0 == tag }
                }
            }
            TextField("Add genres...", text: $text)
                .font(MXFont.body2())
                .foregroundStyle(MXColor.grey)
                .tint(MXColor.accent)
                .focused($focused)
                .onSubmit {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    tags.append(value)
                    text = ""
                }
        }
        .padding(14)
        .frame(minHeight: 84, alignment: .topLeading)
        .background(fieldBackground)
    }

    private var codeField: some View {
        TextField("-", text: $text)
            .font(MXFont.body2())
            .foregroundStyle(text.isEmpty ? MXColor.grey : MXColor.white)
            .multilineTextAlignment(.center)
            .focused($focused)
            .keyboardType(.numberPad)
            .frame(width: 48, height: 48)
            .background(fieldBackground)
            .onChange(of: text) { _, newValue in
                if newValue.count > 1 {
                    text = String(newValue.prefix(1))
                }
            }
    }

    private var iconTint: Color {
        derivedState == .empty && !focused ? MXColor.grey : MXColor.accent
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(MXColor.black)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(showsNotice ? MXColor.accent : Color.clear, lineWidth: 1)
            )
    }
}

/// Simple tag chips row for Input Tags.
private struct FlowTags: View {
    var tags: [String]
    var onRemove: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.accent)
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(MXColor.accent)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(MXColor.accent.opacity(0.08))
                )
            }
            Spacer(minLength: 0)
        }
    }
}
