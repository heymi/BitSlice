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
    frameDuration: CMTime? = nil,
    baseName: String,
    fileExtension: String
) -> [SegmentInfo] {
    let totalSec = CMTimeGetSeconds(totalDuration)
    let segSec = CMTimeGetSeconds(segmentDuration)

    guard totalSec > 0, segSec > 0 else { return [] }

    var boundaries: [CMTime] = [.zero]
    var requestedBoundary = segSec
    while requestedBoundary < totalSec {
        let boundary = snapToNearestFrame(
            CMTime(seconds: requestedBoundary, preferredTimescale: totalDuration.timescale),
            frameDuration: frameDuration
        )
        if CMTimeCompare(boundary, boundaries.last!) > 0,
           CMTimeCompare(boundary, totalDuration) < 0 {
            boundaries.append(boundary)
        }
        requestedBoundary += segSec
    }
    boundaries.append(totalDuration)

    return (0 ..< boundaries.count - 1).map { i in
        let start = boundaries[i]
        let end = boundaries[i + 1]
        let sequence = String(format: "%02d", i + 1)
        let name = "\(baseName)_part_\(sequence).\(fileExtension)"
        return SegmentInfo(index: i, start: start, end: end, fileName: name)
    }
}

private func snapToNearestFrame(_ time: CMTime, frameDuration: CMTime?) -> CMTime {
    guard let frameDuration,
          frameDuration.isValid,
          frameDuration.isNumeric,
          CMTimeCompare(frameDuration, .zero) > 0
    else { return time }

    let frame = CMTimeGetSeconds(frameDuration)
    let seconds = CMTimeGetSeconds(time)
    guard frame.isFinite, frame > 0, seconds.isFinite else { return time }
    let frameIndex = (seconds / frame).rounded()
    return CMTimeMultiplyByFloat64(frameDuration, multiplier: frameIndex)
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
