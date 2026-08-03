import AppKit
import ApplicationServices

/// 창 스냅(윈도우 타일링) 위치.
enum SnapPosition: String, CaseIterable {
    case leftHalf
    case rightHalf
    case maximize
}

/// 화면 하나의 기하(NSScreen에서 분리해 순수 로직을 테스트 가능하게 함).
struct SnapScreen: Equatable {
    let frame: NSRect         // 전역 Cocoa 좌표(모니터 배치 판정용)
    let visibleFrame: NSRect  // 메뉴바·Dock 제외 영역(실제 배치 대상)
}

/// 손쉬운 사용(Accessibility) API로 **현재 최상위 앱의 포커스 창**을 화면 좌/우 절반 또는 최대화로 배치한다.
/// 멀티 모니터에서 **같은 방향키를 반복하면 인접 모니터로 넘어간다**(Magnet식):
///   좌측 반 → (이미 좌측 반이면) 왼쪽 모니터의 우측 반 → 그 화면 좌측 반 → … (왼쪽 끝에서 멈춤)
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

    /// 최상위 앱의 포커스 창을 지정 위치로 배치. 권한이 없으면 프롬프트만 띄우고 false 반환.
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
        let winFrame = currentFrame(of: window)
        guard let screen = screen(for: winFrame) else { return false }

        let screens = NSScreen.screens.map { SnapScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let current = SnapScreen(frame: screen.frame, visibleFrame: screen.visibleFrame)
        let target = resolveTarget(position, windowFrame: winFrame, currentScreen: current, screens: screens)
        setFrame(target, for: window)
        return true
    }

    // MARK: 순수 계산(테스트 대상)

    /// 목표 프레임 결정. 같은 방향으로 **이미 배치돼 있으면 인접 모니터로 넘어간다**(Magnet식).
    static func resolveTarget(_ position: SnapPosition,
                              windowFrame: NSRect?,
                              currentScreen: SnapScreen,
                              screens: [SnapScreen]) -> NSRect {
        switch position {
        case .maximize:
            return targetFrame(for: .maximize, in: currentScreen.visibleFrame)

        case .leftHalf:
            let here = targetFrame(for: .leftHalf, in: currentScreen.visibleFrame)
            // 이미 현재 화면 좌측 반이면 → 왼쪽 인접 모니터의 우측 반으로 넘어간다.
            if let w = windowFrame, occupies(w, here),
               let left = adjacentScreen(of: currentScreen, in: screens, toLeft: true) {
                return targetFrame(for: .rightHalf, in: left.visibleFrame)
            }
            return here

        case .rightHalf:
            let here = targetFrame(for: .rightHalf, in: currentScreen.visibleFrame)
            // 이미 현재 화면 우측 반이면 → 오른쪽 인접 모니터의 좌측 반으로 넘어간다.
            if let w = windowFrame, occupies(w, here),
               let right = adjacentScreen(of: currentScreen, in: screens, toLeft: false) {
                return targetFrame(for: .leftHalf, in: right.visibleFrame)
            }
            return here
        }
    }

    /// visibleFrame(메뉴바·Dock 제외 영역) 안에서의 목표 프레임(Cocoa 좌표).
    static func targetFrame(for position: SnapPosition, in vf: NSRect) -> NSRect {
        switch position {
        case .leftHalf:
            return NSRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .rightHalf:
            return NSRect(x: vf.midX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .maximize:
            return vf
        }
    }

    /// 현재 화면 기준 왼쪽/오른쪽으로 **가장 가까운** 인접 화면(수평 중심 거리 기준). 없으면 nil.
    static func adjacentScreen(of screen: SnapScreen, in screens: [SnapScreen], toLeft: Bool) -> SnapScreen? {
        let cx = screen.frame.midX
        return screens
            .filter { $0 != screen }
            .filter { toLeft ? $0.frame.midX < cx : $0.frame.midX > cx }
            .min { abs($0.frame.midX - cx) < abs($1.frame.midX - cx) }
    }

    /// 두 사각형이 대략 같은 위치·크기인지(창이 픽셀 단위로 딱 맞지 않을 수 있어 허용 오차를 둔다).
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

    /// 창의 현재 프레임을 Cocoa 좌표로 반환(어느 화면에 있는지 + 이미 반쪽인지 판정용).
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
        var pos = CGPoint(x: ax.minX, y: ax.minY)
        var size = CGSize(width: ax.width, height: ax.height)

        // 위치 → 크기 → 위치 순. 일부 앱은 최소 크기 제약으로 첫 위치가 밀리므로 마지막에 한 번 더 맞춘다.
        if let posValue = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }
}
