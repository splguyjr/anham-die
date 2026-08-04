import Foundation
import SwiftUI
@testable import AnhamDieApp

/// Testing.Tag와 모델 Tag의 이름 충돌 회피용 별칭 (모듈명 AnhamDieApp도 @main 타입에 가려 한정 불가).
typealias TaskTag = Tag

func makeTestSettings(boundaryHour: Int = 9, boundaryMinute: Int = 0) -> AppSettings {
    let suite = "AnhamDieTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let settings = AppSettings(defaults: defaults)
    settings.dayBoundaryHour = boundaryHour
    settings.dayBoundaryMinute = boundaryMinute
    return settings
}

func makeTempStoreDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AnhamDieTests-\(UUID().uuidString)", isDirectory: true)
}

@MainActor
func makeTempStore() -> JSONTaskStore {
    JSONTaskStore(directory: makeTempStoreDirectory())
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}

func midnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.startOfDay(for: date(year, month, day, 12))
}

// MARK: - WCAG 상대휘도 대비 헬퍼 (ThemeContrastTests·StickyStoreTests 공용)

struct SRGBValue {
    let r, g, b: Double
}

enum WCAG {
    static func srgb(_ color: Color) -> SRGBValue {
        let hex = ColorHex.hex(color)
        let value = UInt64(hex.dropFirst(), radix: 16)!
        return SRGBValue(
            r: Double((value & 0xFF0000) >> 16) / 255,
            g: Double((value & 0x00FF00) >> 8) / 255,
            b: Double(value & 0x0000FF) / 255
        )
    }

    static func luminance(_ c: SRGBValue) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    static func ratio(_ a: SRGBValue, _ b: SRGBValue) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func ratio(_ a: Color, _ b: Color) -> Double {
        ratio(srgb(a), srgb(b))
    }

    static func blend(_ fg: SRGBValue, _ alpha: Double, over bg: SRGBValue) -> SRGBValue {
        SRGBValue(
            r: fg.r * alpha + bg.r * (1 - alpha),
            g: fg.g * alpha + bg.g * (1 - alpha),
            b: fg.b * alpha + bg.b * (1 - alpha)
        )
    }
}
