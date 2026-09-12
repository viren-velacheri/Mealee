import PhotosUI
import SwiftUI

struct ReviewPayload: Identifiable {
    let id = UUID()
    let meal: MealResponse
    let image: UIImage
    let fighterBefore: FighterStats
}

struct CaptureView: View {
    private enum ReviewOutcome { case retake, cancel, done }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var cameraError: String?
    @State private var uploadError: String?
    @State private var isUploading = false
    @State private var review: ReviewPayload?
    @State private var reviewOutcome: ReviewOutcome?
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            if cameraError == nil {
                CameraPreview(session: camera.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            VStack {
                Text("Frame your meal, then tap the shutter").font(TypeScale.label).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                    .padding(.top, 8)
                Spacer()
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.mint.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [10, 7]))
                    .frame(width: 150, height: 95)
                    .overlay(Text("card optional\nfor better portions").font(TypeScale.caption)
                        .multilineTextAlignment(.center).foregroundStyle(Palette.mist.opacity(0.9)))
                    .shadow(color: Palette.ink.opacity(0.4), radius: 6)
                    .padding(.bottom, 40)
                if let message = cameraError ?? uploadError {
                    Text(message).font(TypeScale.caption).foregroundStyle(Palette.ink).padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                controls
            }
            .padding()
            if isUploading {
                Palette.ink.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().tint(Palette.leaf).scaleEffect(1.3)
                    StreamingText(text: "Measuring your plate", font: TypeScale.heading)
                }
                .glassCard()
                .transition(.liquid)
            }
        }
        .task {
            do { try await camera.start() } catch { cameraError = error.localizedDescription }
        }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(loading: { try await item.loadTransferable(type: Data.self) }) }
        }
        .fullScreenCover(item: $review, onDismiss: handleReviewDismiss) { payload in
            MealReviewView(meal: payload.meal, image: payload.image, fighterBefore: payload.fighterBefore,
                           onRetake: { finishReview(.retake) },
                           onCancel: { finishReview(.cancel) },
                           onDone: { finishReview(.done) })
        }
    }

    private var controls: some View {
        HStack {
            Button { Haptics.tap(); dismiss() } label: {
                Image(systemName: "xmark").font(TypeScale.heading).foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(Pressable())
            .accessibilityLabel("Cancel")
            Spacer()
            Button {
                Haptics.thud()
                Task { await upload(loading: { try await camera.capture() }) }
            } label: {
                ZStack {
                    Circle().strokeBorder(Palette.mist, lineWidth: 5).frame(width: 84, height: 84)
                    Circle().fill(LinearGradient(colors: [Palette.mist, Palette.mint], startPoint: .top, endPoint: .bottom))
                        .frame(width: 66, height: 66)
                        .shadow(color: Palette.leaf.opacity(0.7), radius: 14)
                }
            }
            .buttonStyle(Pressable())
            .accessibilityLabel("Take photo")
            .disabled(cameraError != nil || isUploading)
            Spacer()
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle").font(TypeScale.heading).foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Choose photo")
        }
    }

    private func upload(loading: () async throws -> Data?) async {
        guard let playerId = appState.playerId else { return }
        isUploading = true
        uploadError = nil
        defer { isUploading = false }
        do {
            guard let raw = try await loading(), let jpeg = PhotoEncoder.jpeg(from: raw),
                  let uprightImage = UIImage(data: jpeg) else {
                uploadError = "Could not read that photo."
                return
            }
            let fighterBefore = appState.fighter
            let meal = try await appState.api.uploadMeal(playerId: playerId, jpeg: jpeg)
            review = ReviewPayload(meal: meal, image: uprightImage, fighterBefore: fighterBefore)
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func finishReview(_ outcome: ReviewOutcome) {
        reviewOutcome = outcome
        review = nil
    }

    private func handleReviewDismiss() {
        let outcome = reviewOutcome
        reviewOutcome = nil
        if outcome == .retake {
            pickerItem = nil
            Task {
                do { try await camera.start() } catch { cameraError = error.localizedDescription }
            }
        } else if outcome == .cancel || outcome == .done {
            dismiss()
        }
    }
}
