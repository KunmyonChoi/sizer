import Foundation

/// 한 파일 변환의 결과 요약(코디네이터가 히스토리로 기록).
struct JobOutcome {
    let sourceName: String
    let outputName: String?
    let outputURL: URL?
    let kind: MediaKind
    let success: Bool
    let detail: String
}

/// 한 파일에 대한 전체 변환 파이프라인(probe → 정지 감지 → 플랜 → 변환 → 원본 이동 → 알림).
/// 백그라운드 큐에서 동기 실행된다.
enum ConversionEngine {

    /// 확장자에 따라 영상/이미지 변환으로 분기.
    static func process(_ src: URL, config: ConversionConfig) -> JobOutcome {
        let ext = src.pathExtension.lowercased()
        if ConversionConfig.imageExtensions.contains(ext) {
            return convertImage(src, config: config)
        }
        return convert(src, config: config)
    }

    static func convert(_ src: URL, config: ConversionConfig) -> JobOutcome {
        let fm = FileManager.default
        let name = src.lastPathComponent
        let origSize = fileSize(src)

        guard let ffmpeg = FFmpeg.ffmpegURL else {
            AppLogger.error("ffmpeg 없음 — 변환 불가: \(name)")
            return JobOutcome(sourceName: name, outputName: nil, outputURL: nil, kind: .video, success: false, detail: "ffmpeg 없음")
        }

        let dst = uniqueOutputPath(for: src, config: config)
        let tmp = dst.appendingPathExtension("part")

        let hasAudio = Probe.hasAudio(src)
        let duration = Probe.duration(src)

        // 움직임 없는 구간 계획
        var keepSegments: [Segment]? = nil
        var removed = 0.0
        if config.trimStill && duration > 0 {
            let freezes = FreezeDetector.detectFreezes(url: src, duration: duration, options: config.trimOptions)
            if !freezes.isEmpty {
                if let segments = SegmentPlanner.plan(freezes: freezes, duration: duration,
                                                      options: config.trimOptions, sceneChanges: []) {
                    keepSegments = segments
                    let kept = segments.totalDuration
                    removed = duration - kept
                    AppLogger.info(String(format: "정지 구간 %d곳, %.1fs 제거 → %.1fs 편집 (%@)",
                                          freezes.count, removed, kept, name))
                } else {
                    AppLogger.warn("움직임 구간이 거의 없거나 제거량이 미미하여 트리밍 생략: \(name)")
                }
            }
        }

        AppLogger.info("변환 시작: \(name) (\(humanSize(origSize)))")
        let args = FilterGraphBuilder.build(src: src, dst: tmp, config: config,
                                            keepSegments: keepSegments, hasAudio: hasAudio)

        let start = Date()
        let result = FFmpeg.run(ffmpeg, args)
        let elapsed = Date().timeIntervalSince(start)

        if !result.succeeded || !fm.fileExists(atPath: tmp.path) {
            try? fm.removeItem(at: tmp)
            let tail = result.stderr.split(separator: "\n").suffix(3).joined(separator: " / ")
            AppLogger.error("변환 실패: \(name) — \(tail)")
            moveOriginal(src, to: config.failedFolder)
            if config.notificationsEnabled {
                Notifier.notify(title: "변환 실패 ❌", body: name, subtitle: "failed 폴더로 이동됨")
            }
            return JobOutcome(sourceName: name, outputName: nil, outputURL: nil, kind: .video, success: false, detail: "실패 · failed로 이동")
        }

        try? fm.removeItem(at: dst)
        do {
            try fm.moveItem(at: tmp, to: dst)
        } catch {
            AppLogger.error("결과 파일 이름 변경 실패: \(error.localizedDescription)")
            try? fm.removeItem(at: tmp)
            moveOriginal(src, to: config.failedFolder)
            return JobOutcome(sourceName: name, outputName: nil, outputURL: nil, kind: .video, success: false, detail: "결과 저장 실패")
        }

        let newSize = fileSize(dst)
        let saved = origSize > 0 ? 100.0 * (1.0 - Double(newSize) / Double(origSize)) : 0
        var detail = "\(humanSize(origSize)) → \(humanSize(newSize)) (\(Int(saved))% 절감)"
        if keepSegments != nil { detail += " · 정지 \(Int(removed))s 제거" }

        AppLogger.info(String(format: "변환 완료: %@ → %@ (%@, %.1fs)", name, dst.lastPathComponent, detail, elapsed))
        moveOriginal(src, to: config.processedFolder, stampDate: true)
        if config.notificationsEnabled {
            Notifier.notify(title: "Sizer 변환 완료 ✅", body: dst.lastPathComponent, subtitle: detail)
        }
        return JobOutcome(sourceName: name, outputName: dst.lastPathComponent, outputURL: dst, kind: .video, success: true, detail: detail)
    }

