import SwiftUI

struct AppGridItemView: View {
    let app: AppRecord
    let isSelected: Bool
    let isDragging: Bool
    let canReorder: Bool
    let isFolderDropTarget: Bool
    let iconRefreshToken: UUID
    let launch: () -> Void

    var body: some View {
        Button(action: launch) {
            VStack(spacing: 14) {
                AppIconView(app: app, size: 118, refreshToken: iconRefreshToken)

                Text(app.alias ?? app.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.38), radius: 4, y: 1)
                    .frame(width: 138, height: 40, alignment: .top)
            }
            .frame(width: 156, height: 172)
            .contentShape(RoundedRectangle(cornerRadius: VisualStyle.tileRadius, style: .continuous))
            .background {
                if isFolderDropTarget {
                    RoundedRectangle(cornerRadius: VisualStyle.tileRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: VisualStyle.tileRadius, style: .continuous))
                }
            }
            .overlay {
                if canReorder || isFolderDropTarget {
                    RoundedRectangle(cornerRadius: VisualStyle.tileRadius, style: .continuous)
                        .stroke(
                            Color.accentColor.opacity(isFolderDropTarget ? 0.72 : 0),
                            lineWidth: isFolderDropTarget ? 2 : 1
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(isDragging ? 0.08 : 1)
        .scaleEffect(isFolderDropTarget ? 1.05 : (isDragging ? 0.88 : 1))
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.78, blendDuration: 0.04), value: isDragging)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.82, blendDuration: 0.04), value: isFolderDropTarget)
        .accessibilityLabel(app.alias ?? app.displayName)
    }
}
