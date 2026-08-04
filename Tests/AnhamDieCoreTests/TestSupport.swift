import Foundation
import SwiftUI
@testable import AnhamDieApp

/// Testing.Tag와 모델 Tag의 이름 충돌 회피용 별칭 (모듈명 AnhamDieApp도 @main 타입에 가려 한정 불가).
typealias TaskTag = Tag

func makeTestSettings(boundaryHour: Int = 9, boundaryMinute: Int = 0) -> AppSettings {
    // 영속 suite 대신 인메모리 백엔드 — ~/Library/Preferences에 plist를 남기지 않는다.
    let settings = AppSettings(defaults: InMemoryUserDefaults())
    settings.dayBoundaryHour = boundaryHour
    settings.dayBoundaryMinute = boundaryMinute
    return settings
}

/// AppSettings 전용 인메모리 UserDefaults — 디스크에 쓰지 않아 테스트 격리·정리가 불필요하다.
/// AppSettings가 실제로 호출하는 접근자만 오버라이드한다(타입별 setter는 set(_:forKey:)로 위임).
final class InMemoryUserDefaults: UserDefaults {
    private var store: [String: Any] = [:]
    private let lock = NSLock()

    override func object(forKey defaultName: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return store[defaultName]
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        store[defaultName] = value
    }
    override func set(_ value: Int, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ value: Double, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ value: Bool, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ value: Float, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func removeObject(forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        store[defaultName] = nil
    }
    override func string(forKey defaultName: String) -> String? { object(forKey: defaultName) as? String }
    override func stringArray(forKey defaultName: String) -> [String]? { object(forKey: defaultName) as? [String] }
    override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }
    override func removePersistentDomain(forName domainName: String) {
        lock.lock(); defer { lock.unlock() }
        store.removeAll()
    }
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
