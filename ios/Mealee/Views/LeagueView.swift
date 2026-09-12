import CoreImage.CIFilterBuiltins
import SwiftUI

struct LeagueView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if let league = appState.league {
                Section {
                    VStack(spacing: 8) {
                        Text(league.code).font(.system(size: 56, weight: .black, design: .monospaced)).tracking(8)
                        Text(league.name).foregroundStyle(.secondary)
                        if let qr = QRCode.image(for: "mealee://join/\(league.code)") {
                            Image(uiImage: qr).interpolation(.none).resizable().frame(width: 150, height: 150)
                                .background(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text("Friends type the code or scan to join").font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("Standings this week") {
                    ForEach(league.standings) { standing in
                        HStack {
                            Text("\(standing.rank)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                            Text(standing.emoji).font(.title2)
                            Text(standing.name).font(standing.playerId == appState.playerId ? .headline : .body)
                            Spacer()
                            Text("\(standing.wins) W").font(.headline.monospacedDigit())
                            Text("\(standing.damage) dmg").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Tonight at 9pm") {
                    ForEach(league.tonight) { matchup in
                        HStack {
                            Text("\(matchup.a.emoji) \(matchup.a.name)")
                            Spacer()
                            Text("vs").foregroundStyle(.tertiary)
                            Spacer()
                            Text(matchup.b.map { "\($0.emoji) \($0.name)" } ?? "bye")
                        }
                    }
                }
                Section("Foodex this week") {
                    ForEach(league.players) { player in
                        HStack {
                            Text("\(player.emoji) \(player.name)")
                            Spacer()
                            Text("\(player.discovered) of \(foodClassLabels.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                if let fight = appState.lastFight {
                    Section("Latest fight") {
                        Text("\(fight.a.emoji) \(fight.a.name) vs \(fight.b.emoji) \(fight.b.name), won by \(fight.winnerId == fight.a.playerId ? fight.a.name : fight.b.name)")
                    }
                }
            } else {
                ProgressView()
            }
            Section {
                Button("Leave league", role: .destructive) { appState.leave() }
            }
        }
        .navigationTitle("League")
        .refreshable { await appState.refresh() }
        .task { await appState.refresh() }
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
