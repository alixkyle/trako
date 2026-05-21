import SwiftUI

enum TrakoBrand {
    static let teal = Color(red: 24 / 255, green: 188 / 255, blue: 165 / 255)
    static let blue = Color(red: 40 / 255, green: 126 / 255, blue: 224 / 255)
    static let mint = Color(red: 133 / 255, green: 255 / 255, blue: 222 / 255)

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [teal, blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var chartGradient: LinearGradient {
        LinearGradient(
            colors: [mint.opacity(0.9), teal, blue],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

struct TrakoCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 14
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.background.opacity(elevated ? 0.92 : 0.72))
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(elevated ? 0.18 : 0.08), radius: elevated ? 14 : 6, y: elevated ? 6 : 3)
    }
}

extension View {
    func trakoCard(cornerRadius: CGFloat = 14, elevated: Bool = false) -> some View {
        modifier(TrakoCardModifier(cornerRadius: cornerRadius, elevated: elevated))
    }

    func trakoWindowBackground() -> some View {
        background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                TrakoBrand.gradient
                    .opacity(0.07)
                    .blur(radius: 60)
            }
            .ignoresSafeArea()
        }
    }
}

struct TrakoProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TrakoBrand.gradient.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MiniSparkline: View {
    var values: [TimeInterval]

    private var maximum: TimeInterval {
        max(values.max() ?? 1, 60)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        value > 0
                            ? AnyShapeStyle(TrakoBrand.gradient)
                            : AnyShapeStyle(Color.secondary.opacity(0.25))
                    )
                    .frame(width: 8, height: max(4, CGFloat(value / maximum) * 28))
            }
        }
        .frame(height: 32)
        .accessibilityLabel("Last seven days activity")
    }
}
