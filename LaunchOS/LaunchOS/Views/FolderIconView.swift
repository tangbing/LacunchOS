import SwiftUI

struct FolderIconView: View {
    let apps: [AppRecord]
    var refreshToken: UUID?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.10))
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(42), spacing: 8), count: 2),
                spacing: 8
            ) {
                ForEach(apps.prefix(4)) { app in
                    AppIconView(app: app, size: 42, refreshToken: refreshToken)
                }
            }
            .frame(width: 92, height: 92)
        }
        .frame(width: 118, height: 118)
        .launchOSGlassSurface(cornerRadius: 28, strokeOpacity: 0.22)
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .accessibilityHidden(true)
    }
}
