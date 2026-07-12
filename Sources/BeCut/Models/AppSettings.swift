import Foundation

enum AppAppearanceMode: String, CaseIterable, Codable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    func displayName(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.automatic, .english): "Automatic"
        case (.light, .english): "Light"
        case (.dark, .english): "Dark"
        case (.automatic, .simplifiedChinese): "自动"
        case (.light, .simplifiedChinese): "浅色"
        case (.dark, .simplifiedChinese): "深色"
        }
    }
}

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english: "en_US"
        case .simplifiedChinese: "zh_CN"
        }
    }

    var isChinese: Bool { self == .simplifiedChinese }

    /// Pick English or Chinese copy based on current language.
    func t(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case engine
    case notifications
    case about

    var id: String { rawValue }

    func title(isChinese: Bool) -> String {
        switch (self, isChinese) {
        case (.general, false): "General"
        case (.general, true): "通用"
        case (.engine, false): "Engine"
        case (.engine, true): "引擎"
        case (.notifications, false): "Notifications"
        case (.notifications, true): "通知"
        case (.about, false): "About"
        case (.about, true): "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .engine: "cpu"
        case .notifications: "bell"
        case .about: "info.circle"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var appearance: AppAppearanceMode = .dark
    var language: AppLanguage = .english
    /// Play system sound when export completes.
    var playSoundWhenFinished: Bool = true
    /// Prefer Apple media-engine backed encode when re-encoding (Precise mode).
    var preferHardwareAcceleration: Bool = true
    /// Export multiple Fast-mode slices concurrently (capped). Precise stays sequential.
    var parallelFastExports: Bool = true

    private static let defaultsKey = "BeCut.AppSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    static func reset() -> AppSettings {
        let settings = AppSettings()
        settings.save()
        return settings
    }
}

enum BeCutAppMetadata {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    static let websiteURL = URL(string: "https://github.com/heymi/BitSlice")!
    static let supportEmail = "support@becut.app"
    static let supportURL = URL(string: "mailto:\(supportEmail)")!

    static var versionLabel: String {
        guard let build, !build.isEmpty, build != version else { return version }
        return "\(version) (\(build))"
    }
}
