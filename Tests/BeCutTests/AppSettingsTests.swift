import Testing
@testable import BeCut

@Suite("App settings")
struct AppSettingsTests {
    @Test func defaultsMatchProductPreferences() {
        let settings = AppSettings()

        #expect(settings.appearance == .dark)
        #expect(settings.language == .english)
        #expect(settings.playSoundWhenFinished == true)
        #expect(settings.preferHardwareAcceleration == true)
        #expect(settings.parallelFastExports == true)
    }

    @Test func appearanceLabelsFollowSelectedLanguage() {
        #expect(AppAppearanceMode.automatic.displayName(for: .english) == "Automatic")
        #expect(AppAppearanceMode.automatic.displayName(for: .simplifiedChinese) == "自动")
        #expect(AppAppearanceMode.dark.displayName(for: .simplifiedChinese) == "深色")
    }

    @Test func settingsPanesCoverDesignSections() {
        #expect(SettingsPane.allCases.map(\.rawValue) == ["general", "engine", "notifications", "about"])
    }

    @Test func metadataIncludesVersionAndSupportLinks() {
        #expect(!BeCutAppMetadata.versionLabel.isEmpty)
        #expect(!BeCutAppMetadata.versionLabel.contains("(version)"))
        #expect(BeCutAppMetadata.websiteURL.absoluteString.hasPrefix("https://"))
        #expect(BeCutAppMetadata.supportURL.scheme == "mailto")
    }
}
