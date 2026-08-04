import Foundation
import SwiftUI
import Testing
@testable import AnhamDieApp

// v10 포스트잇 (PLAN §19.4) — StickyNote JSON 왕복·문서 보호(버전 잠금/.corrupt 백업)·
// 보관/재열기 상태 전이·색 대비(WCAG) 잠금.

@MainActor
private func makeTempStickyStore() -> (store: StickyStore, dir: URL) {
    let dir = makeTempStoreDirectory()
    return (StickyStore(directory: dir), dir)
}

@MainActor
@Suite("StickyNote JSON 왕복")
struct StickyNoteRoundTripTests {
    @Test("모든 필드가 저장/재로드 왕복된다 (frame·pinned·archivedAt 포함)")
    func fullRoundTrip() throws {
        let (store, dir) = makeTempStickyStore()
        let note = StickyNote(
            text: "장보기 목록\n- 우유",
            colorID: .mint,
            frame: CGRect(x: 120.5, y: 80.25, width: 300, height: 260),
            pinned: true,
            createdAt: date(2026, 8, 4, 10, 0)
        )
        store.add(note)
        let archived = StickyNote(text: "끝난 메모", colorID: .lavender)
        archived.markArchived(at: date(2026, 8, 4, 12, 0))
        store.add(archived)
        store.saveNow()

        let reloaded = StickyStore(directory: dir)
        #expect(reloaded.notes.count == 2)
        let restored = try #require(reloaded.note(withID: note.id))
        #expect(restored.text == "장보기 목록\n- 우유")
        #expect(restored.colorID == .mint)
        #expect(restored.frame == CGRect(x: 120.5, y: 80.25, width: 300, height: 260))
        #expect(restored.pinned)
        #expect(restored.isOpen)
        let restoredArchived = try #require(reloaded.note(withID: archived.id))
        #expect(!restoredArchived.isOpen)
        #expect(restoredArchived.archivedAt != nil)
    }

    @Test("v1 수기 문서 로드 — 선택 키 누락은 기본값으로, 미상 colorID는 기본색으로 흡수")
    func handwrittenV1DocumentLoads() throws {
        let dir = makeTempStoreDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("stickies.json")
        // frame/pinned/text/archivedAt 키 없음 + 미래 버전이 추가했을 법한 미상 색 이름.
        let v1Content = """
        {
          "version" : 1,
          "notes" : [
            {
              "colorID" : "pink",
              "createdAt" : "2026-08-04T01:00:00Z",
              "frame" : { "height" : 200, "width" : 240, "x" : 40, "y" : 60 },
              "id" : "AAAAAAAA-0000-0000-0000-000000000001",
              "pinned" : true,
              "text" : "메모"
            },
            {
              "colorID" : "neon",
              "createdAt" : "2026-08-04T02:00:00Z",
              "id" : "AAAAAAAA-0000-0000-0000-000000000002"
            }
          ]
        }
        """
        try v1Content.write(to: file, atomically: true, encoding: .utf8)

        let store = StickyStore(directory: dir)
        #expect(!store.saveBlocked)
        #expect(store.notes.count == 2)

        let full = try #require(store.note(
            withID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!))
        #expect(full.text == "메모")
        #expect(full.colorID == .pink)
        #expect(full.frame == CGRect(x: 40, y: 60, width: 240, height: 200))
        #expect(full.pinned)

        let minimal = try #require(store.note(
            withID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!))
        #expect(minimal.text.isEmpty)
        #expect(minimal.colorID == .yellow) // 미상 색은 기본색 폴백 — 로드 실패로 데이터를 잃지 않는다
        #expect(minimal.frame.size == StickyNote.defaultSize)
        #expect(!minimal.pinned)
        #expect(minimal.isOpen)
    }
}

@MainActor
@Suite("StickyStore 문서 보호 (버전·손상)")
struct StickyStoreProtectionTests {
    @Test("디스크 문서 버전이 더 높으면 읽기/쓰기를 거부한다")
    func newerVersionBlocksSave() throws {
        let dir = makeTempStoreDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("stickies.json")
        let newerContent = #"{"version":999,"notes":[]}"#
        try newerContent.write(to: file, atomically: true, encoding: .utf8)

        let store = StickyStore(directory: dir)
        #expect(store.saveBlocked)
        store.add(StickyNote(text: "저장되면 안 됨"))
        store.saveNow()

        let onDisk = try String(contentsOf: file, encoding: .utf8)
        #expect(onDisk == newerContent)
    }

    @Test("디코드 실패 시 원본을 stickies.json.corrupt-* 백업으로 보존한다")
    func corruptFileIsBackedUp() throws {
        let dir = makeTempStoreDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("stickies.json")
        let corruptContent = #"{"version":1,"notes":[{"createdAt":123}]}"#
        try corruptContent.write(to: file, atomically: true, encoding: .utf8)

        let store = StickyStore(directory: dir)
        #expect(store.notes.isEmpty)

        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("stickies.json.corrupt-") }
        #expect(backups.count == 1)
        let backupContent = try String(
            contentsOf: dir.appendingPathComponent(backups[0]), encoding: .utf8)
        #expect(backupContent == corruptContent)

