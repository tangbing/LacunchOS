import AppKit
import SwiftUI

struct AppIconView: View {
    let app: AppRecord
    var size: CGFloat = 64
    var refreshToken: UUID?

    var body: some View {
        Image(nsImage: AppIconCache.icon(for: app.path))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: size / 8, y: size / 16)
            .id(refreshToken)
            .accessibilityHidden(true)
    }
}
