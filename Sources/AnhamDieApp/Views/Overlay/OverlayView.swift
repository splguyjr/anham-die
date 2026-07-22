import AppKit
import SwiftUI

/// 오버레이 카드 레이아웃 상수. 컨트롤러의 높이 추정(estimatedSize)과 뷰가 공유한다.
enum OverlayMetrics {
    static let width: CGFloat = 260
    static let corner: CGFloat = 16
    static let hPadding: CGFloat = 14
    static let vPadding: CGFloat = 12
    static let rowSpacing: CGFloat = 8
    static let rowHeight: CGFloat = 24
    static let headerHeight: CGFloat = 22
    static let footerHeight: CGFloat = 18
    static let moreHeight: CGFloat = 16
    // SwiftUI Divider의 실측 프레임 높이(헤어라인). 높이 추정에만 쓰인다.
    static let dividerHeight: CGFloat = 1
}

/// acceptsFirstMouse를 열어, 앱이 비활성 상태여도 체크박스 첫 클릭이 바로 먹히게 한다.
/// (nonactivating 패널이라 클릭해도 현재 앱 포커스는 뺏지 않는다.)
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 패널을 꽉 채우되 카드를 좌상단에 고정해, 높이 보정 전 잠깐의 크기 차이에도 카드가 튀지 않게 한다.
struct OverlayRootView: View {
    let onResize: (CGSize) -> Void

    var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                OverlayCardView(onResize: onResize)
            }
    }
}

/// 컴팩트 플로팅 오버레이 카드 (PLAN §3.2).
/// 헤더(색 점 + "오늘 할 일" + 진행률) · 오늘 task 최대 overlayMaxCount개 + "+N개" · 이월 배지.
struct OverlayCardView: View {
    let onResize: (CGSize) -> Void

    var body: some View {
        // MenuBarContentView와 동일하게 body 안에서 관찰 대상 프로퍼티를 읽어 SwiftUI 관찰을 성립시킨다.
        let context = AppContext.shared
        let settings = context.settings
        // 관찰 지점: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 열려 있는 오버레이가 재평가된다.
        _ = settings.currentLogicalDay
        let base = context.store.todayTasks(boundary: context.dayBoundary)
        let ordered = base.filter { !$0.isCompleted } + base.filter { $0.isCompleted }
        let total = base.count
        let completed = base.filter { $0.isCompleted }.count
        let maxCount = max(1, settings.overlayMaxCount)
        let shown = Array(ordered.prefix(maxCount))
        let moreCount = total - shown.count
        let rolloverCount = base.filter { $0.rolloverCount > 0 }.count

        return VStack(alignment: .leading, spacing: OverlayMetrics.rowSpacing) {
            header(total: total, completed: completed)
            Divider().opacity(0.5)
            if base.isEmpty {
                Text("오늘 할 일이 없어요")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(height: OverlayMetrics.rowHeight, alignment: .leading)
            } else {
                ForEach(shown) { task in
                    row(task)
                }
                if moreCount > 0 {
                    Text("+\(moreCount)개")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: OverlayMetrics.moreHeight, alignment: .leading)
                        .padding(.leading, 25)
                }
            }
            if rolloverCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                    Text("이월됨 \(rolloverCount)개")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.orange)
                .frame(height: OverlayMetrics.footerHeight, alignment: .leading)
            }
        }
        .padding(.horizontal, OverlayMetrics.hPadding)
        .padding(.vertical, OverlayMetrics.vPadding)
        .frame(width: OverlayMetrics.width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OverlayMetrics.corner, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(settings.overlayOpacity)
        )
        .clipShape(RoundedRectangle(cornerRadius: OverlayMetrics.corner, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onResize)
    }

    // MARK: - 하위 뷰

    // 헤더 클릭은 클릭 동작 설정과 무관하게 '항상' 메인 창을 연다 (PLAN §10.3).
    private func header(total: Int, completed: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 8, height: 8)
            Text("오늘 할 일")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            Text("\(completed)/\(total)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(height: OverlayMetrics.headerHeight)
        .contentShape(Rectangle())
        .onTapGesture { MainWindowOpener.openMain() }
        .help("메인 창 열기")
    }

    private func row(_ task: TodoTask) -> some View {
        HStack(spacing: 8) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(task.isCompleted ? AppTheme.accent : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 12))
                .strikethrough(task.isCompleted, color: .secondary)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if task.rolloverCount > 0 {
                rolloverBadge(task.rolloverCount)
            }
            if task.priority == .high {
                Circle()
                    .fill(AppTheme.priorityColor(.high))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(height: OverlayMetrics.rowHeight)
    }

    private func rolloverBadge(_ count: Int) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 8, weight: .bold))
            Text("\(count)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.orange.opacity(0.15)))
    }

    // 체크박스 클릭 동작은 설정(PLAN §3.4 "클릭 동작")을 따른다.
    // 즉시 완료 체크일 때 포커스는 nonactivating 패널이 지켜준다.
    private func toggle(_ task: TodoTask) {
        switch AppContext.shared.settings.overlayClickAction {
        case .completeImmediately:
            if task.isCompleted {
                task.reactivate()
            } else {
                task.markCompleted()
            }
            AppContext.shared.store.notifyChanged()
        case .openApp:
            // 메인 창 열기의 단일 경로 (activate + 기존 창 포커스/openWindow 재시도).
            MainWindowOpener.openMain()
        case .ignore:
            break
        }
    }
}
