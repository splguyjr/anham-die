import Foundation

/// 메모 미리보기 한 줄 추출 (PLAN §17). 리스트 행·브리핑 행이 공유하는 순수 문자열 헬퍼.
/// 메모의 첫 '내용 있는' 줄을 트리밍해 돌려준다 — 선행 빈 줄은 건너뛰고, 내용이 없으면 nil.
enum NotePreview {
    /// 개행으로 나눈 뒤 공백만이 아닌 첫 줄을 트리밍해 반환. 표시할 내용이 없으면 nil.
    static func firstLine(_ note: String) -> String? {
        for line in note.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
