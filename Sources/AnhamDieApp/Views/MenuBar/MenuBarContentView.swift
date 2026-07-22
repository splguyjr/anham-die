import SwiftUI

// 플레이스홀더 — menubar 모듈이 오늘 요약 팝오버로 구현 (PLAN §3.4)
struct MenuBarContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AnhamDie — 메뉴바 팝오버 구현 예정")
            Divider()
            Button("종료") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
