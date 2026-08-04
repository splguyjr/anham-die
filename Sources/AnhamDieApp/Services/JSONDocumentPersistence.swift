import Foundation

/// JSON 문서 영속화 공용 엔진 (v10 §19.4 — TaskStore 선례를 복제하지 않고 공용화).
/// JSONTaskStore(store.json)·StickyStore(stickies.json)가 같은 저장 규약을 공유한다:
/// - 0.5s 트레일링 디바운스(scheduleSave) + 즉시 플러시(saveNow)
/// - 버전 프로브: 디스크 문서가 지원 버전보다 새로우면 읽기/쓰기 잠금(saveBlocked)
///   — 구버전 실행이 새 포맷을 덮어써 데이터를 잃는 것을 막는다
/// - 디코드 실패 시 원본을 <파일명>.corrupt-<timestamp>로 백업한 뒤 빈 상태로 시작
///   (백업 실패 시에도 원본을 덮어쓰지 않도록 저장 잠금)
/// - mtime 추적: 외부 프로세스 변경 재읽기(decodeIfChangedOnDisk)의 no-op 알림 스킵
/// 인코딩 규약: iso8601 날짜 · prettyPrinted+sortedKeys · atomic 쓰기.
/// Document 타입은 반드시 최상위에 version(Int) 키를 포함해야 버전 프로브가 동작한다.
@MainActor
final class JSONDocumentPersistence<Document: Codable> {
    private let fileURL: URL
    private let supportedVersion: Int
    /// 예약된 디바운스 저장 작업 — saveNow()/재예약 시 취소해 유효 간격을 0.5s로 유지한다.
    private var saveWorkItem: DispatchWorkItem?
    /// 마지막으로 디스크에서 읽거나 디스크에 쓴 파일의 수정 시각 — no-op 재읽기 스킵 근거.
    private var lastKnownModificationDate: Date?
    /// 디스크의 문서가 지원 버전보다 새 버전이면 true — 덮어쓰기(데이터 소실) 방지용 저장 거부.
    private(set) var saveBlocked = false
    /// saveNow 성공 직후 호출 (위젯 타임라인 리로드 등)
    var onDidSave: (() -> Void)?

    private struct VersionProbe: Codable {
        var version: Int
    }

    init(directory: URL, fileName: String, supportedVersion: Int) {
        self.fileURL = directory.appendingPathComponent(fileName)
        self.supportedVersion = supportedVersion
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 시작 시 1회 로드. 파일 없음/버전 초과/디코드 실패 시 nil — 실패 원본은 .corrupt로 보존된다.
    func load() -> Document? {
        guard let document = decodeDocument(preserveOnFailure: true) else { return nil }
        lastKnownModificationDate = fileModificationDate()
        return document
    }

    /// 연속 변경마다 재예약(취소 후 재설치) — 트레일링 디바운스로 마지막 변경 0.5s 뒤 1회만 저장한다.
    /// makeDocument가 nil을 반환하면(소유 스토어 해제 등) 저장을 생략한다.
    func scheduleSave(_ makeDocument: @escaping () -> Document?) {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWorkItem = nil
            if let document = makeDocument() {
                self.saveNow(document)
            }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// 즉시 디스크에 플러시 (앱 종료 시 등). 예약된 디바운스 저장은 취소해 중복 발화를 막는다.
    func saveNow(_ document: Document) {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard !saveBlocked else {
            NSLog("AnhamDie: 저장 거부 — 디스크 문서 버전이 지원 버전(v\(supportedVersion))보다 높음 [\(fileURL.lastPathComponent)]")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
            lastKnownModificationDate = fileModificationDate()
            onDidSave?()
        } catch {
            NSLog("AnhamDie: 저장 실패 [\(fileURL.lastPathComponent)] — \(error)")
        }
    }

    /// 외부 프로세스 변경 후 재읽기. 마지막으로 읽거나 쓴 이후 mtime이 그대로면(no-op 알림)
    /// 전체 JSON 디코드조차 하지 않고 nil을 돌려준다.
    func decodeIfChangedOnDisk() -> Document? {
        let currentMtime = fileModificationDate()
        if let currentMtime, currentMtime == lastKnownModificationDate { return nil }
        guard let document = decodeDocument(preserveOnFailure: false) else { return nil }
        lastKnownModificationDate = currentMtime
        return document
    }

    /// 파일의 현재 수정 시각. 파일이 없거나 stat 실패 시 nil.
    private func fileModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
    }

    private func decodeDocument(preserveOnFailure: Bool) -> Document? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let probe = try? decoder.decode(VersionProbe.self, from: data),
           probe.version > supportedVersion {
            NSLog("AnhamDie: 디스크 문서 v\(probe.version) > 지원 v\(supportedVersion) — 읽기/쓰기 중단 [\(fileURL.lastPathComponent)]")
            saveBlocked = true
            return nil
        }
        do {
            return try decoder.decode(Document.self, from: data)
        } catch {
            NSLog("AnhamDie: 로드 실패 [\(fileURL.lastPathComponent)] — \(error)")
            if preserveOnFailure {
                backupCorruptFile()
            }
            return nil
        }
    }

    private func backupCorruptFile() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(stamp)")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backup)
            NSLog("AnhamDie: 손상된 저장소를 백업함 — \(backup.path)")
        } catch {
            // 백업 실패 시 기존 파일을 덮어쓰지 않도록 저장을 잠근다.
            NSLog("AnhamDie: 손상 저장소 백업 실패 — 저장 잠금. \(error)")
            saveBlocked = true
        }
    }
}
