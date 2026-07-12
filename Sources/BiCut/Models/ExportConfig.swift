import AVFoundation
import Foundation

/// Export configuration persisted across app launches via UserDefaults.
struct ExportConfig: Codable, Equatable {
    var segmentDuration: TimeInterval = 180
    var outputFormat: OutputFormat = .mp4
    var resolution: ExportResolution = .original
    var outputDirectory: URL?
    var customTitle: String = ""
    /// Default is fast (keyframe-aligned passthrough). Precise re-encodes for frame-accurate cuts.
    var splittingStrategy: SplittingStrategy = .fast
    /// Preferred output video codec. Used by precise mode only.
    var videoCodec: VideoCodecPreference = .h264

    init() {}

    private enum CodingKeys: String, CodingKey {
        case segmentDuration, outputFormat, resolution, outputDirectory, customTitle, splittingStrategy, videoCodec
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        segmentDuration = try values.decodeIfPresent(TimeInterval.self, forKey: .segmentDuration) ?? 180
        outputFormat = try values.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .mp4
        resolution = try values.decodeIfPresent(ExportResolution.self, forKey: .resolution) ?? .original
        outputDirectory = try values.decodeIfPresent(URL.self, forKey: .outputDirectory)
        customTitle = try values.decodeIfPresent(String.self, forKey: .customTitle) ?? ""
        splittingStrategy = try values.decodeIfPresent(SplittingStrategy.self, forKey: .splittingStrategy) ?? .fast
        videoCodec = try values.decodeIfPresent(VideoCodecPreference.self, forKey: .videoCodec) ?? .h264
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(segmentDuration, forKey: .segmentDuration)
        try values.encode(outputFormat, forKey: .outputFormat)
        try values.encode(resolution, forKey: .resolution)
        try values.encodeIfPresent(outputDirectory, forKey: .outputDirectory)
        try values.encode(customTitle, forKey: .customTitle)
        try values.encode(splittingStrategy, forKey: .splittingStrategy)
        try values.encode(videoCodec, forKey: .videoCodec)
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

/// Codecs BiCut can actually target when re-encoding (Precise mode).
enum VideoCodecPreference: String, CaseIterable, Identifiable {
    case h264
    case hevc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .h264: "H264"
        case .hevc: "HEVC"
        }
    }

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        }
    }
}

extension VideoCodecPreference: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case Self.hevc.rawValue:
            self = .hevc
        case Self.h264.rawValue:
            self = .h264
        default:
            // Ignore legacy unsupported values such as "prores" / "gif".
            self = .h264
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum SplittingStrategy: String, CaseIterable, Codable, Identifiable, Equatable {
    /// Stream copy / remux. Much faster; starts may snap back to the previous keyframe.
    case fast
    /// Decode + re-encode. Frame-aligned cuts; slower.
    case precise

    var id: String { rawValue }

    func displayName(for language: AppLanguage) -> String {
        switch self {
        case .fast: language.t("Fast", "快速")
        case .precise: language.t("Precise", "精确")
        }
    }

    func shortDescription(for language: AppLanguage) -> String {
        switch self {
        case .fast:
            language.t(
                "Near-instant stream copy. Cut starts may begin slightly earlier at the previous keyframe (often under 1–2s).",
                "近乎即时的直通复制。切点可能略提前到上一关键帧（常见不到 1–2 秒）。"
            )
        case .precise:
            language.t(
                "Frame-accurate cuts via re-encoding. Keeps planned timing; slower and may lightly recompress.",
                "重编码实现帧级精确切点，时间更准，但更慢，可能有轻微画质损失。"
            )
        }
    }
}

enum SegmentDurationPreset: Int, CaseIterable, Identifiable, Equatable {
    case seconds15 = 15
    case seconds30 = 30
    case seconds60 = 60
    case minutes2 = 120
    case minutes3 = 180

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    func displayName(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.seconds15, .english): "15s"
        case (.seconds30, .english): "30s"
        case (.seconds60, .english): "60s"
        case (.minutes2, .english): "2 min"
        case (.minutes3, .english): "3 min"
        case (.seconds15, .simplifiedChinese): "15 秒"
        case (.seconds30, .simplifiedChinese): "30 秒"
        case (.seconds60, .simplifiedChinese): "60 秒"
        case (.minutes2, .simplifiedChinese): "2 分钟"
        case (.minutes3, .simplifiedChinese): "3 分钟"
        }
    }
}

func validSegmentDuration(_ requested: TimeInterval, videoDuration: TimeInterval) -> TimeInterval {
    let lowerBounded = max(1, requested)
    guard videoDuration >= 1 else { return lowerBounded }
    return min(lowerBounded, videoDuration)
}

enum ExportResolution: String, CaseIterable, Codable, Equatable {
    case original
    case hd720
    case hd1080
    case uhd2k
    case uhd4k

    func displayName(for language: AppLanguage = .english) -> String {
        switch self {
        case .original: language.t("Original", "原始")
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