    // MARK: 이미지 변환

    static func convertImage(_ src: URL, config: ConversionConfig) -> JobOutcome {
        let fm = FileManager.default
        let name = src.lastPathComponent
        let origSize = fileSize(src)

        let dst = uniqueImageOutputPath(for: src, config: config)
        let tmp = dst.appendingPathExtension("part")

        AppLogger.info("이미지 변환 시작: \(name) (\(humanSize(origSize))) → \(config.imageFormat.fileExtension)")
        let result = ImageConverter.convert(
            src: src, dst: tmp,
            format: config.imageFormat,
            quality: config.imageQuality,
            maxLongEdge: config.imageMaxLongEdge
        )

        if !result.success || !fm.fileExists(atPath: tmp.path) {
            try? fm.removeItem(at: tmp)
            AppLogger.error("이미지 변환 실패: \(name) — \(result.error ?? "")")
            moveOriginal(src, to: config.failedFolder)
            if config.notificationsEnabled {
                Notifier.notify(title: "이미지 변환 실패 ❌", body: name, subtitle: "failed 폴더로 이동됨")
            }
            return JobOutcome(sourceName: name, outputName: nil, outputURL: nil, kind: .image, success: false, detail: "실패 · failed로 이동")
        }

        try? fm.removeItem(at: dst)
        do {
            try fm.moveItem(at: tmp, to: dst)
        } catch {
            try? fm.removeItem(at: tmp)
            moveOriginal(src, to: config.failedFolder)
            return JobOutcome(sourceName: name, outputName: nil, outputURL: nil, kind: .image, success: false, detail: "결과 저장 실패")
        }

        let newSize = fileSize(dst)
        let saved = origSize > 0 ? 100.0 * (1.0 - Double(newSize) / Double(origSize)) : 0
        let detail = "\(humanSize(origSize)) → \(humanSize(newSize)) (\(Int(saved))% 절감)"
        AppLogger.info("이미지 변환 완료: \(name) → \(dst.lastPathComponent) (\(detail))")
        moveOriginal(src, to: config.processedFolder, stampDate: true)
        if config.notificationsEnabled {
            Notifier.notify(title: "이미지 변환 완료 ✅", body: dst.lastPathComponent, subtitle: detail)
        }
        return JobOutcome(sourceName: name, outputName: dst.lastPathComponent, outputURL: dst, kind: .image, success: true, detail: detail)
    }

    private static func uniqueImageOutputPath(for src: URL, config: ConversionConfig) -> URL {
        let stem = src.deletingPathExtension().lastPathComponent
        let ext = config.imageFormat.fileExtension
        let base = stem + config.outputSuffix
        var candidate = config.outputFolder.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = config.outputFolder.appendingPathComponent("\(base)_\(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    // MARK: helpers

    private static func uniqueOutputPath(for src: URL, config: ConversionConfig) -> URL {
        let stem = src.deletingPathExtension().lastPathComponent
        let ext = config.outputExt.hasPrefix(".") ? String(config.outputExt.dropFirst()) : config.outputExt
        let base = stem + config.outputSuffix
        var candidate = config.outputFolder.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = config.outputFolder.appendingPathComponent("\(base)_\(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private static func moveOriginal(_ src: URL, to destDir: URL, stampDate: Bool = false) {
        let fm = FileManager.default
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        var dest = destDir.appendingPathComponent(src.lastPathComponent)
        let stem = src.deletingPathExtension().lastPathComponent
        let ext = src.pathExtension
        var counter = 1
        while fm.fileExists(atPath: dest.path) {
            let newName = ext.isEmpty ? "\(stem)_\(counter)" : "\(stem)_\(counter).\(ext)"
            dest = destDir.appendingPathComponent(newName)
            counter += 1
        }
        do {
            try fm.moveItem(at: src, to: dest)
            // 보관 기간을 'processed로 이동된 시점' 기준으로 세도록 수정일 갱신.
            if stampDate {
                try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
            }
        } catch {
            AppLogger.warn("원본 이동 실패(\(src.lastPathComponent)): \(error.localizedDescription)")
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    static func humanSize(_ bytes: Int64) -> String {
        var size = Double(bytes)
        for unit in ["B", "KB", "MB", "GB"] {
            if size < 1024 || unit == "GB" {
                return String(format: "%.1f%@", size, unit)
            }
            size /= 1024
        }
        return String(format: "%.1fGB", size)
    }
}
