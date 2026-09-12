import SwiftUI
import UIKit

enum ScanPhase {
    case detecting, popping, revealed
}

struct PolygonShape: Shape {
    let points: [[Int]]
    let imageSize: CGSize
    let fit: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mapped = points.map { point in
            CGPoint(x: fit.minX + CGFloat(point[0]) / imageSize.width * fit.width,
                    y: fit.minY + CGFloat(point[1]) / imageSize.height * fit.height)
        }
        guard let first = mapped.first else { return path }
        path.move(to: first)
        for point in mapped.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    var centroid: CGPoint {
        let bounds = path(in: .zero).boundingRect
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

// Tier A of the "app eats your photo" sequence: detect, pop, reveal. Under 1.2 s.
// Tap anywhere to skip. Reduced motion plays only the fade.
struct ScanAnimationView: View {
    let meal: MealResponse
    let image: UIImage
    @Binding var phase: ScanPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanY: CGFloat = 0
    @State private var outlined: Set<String> = []
    @State private var popped: Set<String> = []
    @State private var backgroundGone = false

    private var imageSize: CGSize { CGSize(width: meal.imageW, height: meal.imageH) }

    var body: some View {
        GeometryReader { geo in
            let fit = fitRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color(white: 0.06)
                Image(uiImage: image).resizable().frame(width: fit.width, height: fit.height).offset(x: fit.minX, y: fit.minY)
                    .saturation(popped.isEmpty ? 1 : 0.7).brightness(popped.isEmpty ? 0 : -0.08)
                    .opacity(backgroundGone ? 0 : 1)
                ForEach(meal.items) { item in
                    let shape = PolygonShape(points: item.polygon, imageSize: imageSize, fit: fit)
                    Image(uiImage: image).resizable().frame(width: fit.width, height: fit.height).offset(x: fit.minX, y: fit.minY)
                        .mask(shape)
                        .scaleEffect(popped.contains(item.id) ? 1.06 : 1, anchor: UnitPoint(x: shape.centroid.x / geo.size.width, y: shape.centroid.y / geo.size.height))
                        .shadow(color: .black.opacity(popped.contains(item.id) ? 0.5 : 0), radius: 12, y: 6)
                    shape.trim(from: 0, to: outlined.contains(item.id) ? 1 : 0)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                    if phase == .revealed {
                        Text("\(foodClassEmoji[item.label] ?? "🍽️") \(item.label)")
                            .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.75), in: Capsule())
                            .position(shape.centroid)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                if phase == .detecting && !reduceMotion {
                    Rectangle().fill(.orange).frame(width: fit.width, height: 2)
                        .shadow(color: .orange, radius: 8)
                        .offset(x: fit.minX, y: fit.minY + scanY * fit.height)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { finish() }
            .task { await run() }
        }
    }

    private func fitRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
                      width: fitted.width, height: fitted.height)
    }

    private func run() async {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.6)) {
                outlined = Set(meal.items.map(\.id))
                backgroundGone = true
            }
            try? await Task.sleep(for: .milliseconds(600))
            finish()
            return
        }
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.prepare()
        withAnimation(.linear(duration: 0.5)) { scanY = 1 }
        let ordered = meal.items.sorted { ($0.polygon.map { $0[1] }.min() ?? 0) < ($1.polygon.map { $0[1] }.min() ?? 0) }
        var elapsed = 0.0
        for item in ordered {
            let top = Double(item.polygon.map { $0[1] }.min() ?? 0) / Double(meal.imageH) * 0.5
            try? await Task.sleep(for: .milliseconds(Int(max(0, top - elapsed) * 1000)))
            elapsed = max(elapsed, top)
            guard phase != .revealed else { return }
            withAnimation(.easeOut(duration: 0.25)) { _ = outlined.insert(item.id) }
            haptic.impactOccurred()
        }
        try? await Task.sleep(for: .milliseconds(Int(max(0, 0.5 - elapsed) * 1000)))
        guard phase != .revealed else { return }
        phase = .popping
        for item in ordered {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { _ = popped.insert(item.id) }
            try? await Task.sleep(for: .milliseconds(60))
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard phase != .revealed else { return }
        withAnimation(.easeIn(duration: 0.3)) { backgroundGone = true }
        try? await Task.sleep(for: .milliseconds(300))
        finish()
    }

    private func finish() {
        withAnimation(.spring(response: 0.3)) {
            outlined = Set(meal.items.map(\.id))
            popped = Set(meal.items.map(\.id))
            backgroundGone = true
            phase = .revealed
        }
    }
}
