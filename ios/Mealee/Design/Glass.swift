import SwiftUI
import UIKit

struct GlassCard: ViewModifier {
    var tint: Color = Palette.mint
    var padding: CGFloat = Layout.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: Layout.corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous).fill(tint.opacity(0.22)))
                    .overlay(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.2)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                    .shadow(color: Palette.sage.opacity(0.22), radius: 22, y: 12)
            }
    }
}

extension View {
    func glassCard(tint: Color = Palette.mint, padding: CGFloat = Layout.cardPadding) -> some View {
        modifier(GlassCard(tint: tint, padding: padding))
    }
}

struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(Motion.snappy, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

struct PrimaryPill: ViewModifier {
    var filled = true

    func body(content: Content) -> some View {
        content
            .font(TypeScale.heading)
            .foregroundStyle(filled ? Palette.ink : Palette.ink.opacity(0.85))
            .padding(.vertical, 16).padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background {
                Capsule().fill(filled ? AnyShapeStyle(LinearGradient(colors: [Palette.leaf, Palette.mint], startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                    .shadow(color: Palette.leaf.opacity(filled ? 0.45 : 0.15), radius: 16, y: 8)
            }
    }
}

extension View {
    func primaryPill(filled: Bool = true) -> some View { modifier(PrimaryPill(filled: filled)) }
}

struct AuroraBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let seconds = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
            Rectangle()
                .fill(Palette.mist)
                .colorEffect(ShaderLibrary.aurora(.float(seconds), .boundingRect))
        }
        .ignoresSafeArea()
    }
}

// Screens and cards arrive and leave as a ripple through glass. Animatable so the
// transition system interpolates progress rather than snapping.
struct LiquidModifier: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.05 * progress)
            .blur(radius: 8 * progress)
            .opacity(1 - progress)
    }
}

extension AnyTransition {
    static var liquid: AnyTransition {
        .modifier(active: LiquidModifier(progress: 1), identity: LiquidModifier(progress: 0))
    }
}

// The generators are held for the life of the app. A generator released right after
// impactOccurred() leaves UIKit with no running engine and the tap is dropped; priming
// after each hit keeps the engine warm for the next one.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    static func tap() { light.impactOccurred(); light.prepare() }
    static func thud() { rigid.impactOccurred(); rigid.prepare() }
    static func success() { notification.notificationOccurred(.success); notification.prepare() }
}
