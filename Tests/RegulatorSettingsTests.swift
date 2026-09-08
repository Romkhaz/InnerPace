import XCTest

final class RegulatorSettingsTests: XCTestCase {
    func testDecodesPartialSettingsWithDefaults() throws {
        let json = #"{"cadenceMin":170,"cadenceMax":190,"heartRateMin":120,"heartRateMax":140}"#
        let settings = try JSONDecoder().decode(RegulatorSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.cadenceMin, 170)
        XCTAssertEqual(settings.heartRateMax, 140)
        XCTAssertEqual(settings.maxStep, RegulatorSettings.default.maxStep)
    }

    func testIgnoresUnknownKeys() throws {
        let json = #"{"heartRateSource":"watch","cadenceMin":175}"#
        let settings = try JSONDecoder().decode(RegulatorSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.cadenceMin, 175)
    }

    func testLegacyHoldBandMigratesToNewDefault() throws {
        let legacy = #"{"cadenceMin":175,"holdBand":3}"#
        let migrated = try JSONDecoder().decode(RegulatorSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(migrated.holdBand, RegulatorSettings.default.holdBand, "старая полоса 3 без версии приводится к новой")
        XCTAssertEqual(migrated.schemaVersion, RegulatorSettings.currentSchemaVersion)

        let deliberate = #"{"cadenceMin":175,"holdBand":3,"schemaVersion":2}"#
        let kept = try JSONDecoder().decode(RegulatorSettings.self, from: Data(deliberate.utf8))
        XCTAssertEqual(kept.holdBand, 3, "выставленное вручную после миграции не трогаем")

        let other = #"{"cadenceMin":175,"holdBand":5}"#
        XCTAssertEqual(try JSONDecoder().decode(RegulatorSettings.self, from: Data(other.utf8)).holdBand, 5)
    }

    func testLegacyVoiceRepeatMigratesToMinute() throws {
        let legacy = #"{"voiceRepeatSeconds":0,"schemaVersion":2}"#
        XCTAssertEqual(try JSONDecoder().decode(RegulatorSettings.self, from: Data(legacy.utf8)).voiceRepeatSeconds, 60)
        let deliberate = #"{"voiceRepeatSeconds":0,"schemaVersion":3}"#
        XCTAssertEqual(try JSONDecoder().decode(RegulatorSettings.self, from: Data(deliberate.utf8)).voiceRepeatSeconds, 0)
        var s = RegulatorSettings.default
        XCTAssertNil(s.isTargetSuspiciouslyLow ? "low" : nil)
        s.heartRateMax = 95
        XCTAssertTrue(s.isTargetSuspiciouslyLow)
        s.heartRateMax = 195
        XCTAssertTrue(s.isTargetSuspiciouslyHigh)
    }

    func testRoundTrip() throws {
        var settings = RegulatorSettings.default
        settings.halfTimeClick = true
        settings.clickVolume = 0.5
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(RegulatorSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}
