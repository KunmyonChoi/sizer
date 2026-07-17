#!/usr/bin/env python3
"""
input 폴더를 감시하다가 새 영상이 들어오면
SNS 공유용 고해상도 저용량 비디오로 변환하여 output 폴더로 저장하고,
macOS 알림을 띄우는 백그라운드 워커.

외부 파이썬 패키지 없이 표준 라이브러리 + ffmpeg + osascript 만 사용한다.
"""

from __future__ import annotations

import logging
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

# ---------------------------------------------------------------------------
# 설정 (필요하면 이 부분만 바꾸면 된다)
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent

INPUT_DIR = BASE_DIR / "input"        # 여기에 영상을 넣으면
OUTPUT_DIR = BASE_DIR / "output"      # 변환 결과가 여기에 저장된다
PROCESSED_DIR = BASE_DIR / "processed"  # 변환에 성공한 원본은 여기로 이동
FAILED_DIR = BASE_DIR / "failed"      # 변환에 실패한 원본은 여기로 이동
LOG_DIR = BASE_DIR / "logs"

POLL_INTERVAL = 3          # 폴더를 확인하는 주기(초)
STABILITY_CHECKS = 2       # 파일 크기가 N번 연속 그대로면 "복사 완료"로 판단
STABILITY_INTERVAL = 2     # 안정성 확인 사이 대기(초)

# 처리할 영상 확장자
VIDEO_EXTS = {
    ".mp4", ".mov", ".mkv", ".avi", ".m4v", ".webm",
    ".flv", ".wmv", ".mpg", ".mpeg", ".3gp", ".ts", ".mts",
}

# --- ffmpeg 인코딩 설정 (SNS 공유용: 고해상도 저용량) ---
VIDEO_CODEC = "libx264"    # H.264 = SNS 최대 호환. 더 작게 원하면 "libx265"
CRF = 26                   # 화질/용량 균형. 낮을수록 고화질/큰용량(18~28 권장)
PRESET = "slow"            # 압축 효율. slow=더 작은 용량(대신 느림)
MAX_LONG_EDGE = 1920       # 장변 최대 픽셀(1080p급). 이보다 크면 축소, 작으면 유지
AUDIO_BITRATE = "128k"
OUTPUT_SUFFIX = "_sns"     # 출력 파일명 접미사
OUTPUT_EXT = ".mp4"
OUTPUT_FORMAT = "mp4"      # ffmpeg 컨테이너 포맷(.part 임시확장자에서도 필요)

# --- 움직임 없는(정지) 구간 잘라내기 옵션 ---
TRIM_STILL = True          # True면 정지 구간을 잘라내고 움직임 구간만 이어붙인다
STILL_MIN_DURATION = 2.0   # 이 시간(초) 이상 움직임이 없으면 그 구간을 잘라냄
STILL_NOISE = "-50dB"      # 정지 판단 민감도. 0에 가까울수록(예: -40dB) 공격적으로,
                           # -60dB 처럼 낮출수록 엄격하게(거의 완전 정지만) 잘라냄
STILL_MIN_KEEP_RATIO = 0.02  # 잘라낸 뒤 남는 길이가 원본의 이 비율 미만이면 트리밍 취소(안전장치)

# ---------------------------------------------------------------------------
# 준비
# ---------------------------------------------------------------------------
# launchd 등 최소 PATH 환경에서도 ffmpeg / osascript 를 찾도록 경로 보강
for extra in ("/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"):
    if extra not in os.environ.get("PATH", "").split(os.pathsep):
        os.environ["PATH"] = os.environ.get("PATH", "") + os.pathsep + extra

FFMPEG = shutil.which("ffmpeg")
FFPROBE = shutil.which("ffprobe")
OSASCRIPT = shutil.which("osascript")

log = logging.getLogger("sns-video")


def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log.setLevel(logging.INFO)
    handler = RotatingFileHandler(
        LOG_DIR / "convert.log", maxBytes=1_000_000, backupCount=3, encoding="utf-8"
    )
    handler.setFormatter(
        logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", "%Y-%m-%d %H:%M:%S")
    )
    log.addHandler(handler)
    # launchd 로그(StandardOutPath)에도 남기기 위해 콘솔 핸들러도 추가
    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", "%Y-%m-%d %H:%M:%S"))
    log.addHandler(console)


