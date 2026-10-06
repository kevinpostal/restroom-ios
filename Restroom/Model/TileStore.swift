import Foundation

/// JSON file in Caches holding the most recent result pages by grid cell, so a relaunch starts warm.
/// Reads once at init; writes are whole-file, debounced by the caller's call rate (one per fetched page).
final class TileStore: @unchecked Sendable {
    struct Entry: Codable {
        let at: Date
        let list: [Restroom]
    }

    /// Bound on file size: 64 pages × ≤100 rows ≈ 3 MB.
    static let maxEntries = 64
    static let disk = TileStore(url: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("tiles.json"))

    private let url: URL
    private let queue = DispatchQueue(label: "restroom.tilestore", qos: .utility)

    init(url: URL) { self.url = url }

    func load() -> [Cell: Entry] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        var out: [Cell: Entry] = [:]
        for (key, entry) in raw {
            let parts = key.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            out[Cell(x: parts[0], y: parts[1])] = entry
        }
        return out
    }

    func save(_ cells: [Cell: Entry]) {
        let newest = cells.sorted { $0.value.at > $1.value.at }.prefix(Self.maxEntries)
        let raw = Dictionary(uniqueKeysWithValues: newest.map { ("\($0.key.x),\($0.key.y)", $0.value) })
        queue.async { [url] in
            guard let data = try? JSONEncoder().encode(raw) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func clear() {
        queue.async { [url] in try? FileManager.default.removeItem(at: url) }
    }
}
