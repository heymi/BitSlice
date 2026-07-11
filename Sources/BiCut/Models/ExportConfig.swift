import AVFoundation
import Foundation

/// Export configuration persisted across app launches via UserDefaults.
struct ExportConfig: Codable, Equatable {
    var segmentDuration: TimeInterval = 180
    var outputFormat: OutputFormat = .mp4
    var resolution: ExportResolution = .original
    var outputDirectory: URL?
    var customTitle: String = ""
    var splittingStrategy: SplittingStrategy = .precise

    init() {}

    private enum CodingKeys: String, CodingKey {
        case segmentDuration, outputFormat, resolution, outputDirectory, customTitle, splittingStrategy
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        segmentDuration = try values.decodeIfPresent(TimeInterval.self, forKey: .segmentDuration) ?? 180
        outputFormat = try values.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .mp4
        resolution = try values.decodeIfPresent(ExportResolution.self, forKey: .resolution) ?? .original
        outputDirectory = try values.decodeIfPresent(URL.self, forKey: .outputDirectory)
        customTitle = try values.decodeIfPresent(String.self, forKey: .customTitle) ?? ""
        splittingStrategy = try values.decodeIfPresent(SplittingStrategy.self, forKey: .splittingStrategy) ?? .precise
    }
}

// MARK: - Nested enums

enum OutputFormat: String, CaseIterable, Codable {
    case mp4
    case mov
    case m4v

    var displayName: String {
        switch self {
        case .mp4: "MP4"
        case .mov: "MOV"
        case .m4v: "M4V"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4: "mp4"
        case .mov: "mov"
        case .m4v: "m4v"
        }
    }

    var avFileType: AVFileType {
        switch self {
        case .mp4: .mp4
        case .mov: .mov
        case .m4v: .m4v
        }
    }
}

enum SplittingStrategy: String, Codable {
    case precise
}

enum SegmentDurationPreset: Int, CaseIterable, Identifiable {
    case seconds15 = 15
    case seconds30 = 30
    case seconds60 = 60
    case minutes2 = 120
    case minutes3 = 180

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var displayName: String {
        switch self {
        case .seconds15: "15 秒"
        case .seconds30: "30 秒"
        case .seconds60: "60 秒"
        case .minutes2: "2 分钟"
        case .minutes3: "3 分钟"
        }
    }
}

func validSegmentDuration(_ requested: TimeInterval, videoDuration: TimeInterval) -> TimeInterval {
    let lowerBounded = max(1, requested)
    guard videoDuration >= 1 else { return lowerBounded }
    return min(lowerBounded, videoDuration)
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
