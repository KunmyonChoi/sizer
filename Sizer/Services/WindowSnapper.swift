import AppKit
import ApplicationServices

/// 창 스냅 단축키가 지시하는 동작.
///
/// 2분할과 3분할을 서로 다른 키에 두어, 한 키를 반복해도 예상 못 한 비율로 넘어가지 않게 한다.
enum SnapPosition: String, CaseIterable {
    case leftHalf     // 좌 1/2 — 이미 좌 1/2면 왼쪽 화면의 우 1/2
    case rightHalf    // 우 1/2 — 이미 우 1/2면 오른쪽 화면의 좌 1/2
    case leftThird    // 좌 1/3 ↔ 좌 2/3 (같은 화면 안에서만)
    case rightThird   // 우 1/3 ↔ 우 2/3 (같은 화면 안에서만)
    case maximize
    case prevScreen   // 비율을 유지한 채 바로 이전 화면
    case nextScreen   // 비율을 유지한 채 바로 다음 화면
}

/// 창이 놓일 수 있는 자리. 화면 폭을 `0 · 1/3 · 1/2 · 2/3 · 1` 다섯 눈금으로 나눈 여섯 배치다.
/// 2분할 단축키는 1/2 두 자리를, 3분할 단축키는 1/3·2/3 네 자리를 쓴다.
enum SnapSlot: Int, CaseIterable {
    case leftThird = 0
    case leftHalf
    case leftTwoThirds
    case rightTwoThirds
    case rightHalf
    case rightThird
}

/// 화면 하나의 기하(NSScreen에서 분리해 순수 로직을 테스트 가능하게 함).
struct SnapScreen: Equatable {
    let frame: NSRect         // 전역 Cocoa 좌표(모니터 배치 판정용)
    let visibleFrame: NSRect  // 메뉴바·Dock 제외 영역(실제 배치 대상)
}

/// 손쉬운 사용(Accessibility) API로 **현재 최상위 앱의 포커스 창**을 정렬한다.
///
/// 키마다 하는 일이 하나씩이다:
/// - `leftHalf`/`rightHalf` — 좌·우 절반. 이미 그 절반이면 **그 방향의 화면**으로 넘어간다(sideScreen).
/// - `leftThird`/`rightThird` — 1/3 ↔ 2/3 토글. 화면을 넘지 않는다.
/// - `prevScreen`/`nextScreen` — 비율을 유지한 채 **모든 화면을 왼쪽 끝 순으로** 오간다(orderedScreens).
///
/// 화면을 고르는 규칙이 둘로 갈리는 이유: 절반 키는 미는 방향과 도착지가 맞아야 하므로 가로로
/// 겹치지 않는 진짜 좌/우 화면만 대상으로 삼고, 그러면 다른 화면에 가로로 감싸인 화면(노트북 위에
/// 올린 모니터 배치)에 창을 보낼 길이 없어지므로 즉시 이동 키가 모든 화면을 순회한다.
///
/// 다른 앱의 창을 옮기려면 손쉬운 사용 권한이 필수다(우회 불가). 좌표 변환에 주의:
/// - Cocoa(NSScreen): 좌하단 원점, Y가 위로 증가.
/// - AX/Quartz: 좌상단 원점, Y가 아래로 증가. 원점은 주 화면(메뉴바 있는 화면)의 좌상단.
enum WindowSnapper {