        // 이후 저장이 백업을 건드리지 않는다
        store.add(StickyNote(text: "새 메모"))
        store.saveNow()
        let backupsAfter = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("stickies.json.corrupt-") }
        #expect(backupsAfter == backups)
    }

    @Test("투두 store.json과 같은 디렉터리에서 서로를 건드리지 않는다 (§19.4 분리)")
    func coexistsWithTaskStore() throws {
        let dir = makeTempStoreDirectory()
        let taskStore = JSONTaskStore(directory: dir)
        taskStore.addTask(TodoTask(title: "할 일"))
        taskStore.saveNow()

        let stickyStore = StickyStore(directory: dir)
        stickyStore.add(StickyNote(text: "메모"))
        stickyStore.saveNow()

        let reloadedTasks = JSONTaskStore(directory: dir)
        #expect(reloadedTasks.tasks.count == 1)
        let reloadedStickies = StickyStore(directory: dir)
        #expect(reloadedStickies.notes.count == 1)
    }
}

@MainActor
@Suite("포스트잇 보관/재열기 상태 전이")
struct StickyArchiveTransitionTests {
    @Test("추가 → 열림 목록, 보관 → 보관 목록 (archivedAt 기록)")
    func archiveTransition() {
        let (store, _) = makeTempStickyStore()
        let note = StickyNote(text: "메모")
        store.add(note)
        #expect(store.openNotes.map(\.id) == [note.id])
        #expect(store.archivedNotes.isEmpty)

        store.archive(note, at: date(2026, 8, 4, 15, 0))
        #expect(store.openNotes.isEmpty)
        #expect(store.archivedNotes.map(\.id) == [note.id])
        #expect(note.archivedAt == date(2026, 8, 4, 15, 0))
    }

    @Test("다시 열기 — archivedAt 해제, frame·색·핀은 보관 전 그대로")
    func reopenTransition() {
        let (store, _) = makeTempStickyStore()
        let note = StickyNote(
            text: "메모", colorID: .blue,
            frame: CGRect(x: 10, y: 20, width: 260, height: 240), pinned: true
        )
        store.add(note)
        store.archive(note)
        store.reopen(note)

        #expect(note.isOpen)
        #expect(note.archivedAt == nil)
        #expect(store.openNotes.map(\.id) == [note.id])
        #expect(note.colorID == .blue)
        #expect(note.frame == CGRect(x: 10, y: 20, width: 260, height: 240))
        #expect(note.pinned)
    }

    @Test("완전 삭제는 보관과 달리 노트를 제거한다")
    func deleteRemoves() {
        let (store, _) = makeTempStickyStore()
        let note = StickyNote(text: "지울 메모")
        store.add(note)
        store.delete(note)
        #expect(store.notes.isEmpty)
    }

    @Test("정렬 — 열림은 생성순, 보관은 보관 시각 내림차순 (닫은 날짜별 그룹 원천)")
    func ordering() {
        let (store, _) = makeTempStickyStore()
        let a = StickyNote(text: "A", createdAt: date(2026, 8, 1, 9, 0))
        let b = StickyNote(text: "B", createdAt: date(2026, 8, 2, 9, 0))
        let c = StickyNote(text: "C", createdAt: date(2026, 8, 3, 9, 0))
        store.add(b)
        store.add(a)
        store.add(c)
        #expect(store.openNotes.map(\.text) == ["A", "B", "C"])

        store.archive(a, at: date(2026, 8, 4, 10, 0))
        store.archive(c, at: date(2026, 8, 4, 11, 0))
        #expect(store.archivedNotes.map(\.text) == ["C", "A"])
        #expect(store.openNotes.map(\.text) == ["B"])
    }
}

@Suite("포스트잇 색 대비 잠금 (WCAG)")
struct StickyPaletteContrastTests {
    @Test("5색 전부 — 잉크/카드 배경 7.0:1+ (AAA, 본문 텍스트 기준)")
    func inkOnFillContrast() {
        for color in StickyColorID.allCases {
            #expect(WCAG.ratio(color.ink, color.fill) >= 7.0, "\(color.rawValue) 잉크/배경")
        }
    }

    @Test("상단 바(잉크 10% 블렌드) 위에서도 잉크 7.0:1+ 유지")
    func inkOnBarContrast() {
        for color in StickyColorID.allCases {
            let ink = WCAG.srgb(color.ink)
            let bar = WCAG.blend(ink, 0.10, over: WCAG.srgb(color.fill))
            #expect(WCAG.ratio(ink, bar) >= 7.0, "\(color.rawValue) 잉크/상단바")
        }
    }

    @Test("5색 배경이 서로 구분된다 (중복 색값 금지)")
    func fillsAreDistinct() {
        let hexes = StickyColorID.allCases.map { ColorHex.hex($0.fill) }
        #expect(Set(hexes).count == StickyColorID.allCases.count)
    }
}
