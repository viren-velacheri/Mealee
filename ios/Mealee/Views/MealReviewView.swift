import SwiftUI

struct MealReviewView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: MealReviewViewModel
    @State private var pickingFor: MealItem?
    @State private var showDetails = false
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
        ZStack {
            AuroraBackground()
            VStack(spacing: 12) {
                HStack {
                    smallButton("Cancel", icon: "xmark") { Task { if await viewModel.discard(using: appState.api) { onCancel() } } }
                    Spacer()
                    smallButton("Retake", icon: "camera.rotate") { Task { if await viewModel.discard(using: appState.api) { onRetake() } } }
                }
                .disabled(viewModel.isBusy)
                ScanAnimationView(meal: viewModel.meal, image: viewModel.image, phase: $viewModel.scanPhase)
                    .aspectRatio(CGFloat(viewModel.meal.imageW) / CGFloat(viewModel.meal.imageH), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                    .shadow(color: Palette.sage.opacity(0.3), radius: 24, y: 12)
                if viewModel.scanPhase == .revealed {
                    MealItemList(meal: viewModel.meal, showDetails: $showDetails, pick: { pickingFor = $0 }).transition(.liquid)
                    Button { Haptics.success(); Task { await viewModel.confirm(using: appState.api) } } label: {
                        Text("Confirm meal").primaryPill()
                    }
                    .buttonStyle(Pressable()).disabled(viewModel.isBusy).transition(.liquid)
                } else {
                    Spacer()
                    StreamingText(text: "Measuring your plate", font: TypeScale.heading, color: Palette.slate)
                    Spacer()
                }
                if let message = viewModel.errorMessage {
                    Text(message).font(TypeScale.caption).foregroundStyle(Palette.slate)
                }
            }
            .padding(Layout.gutter)
        }
        .overlay { if viewModel.isSubmitting { ProgressView().tint(Palette.leaf).scaleEffect(1.5) } }
        .animation(Motion.settle, value: viewModel.scanPhase)
        .interactiveDismissDisabled()
        .sheet(item: $pickingFor) { item in
            LabelPickerSheet(current: item.label) { label in
                pickingFor = nil
                Task { await viewModel.relabel(item, to: label, using: appState.api) }
            }
            .presentationDetents([.medium, .large]).presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $viewModel.showDelta) {
            StatDeltaView(before: fighterBefore, after: viewModel.meal.fighter) {
                appState.apply(meal: viewModel.meal)
                onDone()
            }
            .interactiveDismissDisabled()
        }
    }

    private func smallButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Label(title, systemImage: icon).font(TypeScale.label).foregroundStyle(Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(Pressable())
    }
}

struct MealItemList: View {
    let meal: MealResponse
    @Binding var showDetails: Bool
    let pick: (MealItem) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(meal.items) { item in
                    Button { Haptics.tap(); pick(item) } label: {
                        HStack(spacing: 12) {
                            Text(foodClassEmoji[item.label] ?? "❓").font(.system(size: 34))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.label).font(TypeScale.heading).foregroundStyle(Palette.ink)
                                    if item.isNew { Pill(text: "new", tint: Palette.leaf) }
                                }
                                Text("tap to change").font(TypeScale.caption).foregroundStyle(Palette.slate)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("≈ \(Int(item.grams + 0.5)) g").font(TypeScale.bigNumber).foregroundStyle(Palette.ink).contentTransition(.numericText())
                                Text("\(Int(item.gramsLow + 0.5)) to \(Int(item.gramsHigh + 0.5)) g").font(TypeScale.caption).foregroundStyle(Palette.slate)
                                if showDetails { Text("\(Int(item.confidence * 100))% sure").font(TypeScale.caption).foregroundStyle(Palette.slate) }
                            }
                        }
                        .glassCard(padding: 14)
                    }
                    .buttonStyle(Pressable())
                }
                Button { Haptics.tap(); withAnimation(Motion.bounce) { showDetails.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(showDetails ? "Scale: \(meal.scale.type), \(String(format: "%.2f", meal.scale.pxPerMm)) px per mm" : "Details")
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    }
                    .font(TypeScale.caption).foregroundStyle(Palette.slate)
                }
            }
        }
    }
}

struct LabelPickerSheet: View {
    let current: String
    let choose: (String) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ScrollView(showsIndicators: false) {
            Text("What is it?").font(TypeScale.title).foregroundStyle(Palette.ink).padding(.top, 20)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(foodClassLabels, id: \.self) { label in
                    Button { Haptics.tap(); choose(label) } label: {
                        VStack(spacing: 4) {
                            Text(foodClassEmoji[label] ?? "🍽️").font(.system(size: 30))
                            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(label == current ? Palette.leaf.opacity(0.45) : Palette.mint.opacity(0.3),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(Pressable())
                }
            }
            .padding(Layout.gutter)
        }
    }
}
