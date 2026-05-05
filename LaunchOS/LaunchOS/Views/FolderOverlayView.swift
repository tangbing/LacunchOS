import SwiftUI

struct FolderOverlayView: View {
    let folder: LauncherFolder
    let model: LauncherModel

    private let columns = Array(repeating: GridItem(.fixed(124), spacing: 18), count: 4)

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Button {
                    model.requestRenameFolder(folder.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(folder.name)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)

                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .launcherFolderContextMenu(for: folder, model: model)

                Spacer()

                Button(action: model.closeFolder) {
                    Image(systemName: "xmark")
                        .font(.title3)
                }
                .launchOSGlassButton()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close Folder")
            }

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(model.openedFolderApps) { app in
                    AppGridItemView(
                        app: app,
                        isSelected: false,
                        isDragging: false,
                        canReorder: false,
                        isFolderDropTarget: false,
                        iconRefreshToken: model.iconRefreshToken
                    ) {
                        model.launch(app)
                    }
                    .launcherAppContextMenu(for: app, model: model)
                }
            }
        }
        .padding(24)
        .frame(width: 640)
        .launchOSGlassSurface(cornerRadius: VisualStyle.panelRadius)
        .shadow(color: .black.opacity(0.22), radius: 28, y: 18)
        .accessibilityElement(children: .contain)
    }
}
