import Foundation

struct RecentVideo: Codable, Identifiable, Equatable {
    let path: String
    let fileName: String
    let width: Int
    let height: Int
    let frameRate: Int
    let fileSize: Int64
    let lastOpenedAt: Date
    let bookmark: Data?

    var id: String { path }

    var url: URL {
        var isStale = false
        if let bookmark,
           let resolved = try? URL(
               resolvingBookmarkData: bookmark,
               options: .withSecurityScope,
               relativeTo: nil,
               bookmarkDataIsStale: &isStale
           ) {
            return resolved
        }
        return URL(fileURLWithPath: path)
    }
}

extension RecentVideo {
    private static let defaultsKey = "BiCut.RecentVideos"

    static func loadAll() -> [RecentVideo] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let values = try? JSONDecoder().decode([RecentVideo].self, from: data)
        else { return [] }
        return values.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    static func saveAll(_ values: [RecentVideo]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
