import SwiftUI

struct FolderIconView: View {
    let apps: [AppRecord]
    var refreshToken: UUID?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.10))
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    previewSlot(at: 0)
                    previewSlot(at: 1)
                }

                HStack(spacing: 8) {
                    previewSlot(at: 2)
                    previewSlot(at: 3)
                }
            }
            .frame(width: 92, height: 92)
        }
        .frame(width: 118, height: 118)
        .launchOSGlassSurface(cornerRadius: 28, strokeOpacity: 0.22)
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func previewSlot(at index: Int) -> some View {
        if index < apps.count {
            AppIconView(app: apps[index], size: 42, refreshToken: refreshToken)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 42, height: 42)
                .opacity(0.35)
        }
    }
}
