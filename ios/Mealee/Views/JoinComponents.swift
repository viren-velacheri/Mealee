import SwiftUI

// The rules behind every "you still need to..." message. Kept free of SwiftUI so the
// wording can be pinned by a test.
struct JoinForm {
    var name = ""
    var code = ""
    var leagueName = ""

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedCode: String { code.trimmingCharacters(in: .whitespaces) }
    var trimmedLeagueName: String { leagueName.trimmingCharacters(in: .whitespaces) }

    private static let noName = "Enter your name first, so rivals know who they are fighting."

    var missingForJoin: String? {
        if trimmedName.isEmpty { return Self.noName }
        if trimmedCode.isEmpty { return "Enter the league's 4-letter code to join it." }
        if trimmedCode.count != 4 { return "A league code is exactly 4 letters, like DEMO." }
        return nil
    }

    var missingForCreate: String? {
        if trimmedName.isEmpty { return Self.noName }
        if trimmedLeagueName.isEmpty { return "Give your league a name, like Hall 3 Lunch." }
        return nil
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