def ensure_dirs() -> None:
    for d in (INPUT_DIR, OUTPUT_DIR, PROCESSED_DIR, FAILED_DIR, LOG_DIR):
        d.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# macOS 알림
# ---------------------------------------------------------------------------
def _applescript_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def notify(title: str, message: str, subtitle: str = "", sound: str = "Glass") -> None:
    """macOS 알림 센터에 배너를 띄운다."""
    if not OSASCRIPT:
        return
    script = (
        f'display notification "{_applescript_escape(message)}" '
        f'with title "{_applescript_escape(title)}"'
    )
    if subtitle:
        script += f' subtitle "{_applescript_escape(subtitle)}"'
    if sound:
        script += f' sound name "{_applescript_escape(sound)}"'
    try:
        subprocess.run([OSASCRIPT, "-e", script], check=False, timeout=10)
    except Exception as exc:  # 알림 실패가 변환을 막으면 안 된다
        log.warning("알림 실패: %s", exc)


# ---------------------------------------------------------------------------
# 파일 안정성(복사 완료) 확인
# ---------------------------------------------------------------------------
def is_stable(path: Path) -> bool:
    """파일 크기가 STABILITY_CHECKS 번 연속 동일하면 복사가 끝난 것으로 본다."""
    try:
        last = -1
        for _ in range(STABILITY_CHECKS):
            size = path.stat().st_size
            if size == 0 or size != last:
                last = size
                time.sleep(STABILITY_INTERVAL)
            else:
                time.sleep(STABILITY_INTERVAL)
        # 마지막으로 한 번 더 비교
        return path.exists() and path.stat().st_size == last and last > 0
    except FileNotFoundError:
        return False


# ---------------------------------------------------------------------------
# 변환
# ---------------------------------------------------------------------------
def unique_output_path(src: Path) -> Path:
    base = src.stem + OUTPUT_SUFFIX
    candidate = OUTPUT_DIR / f"{base}{OUTPUT_EXT}"
    counter = 1
    while candidate.exists():
        candidate = OUTPUT_DIR / f"{base}_{counter}{OUTPUT_EXT}"
        counter += 1
    return candidate


def human_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}GB"


