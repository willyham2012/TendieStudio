import SwiftUI
import UIKit

/// TendieStudio design language: a warm "tendie" amber accent on deep ink,
/// with Liquid Glass on iOS 26+ and a material fallback below.
enum Theme {
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.20)
    static let ember = Color(red: 1.0, green: 0.42, blue: 0.30)
    static let ink = Color(red: 0.045, green: 0.05, blue: 0.09)
    static let inkRaised = Color(red: 0.09, green: 0.10, blue: 0.16)
    static let accentGradient = LinearGradient(colors: [amber, ember], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Soft static colour fields behind content. Intentionally not animated (battery).
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Theme.ink
            RadialGradient(colors: [Theme.ember.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color.indigo.opacity(0.30), .clear], center: .bottomLeading, startRadius: 0, endRadius: 520)
        }.ignoresSafeArea()
    }
}

extension View {
    /// Liquid Glass on iOS 26+, ultra-thin material elsewhere.
    @ViewBuilder
    func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let g: Glass = tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular
            self.glassEffect(interactive ? g.interactive() : g, in: shape)
        } else { self.materialGlass(in: shape, tint: tint) }
        #else
        self.materialGlass(in: shape, tint: tint)
        #endif
    }

    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View { glass(in: Capsule(), tint: tint, interactive: interactive) }
    func glassCard(radius: CGFloat = 22) -> some View { glass(in: RoundedRectangle(cornerRadius: radius, style: .continuous)) }

    fileprivate func materialGlass<S: Shape>(in shape: S, tint: Color?) -> some View {
        self.background(.ultraThinMaterial, in: shape)
            .overlay(shape.fill((tint ?? .clear).opacity(0.18)))
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
    }
}

/// Round glass icon button used across the editor chrome.
struct GlassIconButton: View {
    let systemName: String
    var tint: Color? = nil
    var size: CGFloat = 40
    var active = false
    let action: () -> Void
    var body: some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: systemName).font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(active ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background { if active { Circle().fill(Theme.accentGradient) } }
                .glass(in: Circle(), tint: tint, interactive: true)
        }.buttonStyle(PressScale())
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.black)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(Theme.accentGradient, in: Capsule())
            .shadow(color: Theme.ember.opacity(0.4), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

struct SectionTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.5))
    }
}
