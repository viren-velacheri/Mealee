import SwiftUI

struct FoodexView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var discoveries: DiscoveriesResponse?
    @State private var errorMessage: String?
    @State private var revealed = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView(showsIndicators: false) {
                    if let discoveries {
                        VStack(spacing: 4) {
                            Text("\(discoveries.discovered.count) of \(discoveries.total)")
                                .font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(Palette.ink)
                                .contentTransition(.numericText())
                            Text("found this week").font(TypeScale.body).foregroundStyle(Palette.muted)
                        }
                        .padding(.top, 16)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Array(foodClassLabels.enumerated()), id: \.element) { index, label in
                                FoodexTile(label: label, discovery: discoveries.discovered.first { $0.label == label },
                                           api: appState.api)
                                    .rotation3DEffect(.degrees(revealed ? 0 : 90), axis: (x: 0, y: 1, z: 0))
                                    .opacity(revealed ? 1 : 0)
                                    .animation(Motion.bounce.delay(Double(index) * 0.025), value: revealed)
                            }
                        }
                        .padding(Layout.gutter)
                        .onAppear { revealed = true }
                    } else if let errorMessage {
                        Text(errorMessage).font(TypeScale.caption).foregroundStyle(Palette.muted).padding()
                    } else {
                        ProgressView().tint(Palette.leaf).padding(.top, 120)
                    }
                }
            }
            .navigationTitle("Foodex")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { Button("Done") { Haptics.tap(); dismiss() }.font(TypeScale.label).foregroundStyle(Palette.muted) }
            .task { await load() }
        }
    }

    private func load() async {
        guard let playerId = appState.playerId else { return }
        do {
            discoveries = try await appState.api.discoveries(playerId: playerId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FoodexTile: View {
    let label: String
    let discovery: Discovery?
    let api: MealeeAPI

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(discovery == nil ? Palette.mint.opacity(0.25) : Palette.leaf.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                if let discovery, let url = api.imageURL(path: discovery.thumbnailUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Text(foodClassEmoji[label] ?? "🍽️").font(.title)
                    }
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text(foodClassEmoji[label] ?? "🍽️").font(.title).grayscale(1).opacity(0.28)
                }
            }
            .frame(height: 62)
            Text(label).font(Font.system(.caption2, design: .rounded).weight(.semibold)).lineLimit(1)
                .foregroundStyle(discovery == nil ? Palette.slate : Palette.ink)
        }
    }
}
