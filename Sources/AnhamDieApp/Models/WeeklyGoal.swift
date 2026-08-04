import Foundation
import Observation

// 주간 목표 (v11 §20.1). Models.swift와 같은 폴백 규약:
// @Observable + 수동 Codable (CLT 툴체인에 SwiftDataMacros 없음, PLAN §8).

/// 주간 목표 상태 (§20.3).
/// - active: 진행 중 (지난 주 것이 active + 미달이면 브리핑 '지난주 리뷰' 이월 후보).
/// - carriedOver: 잔여량이 새 주 목표로 이월돼 기록만 남음.
/// - dropped: 종료(루틴이면 재생성 중단). 기록은 보존된다.
enum WeeklyGoalStatus: String, Codable, Sendable {
    case active
    case carriedOver
    case dropped
}

/// 주간 목표 (§20.1). targetCount 1 = 단일형 체크, 2+ = 횟수형.
/// weekKey는 소속 논리적 주의 시작 날짜 키(자정 정규화) — scheduledDate와 같은 규약으로
/// 쓰기는 DayBoundaryService.scheduledDateValue(for: weekStart), 읽기는 logicalDay(ofStored:).
@Observable
final class WeeklyGoal: Identifiable, Codable {
    var id: UUID
    var title: String
    /// 목표 횟수 (≥1 — init에서 클램프). UI 편집 경로도 1 미만을 넣지 말 것.
    var targetCount: Int
    /// 현재 진행 횟수. 0 미만 방지·초과 달성 허용은 TaskStore.increment/decrementGoalCount가 담당.
    var currentCount: Int
    /// 소속 논리적 주의 시작 날짜 키(자정 정규화)
    var weekKey: Date
    /// 루틴(매주 반복) 여부 — 새 주 시작 시 0/n 재생성 대상 (§20.3). 토글로 전환/해제 가능.
    var isRoutine: Bool
    var status: WeeklyGoalStatus
    var createdAt: Date
    /// 루틴 재생성 계보 식별자 (recurrenceSeriesID 선례) — 제목을 바꿔도 같은 루틴으로 이어진다.
    /// 첫 재생성 시 원본 goal.id로 채워지고 이후 주에 승계된다. nil = 아직 재생성된 적 없음.
    var routineSeriesID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        targetCount: Int = 1,
        currentCount: Int = 0,
        weekKey: Date,
        isRoutine: Bool = false,
        status: WeeklyGoalStatus = .active,
        createdAt: Date = Date(),
        routineSeriesID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.targetCount = max(1, targetCount)
        self.currentCount = max(0, currentCount)
        self.weekKey = weekKey
        self.isRoutine = isRoutine
        self.status = status
        self.createdAt = createdAt
        self.routineSeriesID = routineSeriesID
    }

    /// 완주 판정 — 초과 달성도 완주다
    var isAchieved: Bool { currentCount >= targetCount }
    /// 잔여 횟수 (이월 시 새 목표의 targetCount 후보). 완주면 0.
    var remainingCount: Int { max(0, targetCount - currentCount) }
    /// 진행 링/스트립용 진행률 0.0~1.0 (초과 달성은 1.0로 캡)
    var progress: Double { min(1.0, Double(currentCount) / Double(max(1, targetCount))) }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, targetCount, currentCount, weekKey, isRoutine, status, createdAt
        case routineSeriesID
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            title: try c.decode(String.self, forKey: .title),
            targetCount: try c.decodeIfPresent(Int.self, forKey: .targetCount) ?? 1,
            currentCount: try c.decodeIfPresent(Int.self, forKey: .currentCount) ?? 0,
            weekKey: try c.decode(Date.self, forKey: .weekKey),
            isRoutine: try c.decodeIfPresent(Bool.self, forKey: .isRoutine) ?? false,
            status: try c.decodeIfPresent(WeeklyGoalStatus.self, forKey: .status) ?? .active,
            createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            routineSeriesID: try c.decodeIfPresent(UUID.self, forKey: .routineSeriesID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(targetCount, forKey: .targetCount)
        try c.encode(currentCount, forKey: .currentCount)
        try c.encode(weekKey, forKey: .weekKey)
        try c.encode(isRoutine, forKey: .isRoutine)
        try c.encode(status, forKey: .status)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(routineSeriesID, forKey: .routineSeriesID)
    }
}
