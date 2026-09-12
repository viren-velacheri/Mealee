import CoreImage.CIFilterBuiltins
import SwiftUI

struct LeagueView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                if let league = appState.league {
                    VStack(spacing: 16) {
                        VStack(spacing: 10) {
                            Text(league.code).font(.system(size: 64, weight: .black, design: .rounded)).tracking(10)
                                .foregroundStyle(Palette.ink).padding(.leading, 10)
                            Text(league.name).font(TypeScale.body).foregroundStyle(Palette.slate)
                            if let qr = QRCode.image(for: "mealee://join/\(league.code)") {
                                Image(uiImage: qr).interpolation(.none).resizable().frame(width: 140, height: 140)
                                    .padding(8).background(Palette.mist, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            Text("Type the code or scan to join").font(TypeScale.caption).foregroundStyle(Palette.slate)
                        }
                        .frame(maxWidth: .infinity)
                        .glassCard(tint: Palette.leaf)
                        section("Standings this week") {
                            ForEach(league.standings) { standing in
                                StandingRow(standing: standing, mine: standing.playerId == appState.playerId)
                            }
                        }
                        section("Tonight at 9pm") {
                            ForEach(league.tonight) { matchup in
                                HStack {
                                    Text("\(matchup.a.emoji) \(matchup.a.name)").font(TypeScale.body).foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text("vs").font(TypeScale.label).foregroundStyle(Palette.slate)
                                    Spacer()
                                    Text(matchup.b.map { "\($0.emoji) \($0.name)" } ?? "bye").font(TypeScale.body).foregroundStyle(Palette.ink)
                                }
                            }
                        }
                        section("Foodex this week") {
                            ForEach(league.players) { player in
                                HStack {
                                    Text("\(player.emoji) \(player.name)").font(TypeScale.body).foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text("\(player.discovered) of \(foodClassLabels.count)").font(TypeScale.number).foregroundStyle(Palette.slate)
                                }
                            }
                        }
                        Button { Haptics.tap(); appState.leave() } label: {
                            Text("Leave league").font(TypeScale.caption).foregroundStyle(Palette.slate)
                        }
                        .padding(.top, 8)
                    }
                    .padding(Layout.gutter)
                } else {
                    ProgressView().tint(Palette.leaf).padding(.top, 120)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await appState.refresh() }
        .task { await appState.refresh() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(TypeScale.heading).foregroundStyle(Palette.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct StandingRow: View {
    let standing: Standing
    let mine: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(standing.rank)").font(TypeScale.number).foregroundStyle(Palette.ink)
                .frame(width: 28, height: 28)
                .background(standing.rank == 1 ? Palette.leaf : Palette.mint.opacity(0.6), in: Circle())
            Text(standing.emoji).font(.system(size: 26))
            Text(standing.name).font(mine ? TypeScale.heading : TypeScale.body).foregroundStyle(Palette.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(standing.wins) W").font(TypeScale.number).foregroundStyle(Palette.ink).contentTransition(.numericText())
                Text("\(standing.damage) dmg").font(TypeScale.caption).foregroundStyle(Palette.slate)
            }
        }
        .padding(.vertical, 4)
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
