import AppKit
import Carbon.HIToolbox

private let sizerHotKeySignature: OSType = 0x53495A52   // 'SIZR'
private let sizerHotKeyID: UInt32 = 1

/// Carbon `RegisterEventHotKey` 기반 전역 단축키.
/// 접근성 권한이 필요 없고(키 이벤트 가로채기 방식과 달리) 키를 소비하며, 메뉴바(accessory) 앱에서도 동작한다.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onFire: (() -> Void)?

    /// keyCode(NSEvent.keyCode 가상키) + cocoaModifiers(NSEvent.ModifierFlags rawValue)로 (재)등록.
    /// 수정키가 하나도 없으면 등록하지 않는다(단독 키 방지).
    func update(keyCode: Int, cocoaModifiers: Int) {
        unregister()
        let flags = NSEvent.ModifierFlags(rawValue: UInt(cocoaModifiers))
        let carbonMods = GlobalHotKey.carbonFlags(from: flags)
        guard keyCode != 0, carbonMods != 0 else { return }

        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: sizerHotKeySignature, id: sizerHotKeyID)
        let status = RegisterEventHotKey(UInt32(keyCode), carbonMods, id,
                                         GetEventDispatcherTarget(), 0, &ref)
        if status == noErr { hotKeyRef = ref }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let this = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard hkID.id == sizerHotKeyID else { return noErr }
            let center = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { center.onFire?() }
            return noErr
        }, 1, &spec, this, &eventHandler)
    }

    /// Cocoa 수정키 → Carbon 플래그.
    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        if flags.contains(.option)  { c |= UInt32(optionKey) }
        if flags.contains(.control) { c |= UInt32(controlKey) }
        if flags.contains(.shift)   { c |= UInt32(shiftKey) }
        return c
    }

    /// 표시 문자열(예 "⌥⌘S"). 레코더가 캡처한 문자와 수정키로 구성.
    static func displayString(flags: NSEvent.ModifierFlags, characters: String) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + characters.uppercased()
    }
}
