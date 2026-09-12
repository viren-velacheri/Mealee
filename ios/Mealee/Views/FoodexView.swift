import SwiftUI

struct FoodexView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var discoveries: DiscoveriesResponse?
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                if let discoveries {
                    Text("\(discoveries.discovered.count) of \(discoveries.total)")
                        .font(.system(size: 40, weight: .black, design: .rounded)).padding(.top)
                    Text("found this week").foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(foodClassLabels, id: \.self) { label in
                            cell(label: label, discovery: discoveries.discovered.first { $0.label == label })
                        }
                    }
                    .padding()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).padding()
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .navigationTitle("Foodex")
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
        }
    }

    private func cell(label: String, discovery: Discovery?) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(discovery == nil ? Color(white: 0.12) : Color.orange.opacity(0.2))
                if let discovery, let url = appState.api.imageURL(path: discovery.thumbnailUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Text(foodClassEmoji[label] ?? "🍽️").font(.title)
                    }
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(foodClassEmoji[label] ?? "🍽️").font(.title).grayscale(1).opacity(0.3)
                }
            }
            .frame(height: 60)
            Text(label).font(.system(size: 9)).lineLimit(1).foregroundStyle(discovery == nil ? .tertiary : .primary)
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
