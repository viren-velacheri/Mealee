import PhotosUI
import SwiftUI

struct ReviewPayload: Identifiable {
    let id = UUID()
    let meal: MealResponse
    let image: UIImage
}

struct CaptureView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var cameraError: String?
    @State private var uploadError: String?
    @State private var isUploading = false
    @State private var review: ReviewPayload?
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            if cameraError == nil {
                CameraPreview(session: camera.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            VStack {
                Text("Put a card or fork on the plate").font(.headline).padding(8)
                    .background(.black.opacity(0.5), in: Capsule()).padding(.top, 8)
                Spacer()
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .frame(width: 150, height: 95)
                    .overlay(Text("card here").font(.caption2).foregroundStyle(.white.opacity(0.8)))
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
        .fullScreenCover(item: $review) { payload in
            MealReviewView(meal: payload.meal, image: payload.image) { dismiss() }
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
            .disabled(cameraError != nil || isUploading)
            Spacer()
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle").font(.title2).foregroundStyle(.white)
            }
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
            let meal = try await appState.api.uploadMeal(playerId: playerId, jpeg: jpeg)
            review = ReviewPayload(meal: meal, image: uprightImage)
        } catch {
            uploadError = error.localizedDescription
        }
    }
}
