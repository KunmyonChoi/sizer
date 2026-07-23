import Foundation

/// 앱 번들의 버전 정보. Info.plist(CFBundleShortVersionString/CFBundleVersion)에서 읽는다.
/// 값은 project.yml의 MARKETING_VERSION / CURRENT_PROJECT_VERSION에서 생성된다.
enum AppInfo {

    /// 마케팅 버전(예: "1.5.1"). 없으면 "—".
    static var version: String {
        string(for: "CFBundleShortVersionString")
    }

    /// 빌드 번호(예: "7"). 없으면 "—".
    static var build: String {
        string(for: "CFBundleVersion")
    }

    /// 짧은 표기(예: "v1.5.1") — 메뉴바 헤더용.
    static var shortVersion: String { "v\(version)" }

    /// 상세 표기(예: "1.5.1 (7)") — 설정 화면용.
    static var fullVersion: String { "\(version) (\(build))" }

    private static func string(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return "—" }
        return value
    }
}