    // MARK: 권한

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 권한 요청 프롬프트를 띄운다(최초 1회). 이미 거부되었으면 시스템이 재프롬프트를 억제할 수 있다.
    @discardableResult
    static func requestTrust() -> Bool {
        // kAXTrustedCheckOptionPrompt 의 실제 문자열 값. 상수의 Unmanaged 브리징 차이를 피하려 리터럴 사용.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 창을 연다.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 스냅 실행

    /// 최상위 앱의 포커스 창을 지정 동작대로 옮긴다. 권한이 없으면 프롬프트만 띄우고 false 반환.
    @discardableResult
    static func snap(_ position: SnapPosition) -> Bool {
        guard isTrusted else {
            requestTrust()
            AppLogger.warn("창 스냅: 손쉬운 사용 권한이 없어 동작하지 않았습니다. 설정 → 창 스냅에서 권한을 허용하세요.")
            return false
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = app.processIdentifier
        // 우리 앱(설정 창 등)은 대상에서 제외.
        if pid == ProcessInfo.processInfo.processIdentifier { return false }

        let appEl = AXUIElementCreateApplication(pid)
        guard let window = focusedWindow(of: appEl) else { return false }
        let winFrame = effectiveFrame(of: window)
        guard let screen = screen(for: winFrame) else { return false }

        let screens = NSScreen.screens.map { SnapScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let current = SnapScreen(frame: screen.frame, visibleFrame: screen.visibleFrame)
        let target = resolveTarget(position, windowFrame: winFrame, currentScreen: current, screens: screens)
        setFrame(target, for: window)
        return true
    }

    // MARK: 순수 계산(테스트 대상)

    /// 목표 프레임 결정.
    static func resolveTarget(_ position: SnapPosition,
                              windowFrame: NSRect?,
                              currentScreen: SnapScreen,
                              screens: [SnapScreen]) -> NSRect {
        switch position {
        case .maximize:
            return currentScreen.visibleFrame
        case .leftHalf:
            return half(toLeft: true, windowFrame: windowFrame, currentScreen: currentScreen, screens: screens)
        case .rightHalf:
            return half(toLeft: false, windowFrame: windowFrame, currentScreen: currentScreen, screens: screens)
        case .leftThird:
            return third(narrow: .leftThird, wide: .leftTwoThirds, windowFrame: windowFrame, currentScreen: currentScreen)
        case .rightThird:
            return third(narrow: .rightThird, wide: .rightTwoThirds, windowFrame: windowFrame, currentScreen: currentScreen)
        case .prevScreen:
            return jump(-1, windowFrame: windowFrame, currentScreen: currentScreen, screens: screens)
        case .nextScreen:
            return jump(+1, windowFrame: windowFrame, currentScreen: currentScreen, screens: screens)
        }
    }

    /// 좌·우 절반. 창이 이미 그 절반에 있으면 **그 방향의 화면**으로 넘어가 반대쪽 절반에 붙인다
    /// (한 번만 더 누르면 넘어간다). 그 방향에 화면이 없으면 그대로 둔다 — 반대편으로 순환시키면
    /// 창이 화면 반대쪽으로 튀어 눈으로 쫓기 어렵다.
    private static func half(toLeft: Bool,
                             windowFrame: NSRect?,
                             currentScreen: SnapScreen,
                             screens: [SnapScreen]) -> NSRect {
        let vf = currentScreen.visibleFrame
        let here = frame(for: toLeft ? .leftHalf : .rightHalf, in: vf)
        guard let w = windowFrame, occupies(w, here),
              let side = sideScreen(of: currentScreen, in: screens, toLeft: toLeft)
        else { return here }
        return frame(for: toLeft ? .rightHalf : .leftHalf, in: side.visibleFrame)
    }

    /// 1/3 ↔ 2/3 토글. 화면은 넘지 않는다 — 넘기는 일은 절반 키와 즉시 이동 키가 맡는다.
    private static func third(narrow: SnapSlot,
                              wide: SnapSlot,
                              windowFrame: NSRect?,
                              currentScreen: SnapScreen) -> NSRect {
        let vf = currentScreen.visibleFrame
        if let w = windowFrame, occupies(w, frame(for: narrow, in: vf)) {
            return frame(for: wide, in: vf)
        }
        return frame(for: narrow, in: vf)
    }

    /// 띠를 거치지 않고 곧장 이웃 화면으로. 칸에 놓인 창은 그 칸을 그대로 가져가고,
    /// 칸에 없는 창은 상대 위치·크기를 비례 변환한다. 이웃이 없으면 움직이지 않는다.
    private static func jump(_ delta: Int,
                             windowFrame: NSRect?,
                             currentScreen: SnapScreen,
                             screens: [SnapScreen]) -> NSRect {
        guard let neighbor = neighborScreen(of: currentScreen, in: screens, delta: delta) else {
            return windowFrame ?? currentScreen.visibleFrame
        }
        let from = currentScreen.visibleFrame
        let to = neighbor.visibleFrame
        guard let w = windowFrame else { return to }
        if let slot = currentSlot(of: w, in: from) {
            return frame(for: slot, in: to)
        }
        return proportionalFrame(w, from: from, to: to)
    }

    /// visibleFrame(메뉴바·Dock 제외 영역) 안에서 한 칸의 프레임(Cocoa 좌표).
    ///
    /// 경계 좌표를 먼저 구하고 폭은 뺄셈으로 유도한다. 폭을 각각 나눗셈으로 계산하면
    /// 좌 2/3 의 오른쪽 끝과 우 1/3 의 왼쪽 끝이 어긋나 틈이나 겹침이 생긴다.
    static func frame(for slot: SnapSlot, in vf: NSRect) -> NSRect {
        let x0 = vf.minX
        let x1 = vf.minX + vf.width / 3
        let x2 = vf.midX
        let x3 = vf.minX + vf.width * 2 / 3
        let x4 = vf.maxX

        let left: CGFloat
        let right: CGFloat
        switch slot {
        case .leftThird:      (left, right) = (x0, x1)
        case .leftHalf:       (left, right) = (x0, x2)
        case .leftTwoThirds:  (left, right) = (x0, x3)
        case .rightTwoThirds: (left, right) = (x1, x4)
        case .rightHalf:      (left, right) = (x2, x4)
        case .rightThird:     (left, right) = (x3, x4)
        }
        return NSRect(x: left, y: vf.minY, width: right - left, height: vf.height)
    }

    /// 창이 지금 어느 칸에 놓여 있는지. 여섯 칸 어디에도 해당하지 않으면 nil.
    ///
    /// 상태를 저장하지 않고 매번 실제 프레임으로 판정한다 — 마우스로 창을 옮겼든 앱을
    /// 재시작했든 결과가 같고, 여러 창을 번갈아 써도 서로 간섭하지 않는다.
    static func currentSlot(of windowFrame: NSRect?, in vf: NSRect) -> SnapSlot? {
        guard let windowFrame else { return nil }
        return SnapSlot.allCases.first { occupies(windowFrame, frame(for: $0, in: vf)) }
    }

    /// **절반 키가 쓰는 규칙** — 가로 범위가 겹치지 않는, 그 방향의 가장 가까운 화면.
    ///
    /// 가로가 겹치는 화면은 좌우 관계가 아니라 위아래 관계다(노트북 위에 모니터를 올린 배치).
    /// 이런 화면을 좌우로 취급하면 오른쪽으로 밀었는데 창이 아래 화면으로 내려가 미는 방향과
    /// 도착지가 어긋난다. 화면 중심(midX)을 비교하던 예전 방식이 정확히 그랬다 — 두 화면의
    /// midX 가 1pt 차이로 갈렸다.
    ///
    /// 가로 간격이 같은 화면이 여럿이면 위쪽(maxY 큰 쪽)을 고른다. `max(by:)`/`min(by:)` 역시
    /// 동점일 때 어느 쪽을 돌려줄지 보장하지 않으므로 규칙으로 못 박는다.
    static func sideScreen(of screen: SnapScreen, in screens: [SnapScreen], toLeft: Bool) -> SnapScreen? {
        let vf = screen.visibleFrame
        if toLeft {
            return screens
                .filter { $0.visibleFrame.maxX <= vf.minX }
                .max { a, b in
                    a.visibleFrame.maxX != b.visibleFrame.maxX
                        ? a.visibleFrame.maxX < b.visibleFrame.maxX
                        : a.visibleFrame.maxY < b.visibleFrame.maxY
                }
        }
        return screens
            .filter { $0.visibleFrame.minX >= vf.maxX }
            .min { a, b in
                a.visibleFrame.minX != b.visibleFrame.minX
                    ? a.visibleFrame.minX < b.visibleFrame.minX
                    : a.visibleFrame.maxY > b.visibleFrame.maxY
            }
    }

    /// **즉시 이동 키가 쓰는 규칙** — 모든 화면을 왼쪽 끝(`visibleFrame.minX`) 순으로 줄 세운다.
    /// 왼쪽 끝이 같으면 위쪽(maxY 큰 쪽)이 앞.
    ///
    /// 절반 키의 `sideScreen` 과 달리 겹침을 따지지 않으므로 **모든 화면이 순회에 들어온다**.
    /// 다른 화면에 가로로 감싸인 화면(노트북 위에 모니터를 올린 배치의 노트북 화면)은 좌우
    /// 이웃이 없어 절반 키로는 드나들 수 없는데, 이 키가 그 길을 만든다.
    ///
    /// 정렬 키를 둘 다 못 박는 이유: Swift 의 `sorted(by:)` 는 안정 정렬을 보장하지 않아,
    /// 같은 값끼리의 순서를 규칙으로 정하지 않으면 실행마다 달라질 수 있다.
    static func orderedScreens(_ screens: [SnapScreen]) -> [SnapScreen] {
        screens.sorted {
            if $0.visibleFrame.minX != $1.visibleFrame.minX {
                return $0.visibleFrame.minX < $1.visibleFrame.minX
            }
            return $0.visibleFrame.maxY > $1.visibleFrame.maxY
        }
    }

    /// 줄에서 `delta` 칸 옆의 화면. 줄 끝이면 nil.
    static func neighborScreen(of screen: SnapScreen, in screens: [SnapScreen], delta: Int) -> SnapScreen? {
        let ordered = orderedScreens(screens)
        guard let i = ordered.firstIndex(of: screen) else { return nil }
        let j = i + delta
        guard ordered.indices.contains(j) else { return nil }
        return ordered[j]
    }

    /// 창의 상대 위치·크기를 유지한 채 다른 화면으로 옮긴다(목표 화면 밖으로 나가지 않게 가둔다).
    static func proportionalFrame(_ rect: NSRect, from: NSRect, to: NSRect) -> NSRect {
        guard from.width > 0, from.height > 0 else { return to }
        let sx = to.width / from.width
        let sy = to.height / from.height
        let w = min(rect.width * sx, to.width)
        let h = min(rect.height * sy, to.height)
        let x = to.minX + (rect.minX - from.minX) * sx
        let y = to.minY + (rect.minY - from.minY) * sy
        return NSRect(x: min(max(x, to.minX), to.maxX - w),
                      y: min(max(y, to.minY), to.maxY - h),
                      width: w, height: h)
    }

    /// 두 사각형이 대략 같은 위치·크기인지(창이 픽셀 단위로 딱 맞지 않을 수 있어 허용 오차를 둔다).
    /// 이웃한 두 칸은 화면 폭의 1/6 만큼 떨어져 있어(내장 화면에서도 252pt) 오차 안에서 헷갈리지 않는다.
    static func occupies(_ a: NSRect, _ b: NSRect, tolerance: CGFloat = 30) -> Bool {
        abs(a.minX - b.minX) <= tolerance &&
        abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance &&
        abs(a.height - b.height) <= tolerance
    }

    /// Cocoa(좌하단 원점) → AX/Quartz(좌상단 원점) 전역 좌표. primaryHeight = 주 화면 frame 높이.
    static func cocoaToAXRect(_ rect: NSRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: AX 헬퍼

    /// 좌표 뒤집기 기준: 전역 원점(좌상단)에 해당하는 **주 화면**(= Cocoa frame origin이 (0,0))의 높이.
    /// NSScreen.screens 의 첫 요소가 항상 주 화면이라는 보장이 없으므로 origin==0 인 화면을 직접 찾는다
    /// (외장 모니터를 '주 디스플레이'로 둔 경우 등 멀티모니터 정확도).
    private static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }

    private static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard err == .success, let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    /// 마지막으로 옮긴 창과 그때 지시한 목표 프레임(Cocoa 좌표).
    ///
    /// AX 는 크기·위치 변경을 앱에 **비동기로** 전달한다. 그래서 키를 빠르게 연달아 누르면 다음
    /// 판정이 아직 반영되지 않은 이전 프레임을 읽어, 같은 자리로 다시 계산하거나(화면을 안 넘어감)
    /// 엉뚱한 자리로 간다 — 천천히 누를 때와 결과가 달라지는 원인이다. 방금 우리가 옮긴 창이라면
    /// 실제 프레임 대신 지시한 목표를 현재 위치로 본다.
    private static var lastSnap: (window: AXUIElement, target: NSRect, at: Date)?

    /// 지시한 목표를 현재 위치로 볼 수 있는 시간. 이보다 오래 지났으면 사용자가 창을 직접 옮겼거나
    /// 앱이 크기를 되돌렸을 수 있으므로 실제 프레임을 신뢰한다.
    private static let lastSnapTrustWindow: TimeInterval = 1.5

    /// 판정에 쓸 프레임. 방금 우리가 옮긴 창이면 지시한 목표를, 아니면 실제 프레임을 돌려준다.
    private static func effectiveFrame(of window: AXUIElement) -> NSRect? {
        if let last = lastSnap,
           CFEqual(last.window, window),
           Date().timeIntervalSince(last.at) < lastSnapTrustWindow {
            return last.target
        }
        return currentFrame(of: window)
    }

    /// 창의 현재 프레임을 Cocoa 좌표로 반환(어느 화면에 있는지 + 지금 어느 칸인지 판정용).
    private static func currentFrame(of window: AXUIElement) -> NSRect? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeVal) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        let cocoaY = primaryHeight - (pos.y + size.height)
        return NSRect(x: pos.x, y: cocoaY, width: size.width, height: size.height)
    }

    /// 창 프레임(Cocoa)이 가장 많이 걸쳐 있는 화면. 프레임을 못 구하면 마우스가 있는 화면.
    private static func screen(for frame: NSRect?) -> NSScreen? {
        guard let frame else {
            return ScreenUtils.screenWithMouse() ?? NSScreen.main
        }
        let best = NSScreen.screens.max { a, b in
            let ia = a.frame.intersection(frame)
            let ib = b.frame.intersection(frame)
            return (ia.width * ia.height) < (ib.width * ib.height)
        }
        return best ?? ScreenUtils.screenWithMouse() ?? NSScreen.main
    }

    private static func setFrame(_ cocoaRect: NSRect, for window: AXUIElement) {
        let ax = cocoaToAXRect(cocoaRect, primaryHeight: primaryHeight)
        let pos = CGPoint(x: ax.minX, y: ax.minY)
        let size = CGSize(width: ax.width, height: ax.height)

        // 다음 키 입력이 아직 반영되지 않은 프레임을 읽지 않도록, 지시한 목표를 먼저 기록한다.
        lastSnap = (window, cocoaRect, Date())

        // 크기 → 위치 → 크기 순.
        // 크기를 먼저 (아직 원래 모니터 위에서) 목표로 줄여두면, 크기가 다른 모니터로 넘어갈 때
        // 큰 창이 두 화면에 걸쳐 크기 변경이 거부/클램프되는 문제를 피한다(→ 이전 모니터 너비로 남던 버그).
        // 이동 후 앱이 되돌렸을 수 있는 크기를 한 번 더 확정한다.
        setSize(size, of: window)
        setPosition(pos, of: window)
        setSize(size, of: window)

        // 더 큰 화면으로 옮길 때는 위 순서만으로 모자란다. AppKit 은 창을 화면 안에 가두면서
        // (NSWindow.constrainFrameRect) **세로만** 잘라낸다 — 가로는 건드리지 않는다. 그래서 창이
        // 아직 작은 화면 위에 있는 동안의 크기 요청은 높이가 이전 화면 기준으로 깎인 채 남고,
        // 폭만 목적지에 맞은 것처럼 보인다. 창이 목적지 화면으로 건너간 뒤 한 번 더 맞춘다.
        //
        // 확인을 곧바로 하지 않고 한 박자 미루는 이유: AX 변경은 앱이 비동기로 처리하므로 지금
        // 읽으면 아직 옮겨지기 전 프레임이 돌아온다. 단축키 응답은 위 동기 설정으로 이미 끝났고,
        // 이 보정은 뒤늦게 따라붙는다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 그 사이 다른 스냅이 일어났으면 건드리지 않는다(연타 중 이전 목표로 되돌리지 않도록).
            guard let last = lastSnap, CFEqual(last.window, window), last.target == cocoaRect else { return }
            guard let landed = currentFrame(of: window), !occupies(landed, cocoaRect, tolerance: 4) else { return }
            setPosition(pos, of: window)
            setSize(size, of: window)
            setPosition(pos, of: window)
        }
    }

    private static func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    private static func setSize(_ sizeValue: CGSize, of window: AXUIElement) {
        var s = sizeValue
        if let value = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }
}
