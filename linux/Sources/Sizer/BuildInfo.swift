/// Linux 빌드의 버전 정보. macOS 는 Info.plist(AppInfo)에서 읽지만 Linux 실행 파일에는 번들이 없다.
/// project.yml 의 MARKETING_VERSION 과 같아야 한다(BuildInfoTests 가 검사).
enum BuildInfo {
    static let version = "1.10.0"
}
