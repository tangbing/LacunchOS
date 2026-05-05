import AppKit
import Observation

@MainActor
@Observable
final class HotCornerService {
    var status: HotCornerStatus = .disabled

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var settings = LauncherSettings()
    @ObservationIgnored private var action: (@MainActor () -> Void)?
    @ObservationIgnored private var isPointerInsideCorner = false
    @ObservationIgnored private var lastTriggerDate = Date.distantPast

    deinit {
        timer?.invalidate()
    }

    func configure(settings: LauncherSettings, action: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.action = action
        isPointerInsideCorner = false

        guard settings.isHotCornerEnabled else {
            stopMonitoring()
            return
        }

        startMonitoring()
    }

    private func startMonitoring() {
        status = .monitoring

        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            guard let service = self else {
                return
            }

            Task { @MainActor [service] in
                service.pollPointer()
            }
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        status = .disabled
    }

    private func pollPointer() {
        guard
            settings.isHotCornerEnabled,
            let screen = DisplayService.pointerScreen
        else {
            isPointerInsideCorner = false
            return
        }

        let isInside = isMouseLocation(NSEvent.mouseLocation, inside: settings.hotCorner, on: screen)

        guard isInside else {
            isPointerInsideCorner = false
            return
        }

        guard !isPointerInsideCorner, Date().timeIntervalSince(lastTriggerDate) > 0.8 else {
            return
        }

        isPointerInsideCorner = true
        lastTriggerDate = Date()
        action?()
    }

    private func isMouseLocation(_ point: NSPoint, inside corner: HotCorner, on screen: NSScreen) -> Bool {
        let threshold: CGFloat = 8
        let frame = screen.frame

        switch corner {
        case .topLeft:
            return point.x <= frame.minX + threshold && point.y >= frame.maxY - threshold
        case .topRight:
            return point.x >= frame.maxX - threshold && point.y >= frame.maxY - threshold
        case .bottomLeft:
            return point.x <= frame.minX + threshold && point.y <= frame.minY + threshold
        case .bottomRight:
            return point.x >= frame.maxX - threshold && point.y <= frame.minY + threshold
        }
    }
}
