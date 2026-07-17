import Foundation

/// ffprobe로 영상 메타데이터를 조회.
enum Probe {
    /// 영상 길이(초). 실패 시 0.
    static func duration(_ url: URL) -> Double {
        guard let ffprobe = FFmpeg.ffprobeURL else { return 0 }
        let r = FFmpeg.run(ffprobe, [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=nk=1:nw=1",
            url.path,
        ], timeout: 30)
        return Double(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// 오디오 스트림 존재 여부. 알 수 없으면 있다고 가정.
    static func hasAudio(_ url: URL) -> Bool {
        guard let ffprobe = FFmpeg.ffprobeURL else { return true }
        let r = FFmpeg.run(ffprobe, [
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=index",
            "-of", "csv=p=0",
            url.path,
        ], timeout: 30)
        return !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
