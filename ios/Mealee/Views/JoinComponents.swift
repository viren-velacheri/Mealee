import SwiftUI

// The rules behind every "you still need to..." message. Kept free of SwiftUI so the
// wording can be pinned by a test.
struct JoinForm {
    var name = ""

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var missingToEnter: String? {
        trimmedName.isEmpty ? "Enter your name first, so rivals know who they are fighting." : nil
    }
}

struct BusyOverlay: View {
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Palette.leaf).scaleEffect(1.4)
            Text(label).font(TypeScale.label).foregroundStyle(Palette.ink)
        }
        .padding(24)
        .glassCard()
    }
}

struct AvatarPicker: View {
    @Binding var emoji: String
    let choices: [String]
    @Binding var showingCustomEmoji: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    Text(choice).font(.system(size: 34)).padding(8)
                        .background(choice == emoji ? Palette.leaf.opacity(0.5) : .clear, in: Circle())
                        .scaleEffect(choice == emoji ? 1.15 : 1)
                        .onTapGesture { Haptics.tap(); withAnimation(Motion.bounce) { emoji = choice } }
                }
                Button { showingCustomEmoji = true } label: {
                    VStack(spacing: 2) {
                        Text(choices.contains(emoji) ? "+" : emoji).font(.system(size: 30, weight: .medium))
                        Text("custom").font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Palette.ink).frame(width: 50, height: 50)
                    .background(choices.contains(emoji) ? .clear : Palette.leaf.opacity(0.5), in: Circle())
                }
                .accessibilityLabel("Choose a custom emoji")
            }
        }
    }
}

enum AvatarChoice {
    static func emoji(from input: String) -> String? {
        guard let character = input.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        let scalars = character.unicodeScalars
        let presentsAsEmoji = scalars.contains { $0.properties.isEmojiPresentation }
            || scalars.contains { $0.value == 0xFE0F }
            || (scalars.count > 1 && scalars.contains { $0.properties.isEmoji })
        guard presentsAsEmoji else { return nil }
        return String(character)
    }
}

struct CustomEmojiSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    let choose: (String) -> Void

    init(current: String, choose: @escaping (String) -> Void) {
        _input = State(initialValue: current)
        self.choose = choose
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(AvatarChoice.emoji(from: input) ?? "🙂").font(.system(size: 88))
                    .frame(width: 132, height: 132).background(Palette.mint.opacity(0.4), in: Circle())
                TextField("Your emoji", text: $input).font(TypeScale.title).multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().padding().glassCard()
                Notice(kind: .guidance,
                       text: "Enter or paste any one emoji. Use the globe key to open the emoji keyboard.")
                Button {
                    guard let emoji = AvatarChoice.emoji(from: input) else { return }
                    Haptics.success(); choose(emoji); dismiss()
                } label: {
                    Text("Use this face").primaryPill()
                }
                .disabled(AvatarChoice.emoji(from: input) == nil)
                Spacer()
            }
            .padding(Layout.gutter).background(AuroraBackground())
            .navigationTitle("Custom face").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
