import AppKit
import Carbon

@MainActor
final class LaunchDeckHotKeyMonitor {
    static let shared = LaunchDeckHotKeyMonitor()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    func start(handler: @escaping () -> Void) {
        self.handler = handler
        guard hotKeyRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData,
                  let eventRef else { return noErr }

            let monitor = Unmanaged<LaunchDeckHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr, hotKeyID.id == monitor.hotKeySignature else {
                return noErr
            }

            monitor.handler?()
            return noErr
        }, 1, &eventSpec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandler)

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeySignature)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private var hotKeySignature: UInt32 {
        0x4C44484B // LDHK
    }
}
