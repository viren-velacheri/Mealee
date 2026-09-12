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
                Text("Frame your meal, then tap the white button").font(.headline).padding(8)
                    .background(.black.opacity(0.5), in: Capsule()).padding(.top, 8)
                Spacer()
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .frame(width: 150, height: 95)
                    .overlay(Text("card optional\nfor better portions").font(.caption2)
                        .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8)))
                    .padding(.bottom, 40)
                if let message = cameraError ?? uploadError {
                    Text(message).font(.footnote).foregroundStyle(.white).padding(10)
                        .background(.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                }
                controls
            }
            .padding()
            if isUploading {
                Color.black.opacity(0.55).ignoresSafeArea()
                ProgressView("Measuring your plate").tint(.white).foregroundStyle(.white)
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
            Button("Cancel") { dismiss() }.foregroundStyle(.white)
            Spacer()
            Button {
                Task { await upload(loading: { try await camera.capture() }) }
            } label: {
                Circle().fill(.white).frame(width: 74, height: 74)
                    .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 4))
            }
            .accessibilityLabel("Take photo")
            .disabled(cameraError != nil || isUploading)
            Spacer()
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle").font(.title2).foregroundStyle(.white)
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
