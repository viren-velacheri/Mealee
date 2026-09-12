import SwiftUI

struct MealReviewView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: MealReviewViewModel
    let fighterBefore: FighterStats
    let onRetake: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    init(meal: MealResponse, image: UIImage, fighterBefore: FighterStats,
         onRetake: @escaping () -> Void,
         onCancel: @escaping () -> Void, onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: MealReviewViewModel(meal: meal, image: image))
        self.fighterBefore = fighterBefore
        self.onRetake = onRetake
        self.onCancel = onCancel
        self.onDone = onDone
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", role: .cancel) {
                    Task {
                        if await viewModel.discard(using: appState.api) { onCancel() }
                    }
                }
                Spacer()
                Button {
                    Task {
                        if await viewModel.discard(using: appState.api) { onRetake() }
                    }
                } label: {
                    Label("Retake", systemImage: "camera.rotate")
                }
            }
            .padding(.horizontal).padding(.top, 8)
            .disabled(viewModel.isBusy)
            if let message = viewModel.errorMessage {
                Text(message).foregroundStyle(.red).font(.footnote).padding(.horizontal)
            }
            ScanAnimationView(meal: viewModel.meal, image: viewModel.image, phase: $viewModel.scanPhase)
                .aspectRatio(CGFloat(viewModel.meal.imageW) / CGFloat(viewModel.meal.imageH), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding()
            if viewModel.scanPhase == .revealed {
                itemList.transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer()
                Text("Scanning your plate").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .background(Color(white: 0.04).ignoresSafeArea())
        .overlay { if viewModel.isSubmitting { ProgressView().controlSize(.large) } }
        .animation(.easeOut(duration: 0.3), value: viewModel.scanPhase)
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $viewModel.showDelta) {
            StatDeltaView(before: fighterBefore, after: viewModel.meal.fighter) {
                appState.apply(meal: viewModel.meal)
                onDone()
            }
            .interactiveDismissDisabled()
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.meal.items) { item in
                    HStack {
                        Menu {
                            ForEach(foodClassLabels, id: \.self) { label in
                                Button("\(foodClassEmoji[label] ?? "") \(label)") {
                                    Task { await viewModel.relabel(item, to: label, using: appState.api) }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(foodClassEmoji[item.label] ?? "❓")
                                Text(item.label).font(.headline)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                                if item.isNew { Text("new").font(.caption2.bold()).padding(4).background(.orange, in: Capsule()) }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(item.grams + 0.5)) g").font(.headline.monospacedDigit())
                            Text("\(Int(item.gramsLow + 0.5)) to \(Int(item.gramsHigh + 0.5)) g")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text("\(Int(item.confidence * 100))% sure").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .listRowBackground(Color(white: 0.1))
                }
                Section {
                    Text("Scale: \(viewModel.meal.scale.type), \(String(format: "%.2f", viewModel.meal.scale.pxPerMm)) px per mm")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .overlay { if viewModel.isRelabeling { ProgressView() } }
            Button { Task { await viewModel.confirm(using: appState.api) } } label: {
                Text("Confirm meal").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).padding()
            .disabled(viewModel.isBusy)
        }
    }
}

struct StatDeltaView: View {
    let before: FighterStats
    let after: FighterStats
    let onDone: () -> Void
    @State private var shown: FighterStats
    @State private var visibleReasons = 0

    init(before: FighterStats, after: FighterStats, onDone: @escaping () -> Void) {
        self.before = before
        self.after = after
        self.onDone = onDone
        _shown = State(initialValue: before)
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Your fighter grew").font(.largeTitle.bold()).padding(.top, 40)
            StatBarsView(stats: shown).padding(.horizontal)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(after.reasons.prefix(visibleReasons).enumerated()), id: \.offset) { _, reason in
                    Text(reason).font(.callout).transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            Spacer()
            Button { onDone() } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).padding()
        }
        .background(Color(white: 0.04).ignoresSafeArea())
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { shown = after }
            for _ in after.reasons {
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.easeOut(duration: 0.25)) { visibleReasons += 1 }
            }
        }
    }
}
