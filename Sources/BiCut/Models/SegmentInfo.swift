import CoreMedia
import Foundation

/// Describes a single output segment.
struct SegmentInfo: Identifiable, Equatable {
    let id = UUID()
    let index: Int              // 0-based
    let start: CMTime
    let end: CMTime
    let fileName: String

    var duration: CMTime {
        CMTimeSubtract(end, start)
    }

    var durationSeconds: Double {
        CMTimeGetSeconds(duration)
    }

    var startSeconds: Double {
        CMTimeGetSeconds(start)
    }

    /// Human-readable time label like "3:00"
    var startLabel: String {
        formatTime(startSeconds)
    }
}

// MARK: - Segment calculation

/// Calculates segment boundaries for a given total duration and target segment duration.
/// The last segment may be shorter than the target duration.
func calculateSegments(
    totalDuration: CMTime,
    segmentDuration: CMTime,
    baseName: String,
    fileExtension: String
) -> [SegmentInfo] {
    let totalSec = CMTimeGetSeconds(totalDuration)
    let segSec = CMTimeGetSeconds(segmentDuration)

    guard totalSec > 0, segSec > 0 else { return [] }

    let count = max(1, Int(ceil(totalSec / segSec)))

    return (0 ..< count).map { i in
        let startSec = Double(i) * segSec
        let endSec = min(startSec + segSec, totalSec)
        let start = CMTime(seconds: startSec, preferredTimescale: totalDuration.timescale)
        let end = CMTime(seconds: endSec, preferredTimescale: totalDuration.timescale)
        let name = "\(baseName)-\(i + 1).\(fileExtension)"
        return SegmentInfo(index: i, start: start, end: end, fileName: name)
    }
}

// MARK: - Formatting

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = Int(seconds.rounded())
    let min = total / 60
    let sec = total % 60
    return String(format: "%d:%02d", min, sec)
}

func formatTimeDetailed(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00:00" }
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
}
