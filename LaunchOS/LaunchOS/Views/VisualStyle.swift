import SwiftUI

enum VisualStyle {
    static let controlRadius: CGFloat = 14
    static let searchRadius: CGFloat = 24
    static let tileRadius: CGFloat = 28
    static let panelRadius: CGFloat = 24
}

private struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isInteractive: Bool
    let strokeOpacity: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            if isInteractive {
                content
                    .background(.regularMaterial, in: shape)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                    .overlay {
                        shape.stroke(.white.opacity(strokeOpacity), lineWidth: 1)
                    }
            } else {
                content
                    .background(.regularMaterial, in: shape)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .overlay {
                        shape.stroke(.white.opacity(strokeOpacity), lineWidth: 1)
                    }
            }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(strokeOpacity), lineWidth: 1)
                }
        }
    }
}

private struct GlassButtonStyleModifier: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if isProminent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(.borderless)
        }
    }
}

extension View {
    func launchOSGlassSurface(
        cornerRadius: CGFloat = VisualStyle.controlRadius,
        isInteractive: Bool = false,
        strokeOpacity: Double = 0.18
    ) -> some View {
        modifier(
            GlassSurfaceModifier(
                cornerRadius: cornerRadius,
                isInteractive: isInteractive,
                strokeOpacity: strokeOpacity
            )
        )
    }

    func launchOSGlassButton(prominent: Bool = false) -> some View {
        modifier(GlassButtonStyleModifier(isProminent: prominent))
    }
}
