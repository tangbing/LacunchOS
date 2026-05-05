import Carbon
import Observation

@Observable
final class HotkeyService {
    enum RegisteredHotkey: UInt32 {
        case commandShiftL = 1
        case f4 = 2
    }

    var commandShiftLState: HotkeyRegistrationState = .disabled
    var f4State: HotkeyRegistrationState = .disabled

    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private var hotkeyRefs: [RegisteredHotkey: EventHotKeyRef] = [:]
    @ObservationIgnored private var action: (@MainActor (RegisteredHotkey) -> Void)?

    init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func configure(settings: LauncherSettings, action: @escaping @MainActor (RegisteredHotkey) -> Void) {
        self.action = action
        unregisterAll()

        commandShiftLState = settings.isCommandShiftLHotkeyEnabled
            ? register(.commandShiftL, keyCode: 37, modifiers: UInt32(cmdKey | shiftKey))
            : .disabled
        f4State = settings.isF4HotkeyEnabled
            ? register(.f4, keyCode: 118, modifiers: 0)
            : .disabled
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                guard status == noErr else {
                    return status
                }

                let service = Unmanaged<HotkeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                Task { @MainActor in
                    service.handlePressed(id: hotkeyID.id)
                }

                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }

    private func register(
        _ hotkey: RegisteredHotkey,
        keyCode: UInt32,
        modifiers: UInt32
    ) -> HotkeyRegistrationState {
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: hotkey.rawValue)
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            return status == eventHotKeyExistsErr ? .conflict : .failed(status)
        }

        hotkeyRefs[hotkey] = hotkeyRef
        return .registered
    }

    private func unregisterAll() {
        for hotkeyRef in hotkeyRefs.values {
            UnregisterEventHotKey(hotkeyRef)
        }

        hotkeyRefs.removeAll()
        commandShiftLState = .disabled
        f4State = .disabled
    }

    @MainActor
    private func handlePressed(id: UInt32) {
        guard let hotkey = RegisteredHotkey(rawValue: id) else {
            return
        }

        action?(hotkey)
    }

    private static let signature: OSType = 0x4C4F5348
}
