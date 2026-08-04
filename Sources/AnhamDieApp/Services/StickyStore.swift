import Foundation
import Observation

/// 포스트잇 저장소 (v10 §19.4) — 투두 TaskStore와 분리된 stickies.json.
/// 관찰 분리가 목적: 투두 변경 알림이 열려 있는 노트 카드 창을 재렌더하지 않는다(역도 동일).
/// 저장 규약(자체 version·마이그레이션·.corrupt 백업·0.5s 트레일링 디바운스)은
/// JSONDocumentPersistence 공용 엔진이 담당한다.
/// 모델(StickyNote)은 비스레드세이프 참조 타입 — 모든 접근은 메인 액터로 강제한다.
/// 프로퍼티 직접 수정(텍스트·frame·색·핀) 뒤에는 notifyChanged()를 호출해 영속화를 트리거한다.
/// (add/archive/reopen/delete는 내부에서 알아서 저장한다.)
@MainActor
@Observable
final class StickyStore {
    private(set) var notes: [StickyNote] = []

    /// 영속화 공용 엔진 — 디바운스·버전 잠금·.corrupt 백업 위임.
    @ObservationIgnored private let persistence: JSONDocumentPersistence<Document>

    /// 디스크 문서가 이 빌드보다 새 버전이면 true — 덮어쓰기(데이터 소실) 방지용 저장 거부.
    var saveBlocked: Bool { persistence.saveBlocked }

    /// 문서 포맷 버전. 하위 호환이 깨지는 변경 시 +1 하고 init에 마이그레이션을 추가할 것
    /// (decodeIfPresent로 흡수되는 키 추가는 예외 — TaskStore와 동일 규약).
    static let documentVersion = 1

    private struct Document: Codable {
        var version: Int
        var notes: [StickyNote]
    }

    /// ~/Library/Application Support/AnhamDie/stickies.json — 위젯이 볼 필요가 없는 데이터라
    /// App Group 공유 경로가 아닌 기본 경로 고정.
    static func makeDefault() -> StickyStore {
        StickyStore(directory: JSONTaskStore.defaultDirectory())
    }

    init(directory: URL) {
        persistence = JSONDocumentPersistence(
            directory: directory, fileName: "stickies.json", supportedVersion: Self.documentVersion
        )
        if let document = persistence.load() {
            notes = document.notes
            // v1이 최초 포맷 — documentVersion 상승 시 document.version < N 마이그레이션을 여기 추가.
        }
    }

    // MARK: - 조회

    /// 열린 노트 (archivedAt == nil), 생성순 — 카드 창 복원·계단식 배치 기준 순서.
    var openNotes: [StickyNote] {
        notes.filter(\.isOpen).sorted { $0.createdAt < $1.createdAt }
    }

    /// 보관된 노트, 보관 시각 내림차순 — 보관함 뷰의 '닫은 날짜별 그룹' 원천 (§19.2).
    var archivedNotes: [StickyNote] {
        notes.filter { !$0.isOpen }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    func note(withID id: UUID) -> StickyNote? {
        notes.first { $0.id == id }
    }

    // MARK: - 변경 API

    func add(_ note: StickyNote) {
        notes.append(note)
        notifyChanged()
    }

    /// 닫기 = 보관 (§19.2) — 삭제가 아니다.
    func archive(_ note: StickyNote, at date: Date = Date()) {
        note.markArchived(at: date)
        notifyChanged()
    }

    /// 보관함에서 다시 열기 — 보관 전 frame·색·핀 상태는 그대로 유지된다.
    func reopen(_ note: StickyNote) {
        note.markReopened()
        notifyChanged()
    }

    /// 완전 삭제 (보관함의 명시 액션 전용 경로).
    func delete(_ note: StickyNote) {
        notes.removeAll { $0.id == note.id }
        notifyChanged()
    }

    /// 모델 프로퍼티를 직접 수정(텍스트 편집·드래그 종료 frame 갱신·색/핀 토글)한 뒤 호출.
    /// 트레일링 디바운스로 마지막 변경 0.5s 뒤 1회만 저장된다.
    func notifyChanged() {
        persistence.scheduleSave { [weak self] in self?.currentDocument() }
    }

    /// 즉시 디스크에 플러시 (앱 종료 시 등).
    func saveNow() {
        persistence.saveNow(currentDocument())
    }

    private func currentDocument() -> Document {
        Document(version: Self.documentVersion, notes: notes)
    }
}
