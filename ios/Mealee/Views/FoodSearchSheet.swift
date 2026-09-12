import SwiftUI

struct FoodSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FoodSearchViewModel
    @State private var isSaving = false
    let api: MealeeAPI
    let choose: (FoodSearchResult, Double) async -> Bool

    init(current: MealItem?, api: MealeeAPI,
         choose: @escaping (FoodSearchResult, Double) async -> Bool) {
        _viewModel = State(initialValue: FoodSearchViewModel(
            query: current?.label ?? "", grams: current?.grams ?? 50))
        self.api = api
        self.choose = choose
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ZStack {
                AuroraBackground()
                List {
                    Section("Amount") {
                        HStack {
                            TextField("50", text: $viewModel.gramsText)
                                .keyboardType(.decimalPad).font(TypeScale.heading)
                            Text("grams").foregroundStyle(Palette.slate)
                        }
                    }
                    Section("Matches") {
                        if viewModel.isSearching {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        }
                        ForEach(viewModel.results) { food in
                            Button { select(food) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(food.label).font(TypeScale.heading).foregroundStyle(Palette.ink)
                                    Text("\(Int(food.kcal.rounded())) kcal · \(food.proteinG, specifier: "%.1f") g protein per 100 g")
                                        .font(TypeScale.caption).foregroundStyle(Palette.slate)
                                    Text(food.source).font(TypeScale.caption).foregroundStyle(Palette.sage)
                                }
                            }
                            .disabled(viewModel.grams == nil || isSaving)
                        }
                        if let message = viewModel.errorMessage {
                            Text(message).font(TypeScale.caption).foregroundStyle(Palette.slate)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Find a food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .searchable(text: $viewModel.query, prompt: "Carrots, yogurt, goji berries…")
            .task(id: viewModel.query) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await viewModel.search(using: api)
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private func select(_ food: FoodSearchResult) {
        guard let grams = viewModel.grams else { return }
        isSaving = true
        Task {
            if await choose(food, grams) { dismiss() }
            isSaving = false
        }
    }
}