def probe_duration(src: Path) -> float:
    """영상 길이(초)를 반환. 실패 시 0.0"""
    if not FFPROBE:
        return 0.0
    try:
        out = subprocess.run(
            [FFPROBE, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nk=1:nw=1", str(src)],
            capture_output=True, text=True, timeout=30,
        ).stdout.strip()
        return float(out)
    except Exception:
        return 0.0


def has_audio_stream(src: Path) -> bool:
    """오디오 스트림 존재 여부. 알 수 없으면 있다고 가정."""
    if not FFPROBE:
        return True
    try:
        out = subprocess.run(
            [FFPROBE, "-v", "error", "-select_streams", "a",
             "-show_entries", "stream=index", "-of", "csv=p=0", str(src)],
            capture_output=True, text=True, timeout=30,
        ).stdout.strip()
        return bool(out)
    except Exception:
        return True


def detect_freeze_intervals(src: Path, duration: float) -> list[tuple[float, float]]:
    """freezedetect 필터로 '움직임 없는(정지)' 구간 [(start, end), ...] 을 찾는다."""
    cmd = [
        FFMPEG, "-hide_banner", "-i", str(src),
        "-vf", f"freezedetect=n={STILL_NOISE}:d={STILL_MIN_DURATION}",
        "-an", "-f", "null", "-",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    text = proc.stderr + proc.stdout
    starts = [float(m) for m in re.findall(r"freeze_start[:=]\s*([0-9.]+)", text)]
    ends = [float(m) for m in re.findall(r"freeze_end[:=]\s*([0-9.]+)", text)]
    intervals: list[tuple[float, float]] = []
    for i, s in enumerate(starts):
        e = ends[i] if i < len(ends) else duration  # 영상 끝까지 정지면 EOF 까지로 처리
        if e > s:
            intervals.append((max(0.0, s), min(duration or e, e)))
    return intervals


def compute_keep_segments(
    freezes: list[tuple[float, float]], duration: float
) -> list[tuple[float, float]]:
    """정지 구간의 여집합 = 유지할 '움직임' 구간 [(start, end), ...]."""
    keep: list[tuple[float, float]] = []
    cursor = 0.0
    for s, e in sorted(freezes):
        if s > cursor:
            keep.append((cursor, s))
        cursor = max(cursor, e)
    if duration - cursor > 0.05:
        keep.append((cursor, duration))
    # 0.1초 미만의 지나치게 짧은 조각은 버린다
    return [(a, b) for a, b in keep if b - a >= 0.1]


def build_ffmpeg_cmd(
    src: Path, dst: Path,
    keep_segments: list[tuple[float, float]] | None = None,
    has_audio: bool = True,
) -> list[str]:
    # 장변(가로/세로 중 긴 쪽)을 MAX_LONG_EDGE 이하로 축소, 원본이 더 작으면 그대로 유지.
    # 방향(가로/세로)에 상관없이 동작하고, 홀수 픽셀은 -2 로 자동 짝수 보정한다.
    scale = (
        f"scale='if(gt(iw,ih),min({MAX_LONG_EDGE},iw),-2)':"
        f"'if(gt(iw,ih),-2,min({MAX_LONG_EDGE},ih))'"
    )

    cmd = [FFMPEG, "-y", "-i", str(src)]

    if keep_segments:
        # 움직임 구간마다 trim/atrim 으로 잘라 타임스탬프를 0부터 다시 잡고(concat 대비),
        # concat 으로 이어붙인 뒤 스케일을 적용한다. (오디오까지 정확히 동기화되어 잘림)
        parts, vlabels, alabels = [], [], []
        for i, (a, b) in enumerate(keep_segments):
            parts.append(f"[0:v]trim={a:.3f}:{b:.3f},setpts=PTS-STARTPTS[v{i}]")
            vlabels.append(f"[v{i}]")
            if has_audio:
                parts.append(f"[0:a]atrim={a:.3f}:{b:.3f},asetpts=PTS-STARTPTS[a{i}]")
                alabels.append(f"[a{i}]")
        n = len(keep_segments)
        if has_audio:
            inputs = "".join(v + a for v, a in zip(vlabels, alabels))
            parts.append(f"{inputs}concat=n={n}:v=1:a=1[vc][aout]")
        else:
            parts.append(f"{''.join(vlabels)}concat=n={n}:v=1:a=0[vc]")
        parts.append(f"[vc]{scale}[vout]")
        cmd += ["-filter_complex", ";".join(parts), "-map", "[vout]"]
        if has_audio:
            cmd += ["-map", "[aout]"]
    else:
        cmd += ["-vf", scale]

    cmd += ["-c:v", VIDEO_CODEC, "-crf", str(CRF), "-preset", PRESET, "-pix_fmt", "yuv420p"]
    if has_audio:
        cmd += ["-c:a", "aac", "-b:a", AUDIO_BITRATE]
    else:
        cmd += ["-an"]
    cmd += ["-movflags", "+faststart", "-f", OUTPUT_FORMAT, str(dst)]
    return cmd


def convert(src: Path) -> None:
    dst = unique_output_path(src)
    tmp = dst.with_suffix(dst.suffix + ".part")  # 완성 전까지 임시 이름
    orig_size = src.stat().st_size

    has_audio = has_audio_stream(src)
    duration = probe_duration(src)

    # 움직임 없는 구간 잘라내기(옵션)
    keep_segments = None
    removed = 0.0
    if TRIM_STILL and duration > 0:
        try:
            freezes = detect_freeze_intervals(src, duration)
            if freezes:
                segments = compute_keep_segments(freezes, duration)
                kept = sum(b - a for a, b in segments)
                if segments and kept >= duration * STILL_MIN_KEEP_RATIO:
                    keep_segments = segments
                    removed = duration - kept
                    log.info("정지 구간 %d곳 %.1fs 제거 → %.1fs 로 편집 (%s)",
                             len(freezes), removed, kept, src.name)
                else:
                    log.warning("움직임 구간이 거의 없어 트리밍 생략: %s", src.name)
        except Exception as exc:
            log.warning("정지 구간 분석 실패(원본 그대로 변환): %s", exc)

    log.info("변환 시작: %s (%s)", src.name, human_size(orig_size))
    cmd = build_ffmpeg_cmd(src, tmp, keep_segments=keep_segments, has_audio=has_audio)

    start = time.monotonic()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.monotonic() - start

    if proc.returncode != 0 or not tmp.exists():
        tmp.unlink(missing_ok=True)
        # ffmpeg stderr 마지막 줄만 로그로
        tail = (proc.stderr or "").strip().splitlines()[-3:]
        log.error("변환 실패: %s\n%s", src.name, "\n".join(tail))
        move_to(src, FAILED_DIR)
        notify("변환 실패 ❌", src.name, subtitle="failed 폴더로 이동됨", sound="Basso")
        return

    tmp.rename(dst)  # 성공 시에만 최종 이름으로
    new_size = dst.stat().st_size
    saved = 100 * (1 - new_size / orig_size) if orig_size else 0

    trim_note = f", 정지 {removed:.0f}s 제거" if keep_segments else ""
    log.info(
        "변환 완료: %s → %s (%s → %s, %.0f%% 절감%s, %.1fs)",
        src.name, dst.name, human_size(orig_size), human_size(new_size), saved, trim_note, elapsed,
    )
    move_to(src, PROCESSED_DIR)
    subtitle = f"{human_size(orig_size)} → {human_size(new_size)} ({saved:.0f}% 절감)"
    if keep_segments:
        subtitle += f" · 정지 {removed:.0f}s 제거"
    notify("SNS 영상 변환 완료 ✅", f"{dst.name}", subtitle=subtitle, sound="Glass")


def move_to(src: Path, dest_dir: Path) -> None:
    """원본을 대상 폴더로 이동(이름 충돌 시 번호 부여)."""
    dest = dest_dir / src.name
    counter = 1
    while dest.exists():
        dest = dest_dir / f"{src.stem}_{counter}{src.suffix}"
        counter += 1
    try:
        shutil.move(str(src), str(dest))
    except Exception as exc:
        log.warning("원본 이동 실패(%s): %s", src.name, exc)


# ---------------------------------------------------------------------------
# 메인 루프
# ---------------------------------------------------------------------------
_running = True


def _handle_stop(signum, frame):  # launchd 종료 신호 처리
    global _running
    _running = False
    log.info("종료 신호(%s) 수신 — 정리 후 종료합니다.", signum)


def scan_once() -> None:
    for entry in sorted(INPUT_DIR.iterdir()):
        if not _running:
            return
        if entry.name.startswith("."):        # .DS_Store, 임시 dotfile 무시
            continue
        if not entry.is_file():
            continue
        if entry.suffix.lower() not in VIDEO_EXTS:
            continue
        if entry.suffix.lower() == ".part":   # 우리 임시파일 무시
            continue
        if not is_stable(entry):              # 아직 복사 중이면 다음 폴링에서
            log.info("복사 중으로 판단, 대기: %s", entry.name)
            continue
        try:
            convert(entry)
        except Exception as exc:
            log.exception("예외 발생, 건너뜀: %s (%s)", entry.name, exc)


def main() -> None:
    setup_logging()
    ensure_dirs()

    if not FFMPEG:
        log.error("ffmpeg 를 찾을 수 없습니다. 'brew install ffmpeg' 후 다시 실행하세요.")
        notify("SNS 변환기 오류", "ffmpeg 가 설치되어 있지 않습니다.", sound="Basso")
        sys.exit(1)

    signal.signal(signal.SIGTERM, _handle_stop)
    signal.signal(signal.SIGINT, _handle_stop)

    log.info("감시 시작 — input: %s", INPUT_DIR)
    log.info("ffmpeg: %s / codec=%s crf=%s preset=%s 장변<=%s",
             FFMPEG, VIDEO_CODEC, CRF, PRESET, MAX_LONG_EDGE)

    while _running:
        try:
            scan_once()
        except Exception as exc:
            log.exception("스캔 루프 예외: %s", exc)
        # 폴링 간격 동안 잘게 끊어 자며 종료 신호에 빠르게 반응
        for _ in range(POLL_INTERVAL):
            if not _running:
                break
            time.sleep(1)

    log.info("감시 종료.")


if __name__ == "__main__":
    main()
