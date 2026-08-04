import CoreGraphics
import Foundation
import Observation

// v10 포스트잇 (PLAN §19). TodoTask와 같은 규약 — CLT 툴체인 제약(§8)으로 @Observable
// + 수동 Codable, 영속화는 StickyStore가 담당한다.

/// 클래식 포스트잇 색 5종 (§19.1). 데이터 정체성이므로 테마(모노 무채 규칙 포함)와 무관하게
/// 유지된다 — 실제 색값·잉크색은 StickyColorID+Palette(Views/Stickies) 확장이 정의한다.
enum StickyColorID: String, Codable, CaseIterable, Sendable {
    case yellow
    case pink
    case mint
    case blue
    case lavender

    var displayName: String {
        switch self {
        case .yellow: return "노랑"
        case .pink: return "핑크"
        case .mint: return "민트"
        case .blue: return "블루"
        case .lavender: return "라벤더"
        }
    }
}

@Observable
final class StickyNote: Identifiable, Codable {
    /// 새 노트 기본 카드 크기 — 생성 위치는 StickyNotesController가 커서/기존 노트 기준으로 정한다.
    static let defaultSize = CGSize(width: 250, height: 230)

    var id: UUID
    var text: String
    var colorID: StickyColorID
    /// 카드 창 프레임(AppKit 화면 좌표). 갱신·저장은 드래그/리사이즈 종료 시 1회(§19.4 에너지 규약).
    var frame: CGRect
    /// true면 그 노트만 항상 위(floating + 전체화면 위 포함). 기본은 일반 창 레벨 (§19.1).
    var pinned: Bool
    var createdAt: Date
    /// nil = 열림. 값 있으면 보관됨 — 닫기는 삭제가 아니라 보관 (§19.2).
    var archivedAt: Date?

    var isOpen: Bool { archivedAt == nil }

    init(
        id: UUID = UUID(),
        text: String = "",
        colorID: StickyColorID = .yellow,
        frame: CGRect = CGRect(origin: .zero, size: StickyNote.defaultSize),
        pinned: Bool = false,
        createdAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.colorID = colorID
        self.frame = frame
        self.pinned = pinned
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    func markArchived(at date: Date = Date()) {
        archivedAt = date
    }

    func markReopened() {
        archivedAt = nil
    }

    // MARK: - Codable

    /// frame은 명시 키 {x,y,width,height}로 인코딩 — 플랫폼 CGRect Codable(중첩 배열) 포맷에
    /// 문서 호환성을 묶지 않는다.
    private struct FrameBox: Codable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        init(_ rect: CGRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }

        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, colorID, frame, pinned, createdAt, archivedAt
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // colorID는 관대하게 — 미래 버전이 색을 추가해도 구버전 실행이 로드 실패로 데이터를 잃지 않게
        // 미상 값은 기본색으로 흡수한다.
        let rawColor = try c.decodeIfPresent(String.self, forKey: .colorID)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
            colorID: rawColor.flatMap { StickyColorID(rawValue: $0) } ?? .yellow,
            frame: (try c.decodeIfPresent(FrameBox.self, forKey: .frame))?.rect
                ?? CGRect(origin: .zero, size: StickyNote.defaultSize),
            pinned: try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false,
            createdAt: try c.decode(Date.self, forKey: .createdAt),
            archivedAt: try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(colorID, forKey: .colorID)
        try c.encode(FrameBox(frame), forKey: .frame)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(archivedAt, forKey: .archivedAt)
    }
}
