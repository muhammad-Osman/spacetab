import XCTest

/// Every language has the same keys as English, with the same placeholders.
final class LocalizationTests: XCTestCase {
    private var localizationDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localization")
    }

    private func strings(_ language: String) throws -> [String: String] {
        let url = localizationDirectory.appendingPathComponent("\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String], "\(language) is not a strings file")
    }

    private func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(\\d\\$)?(lld|@|d)")
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
            .sorted()
    }

    func testEveryLanguageHasEveryEnglishKeyAndNoOthers() throws {
        let english = try strings("en")
        XCTAssertGreaterThan(english.count, 80)
        for key in english.keys {
            XCTAssertEqual(english[key], key, "English maps each key to itself: \(key)")
        }

        let languages = try FileManager.default.contentsOfDirectory(atPath: localizationDirectory.path)
            .filter { $0.hasSuffix(".lproj") }
            .map { $0.replacingOccurrences(of: ".lproj", with: "") }
        XCTAssertGreaterThanOrEqual(languages.count, 5)

        for language in languages where language != "en" {
            let translated = try strings(language)
            let missing = Set(english.keys).subtracting(translated.keys)
            let extra = Set(translated.keys).subtracting(english.keys)
            XCTAssertTrue(missing.isEmpty, "\(language) is missing: \(missing.sorted())")
            XCTAssertTrue(extra.isEmpty, "\(language) has unknown keys: \(extra.sorted())")
            for (key, value) in translated {
                XCTAssertFalse(value.isEmpty, "\(language): empty translation for \(key)")
                XCTAssertEqual(placeholders(value), placeholders(key), "\(language): placeholders differ for \(key)")
            }
        }
    }
}
