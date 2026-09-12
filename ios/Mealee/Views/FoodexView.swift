import SwiftUI

struct FoodexView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var discoveries: DiscoveriesResponse?
    @State private var errorMessage: String?
    @State private var revealed = false
    @State private var selected: Discovery?

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
                        FoodexLeaderboard(players: appState.league?.players ?? [],
                                          meId: appState.playerId)
                            .padding(.horizontal, Layout.gutter)
                            .padding(.top, 12)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Array(foodClassLabels.enumerated()), id: \.element) { index, label in
                                FoodexTile(label: label, discovery: discoveries.discovered.first { $0.label == label },
                                           api: appState.api)
                                    .onTapGesture {
                                        guard let found = discoveries.discovered.first(where: { $0.label == label }) else { return }
                                        Haptics.tap()
                                        selected = found
                                    }
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
            .sheet(item: $selected) { found in
                DiscoveryDetail(label: found.label, discovery: found, api: appState.api)
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

// Tapping a found food opens the photo it was found in, and when.
struct DiscoveryDetail: View {
    @Environment(\.dismiss) private var dismiss
    let label: String
    let discovery: Discovery
    let api: MealeeAPI

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                VStack(spacing: 18) {
                    if let url = api.imageURL(path: discovery.thumbnailUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView().tint(Palette.leaf)
                        }
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: Palette.sage.opacity(0.3), radius: 20, y: 10)
                    }
                    Text(label).font(TypeScale.title).foregroundStyle(Palette.ink)
                    Notice(kind: .guidance, text: collectedOn)
                    Spacer()
                }
                .padding(Layout.gutter)
                .padding(.top, 20)
            }
            .navigationTitle("Found").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var collectedOn: String {
        guard let raw = discovery.foundAt, let date = Self.parse(raw) else { return "Collected this week." }
        return "Collected on \(date.formatted(date: .abbreviated, time: .shortened))."
    }

    // Meals carry microseconds, backfilled rows do not.
    private static func parse(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
