import AVFoundation
import Foundation

/// Export configuration persisted across app launches via UserDefaults.
struct ExportConfig: Codable, Equatable {
    var segmentDuration: TimeInterval = 180
    var outputFormat: OutputFormat = .mp4
    var resolution: ExportResolution = .original
    var outputDirectory: URL?
    var customTitle: String = ""

    init() {}
}

// MARK: - Nested enums

enum OutputFormat: String, CaseIterable, Codable {
    case mp4
    case mov

    var displayName: String {
        switch self {
        case .mp4: "MP4"
        case .mov: "MOV"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4: "mp4"
        case .mov: "mov"
        }
    }

    var avFileType: AVFileType {
        switch self {
        case .mp4: .mp4
        case .mov: .mov
        }
    }
}

enum ExportResolution: String, CaseIterable, Codable {
    case original
    case hd720
    case hd1080
    case uhd2k
    case uhd4k

    var displayName: String {
        switch self {
        case .original: "原始"
        case .hd720: "720p"
        case .hd1080: "1080p"
        case .uhd2k: "2K"
        case .uhd4k: "4K"
        }
    }

    /// Target dimensions (width × height). nil for original.
    var targetSize: CGSize? {
        switch self {
        case .original: nil
        case .hd720: CGSize(width: 1280, height: 720)
        case .hd1080: CGSize(width: 1920, height: 1080)
        case .uhd2k: CGSize(width: 2560, height: 1440)
        case .uhd4k: CGSize(width: 3840, height: 2160)
        }
    }
}

// MARK: - Persistence

extension ExportConfig {
    private static let defaultsKey = "BiCut.ExportConfig"

    static func load() -> ExportConfig {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(ExportConfig.self, from: data)
        else {
            return ExportConfig()
        }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
