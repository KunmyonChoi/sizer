import AppKit
import Carbon.HIToolbox

private let sizerHotKeySignature: OSType = 0x53495A52   // 'SIZR'

/// Carbon `RegisterEventHotKey` 기반 전역 단축키.
/// 접근성 권한이 필요 없고(키 이벤트 가로채기 방식과 달리) 키를 소비하며, 메뉴바(accessory) 앱에서도 동작한다.
///
/// 여러 개를 등록할 수 있도록 **공유 이벤트 핸들러 + id→콜백 레지스트리**로 구성한다.
/// (핸들러를 인스턴스마다 설치하면 Carbon 핸들러 스택에서 맨 위 핸들러가 `noErr`로 모든 핫키를
///  삼켜 다른 핫키가 동작하지 않는다. 핸들러는 하나만 두고 id로 분기한다.)
@MainActor
final class GlobalHotKey {
    // 공유 상태(전 인스턴스 공용)
    private static var sharedHandler: EventHandlerRef?
    private static var callbacks: [UInt32: () -> Void] = [:]
    private static var counter: UInt32 = 0

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    var onFire: (() -> Void)?

    init() {
        GlobalHotKey.counter += 1
        self.id = GlobalHotKey.counter
    }

    /// keyCode(NSEvent.keyCode 가상키) + cocoaModifiers(NSEvent.ModifierFlags rawValue)로 (재)등록.
    /// 수정키가 하나도 없으면 등록하지 않는다(단독 키 방지).
    func update(keyCode: Int, cocoaModifiers: Int) {
        unregister()
        let flags = NSEvent.ModifierFlags(rawValue: UInt(cocoaModifiers))
        let carbonMods = GlobalHotKey.carbonFlags(from: flags)
        guard keyCode != 0, carbonMods != 0 else { return }

        GlobalHotKey.installSharedHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: sizerHotKeySignature, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), carbonMods, hkID,
                                         GetEventDispatcherTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
            GlobalHotKey.callbacks[id] = { [weak self] in self?.onFire?() }
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        GlobalHotKey.callbacks[id] = nil
    }

    private static func installSharedHandlerIfNeeded() {
        guard sharedHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let firedID = hkID.id
            DispatchQueue.main.async { GlobalHotKey.callbacks[firedID]?() }
            return noErr
        }, 1, &spec, nil, &sharedHandler)
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

    /// 특수 키를 보기 좋은 기호로 변환(방향키·리턴 등). 그 외는 문자를 대문자로.
    static func keyLabel(keyCode: Int, characters: String) -> String {
        switch keyCode {
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 36:  return "↩"
        case 76:  return "⌤"      // 숫자패드 Enter
        case 48:  return "⇥"
        case 49:  return "Space"
        case 51:  return "⌫"
        case 117: return "⌦"
        case 53:  return "⎋"
        default:  return characters.uppercased()
        }
    }

    /// 표시 문자열(예 "⌥⌘S"). 레코더가 캡처한 수정키 + 이미 정리된 키 라벨로 구성.
    static func displayString(flags: NSEvent.ModifierFlags, characters: String) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + characters
    }
}
