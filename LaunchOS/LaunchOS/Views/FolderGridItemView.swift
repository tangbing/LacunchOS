import SwiftUI

struct FolderGridItemView: View {
    let folder: LauncherFolder
    let apps: [AppRecord]
    let isSelected: Bool
    let isDropTarget: Bool
    let canReorder: Bool
    let iconRefreshToken: UUID
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 14) {
                FolderIconView(apps: apps, refreshToken: iconRefreshToken)

                Text(folder.name)
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
                if isDropTarget {
                    RoundedRectangle(cornerRadius: VisualStyle.tileRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.22))
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: VisualStyle.tileRadius, style: .continuous))
                }
            }
            .overlay {
                if canReorder || isDropTarget {
                    RoundedRectangle(cornerRadius: VisualStyle.tileRadius, style: .continuous)
                        .stroke(
                            Color.accentColor.opacity(isDropTarget ? 0.72 : 0),
                            lineWidth: isDropTarget ? 2 : 1
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isDropTarget ? 1.08 : 1)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.78, blendDuration: 0.04), value: isDropTarget)
        .accessibilityLabel(folder.name)
    }
}
