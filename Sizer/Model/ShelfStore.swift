import Foundation

/// 셸프에 담긴 파일 하나(원본 참조).
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }
}

/// 임시 파일 보관대. 원본 URL을 참조로 담아 두었다가 드래그로 꺼낸다.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var newItemIDs: Set<UUID> = []   // 방금 얹힌 변환 결과(NEW 배지용, S5)

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    /// URL들을 추가(같은 경로 중복은 무시). 추가된 개수 반환.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.isFileURL {
            let std = url.standardizedFileURL
            guard !items.contains(where: { $0.url.standardizedFileURL == std }) else { continue }
            items.append(ShelfItem(url: std))
            added += 1
        }
        return added
    }

    /// 결과 파일을 트레이 맨 앞(가장 최근)에 삽입. 중복이면 무시. 추가되면 true(S5).
    @discardableResult
    func insertFront(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let std = url.standardizedFileURL
        guard !items.contains(where: { $0.url.standardizedFileURL == std }) else { return false }
        let item = ShelfItem(url: std)
        items.insert(item, at: 0)
        markNew(item.id)
        return true
    }

    /// 방금 얹힌 결과를 잠깐 'NEW'로 표시(S5). 몇 초 뒤 자동 해제.
    private func markNew(_ id: UUID) {
        newItemIDs.insert(id)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.newItemIDs.remove(id)
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        newItemIDs.remove(item.id)
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        newItemIDs.remove(id)
    }

    func clear() {
        items.removeAll()
        newItemIDs.removeAll()
    }
}

/// 통합 셸프 패널에서 드롭이 향하는 존. 상단은 변환, 하단은 보관.
enum ShelfDropZone: Equatable {
    case convert   // 상단 변환 드롭존(구 드롭 타겟)
    case hold      // 하단 보관 트레이

    /// 드롭 지점이 어느 존인지(AppKit 좌표, origin 좌하단). 순수 함수 — 단위 테스트 대상.
    /// 통합(integrated)·펼침(expanded) 상태에서 핸들을 벗어난 상단 영역만 변환존, 그 외는 모두 보관.
    static func at(_ p: CGPoint, panelHeight: CGFloat, handleWidth: CGFloat,
                   convertZoneHeight: CGFloat, integrated: Bool, expanded: Bool) -> ShelfDropZone {
        guard integrated, expanded, p.x >= handleWidth else { return .hold }
        return p.y >= panelHeight - convertZoneHeight ? .convert : .hold
    }
}

/// 통합 패널의 드래그/드롭 시각 상태(존 하이라이트 + 성공·거부 플래시). 컨트롤러가 갱신, ShelfView가 관찰.
@MainActor
final class ShelfDropState: ObservableObject {
    @Published var activeZone: ShelfDropZone?   // 현재 강조 중인 존(C1/C3)
    @Published var convertFlash: Int?           // 변환 시작 성공 카운트(잠깐 표시)
    @Published var rejectFlash = false          // 변환 불가 형식 거부(C2, 잠깐 표시)

    private var flashTask: Task<Void, Never>?

    func setZone(_ zone: ShelfDropZone?) {
        if activeZone != zone { activeZone = zone }
    }

    func flashConvert(_ count: Int) {
        rejectFlash = false
        convertFlash = count
        scheduleClear()
    }

    func flashReject() {
        convertFlash = nil
        rejectFlash = true
        scheduleClear()
    }

    private func scheduleClear() {
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self, !Task.isCancelled else { return }
            self.convertFlash = nil
            self.rejectFlash = false
        }
    }
}
