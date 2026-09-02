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

    func testRoundTrip() throws {
        var settings = RegulatorSettings.default
        settings.halfTimeClick = true
        settings.clickVolume = 0.5
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(RegulatorSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}
