import XCTest
@testable import SpaceTab

@MainActor
final class SettingsTransferTests: XCTestCase {
    private let suite = "SpaceTabTests.transfer"

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    func testSettingsSurviveExportAndImport() throws {
        let source = freshDefaults()
        source.set("thumbnails", forKey: AppSettings.Key.style)
        source.set(0.4, forKey: AppSettings.Key.opacity)
        source.set(true, forKey: AppSettings.Key.groupByApp)
        source.set("com.apple.Music", forKey: AppSettings.Key.excludedApps)
        let shortcuts = [Shortcut(keyCode: 50, modifiers: .command, scope: .currentApp)]
        ShortcutSettings.save(shortcuts, to: source)

        let data = try SettingsTransfer.export(from: source)

        let target = freshDefaults()
        target.set("light", forKey: AppSettings.Key.theme) // not in the file: reset to default
        try SettingsTransfer.import(data, into: target)

        XCTAssertEqual(target.string(forKey: AppSettings.Key.style), "thumbnails")
        XCTAssertEqual(target.double(forKey: AppSettings.Key.opacity), 0.4)
        XCTAssertEqual(target.bool(forKey: AppSettings.Key.groupByApp), true)
        XCTAssertEqual(target.string(forKey: AppSettings.Key.excludedApps), "com.apple.Music")
        XCTAssertNil(target.object(forKey: AppSettings.Key.theme))
        XCTAssertEqual(ShortcutSettings.load(from: target), shortcuts)
    }

    func testOtherFilesAreRejected() {
        let target = freshDefaults()
        let notSettings = Data("{\"style\": \"titles\"}".utf8)
        XCTAssertThrowsError(try SettingsTransfer.import(notSettings, into: target))
        XCTAssertNil(target.object(forKey: AppSettings.Key.style))
    }
}
