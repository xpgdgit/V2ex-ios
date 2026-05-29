import Foundation

extension Notification.Name {
    static let v2exCacheDidClear = Notification.Name("V2EXCacheDidClear")
}

actor CacheStore {
    static let shared = CacheStore()

    private var memory: [String: Data] = [:]
    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "V2EXClient", directoryHint: .isDirectory)
        self.directory = base.appending(path: "V2EXClientCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        Self.excludeFromBackup(self.directory)

        if directory == nil {
            Self.migrateLegacyCache(to: self.directory)
        }
    }

    func value<T: Decodable>(for key: String, as type: T.Type = T.self) -> T? {
        let cacheKey = sanitized(key)
        let data = memory[cacheKey] ?? (try? Data(contentsOf: fileURL(for: cacheKey)))
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func set<T: Encodable>(_ value: T, for key: String) {
        let cacheKey = sanitized(key)
        guard let data = try? JSONEncoder().encode(value) else { return }
        memory[cacheKey] = data
        try? data.write(to: fileURL(for: cacheKey), options: .atomic)
    }

    func clear() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func diskUsage() -> Int64 {
        Self.diskUsage(of: directory)
    }

    private func fileURL(for key: String) -> URL {
        directory.appending(path: "\(key).json")
    }

    private func sanitized(_ key: String) -> String {
        key.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    }

    private static func migrateLegacyCache(to directory: URL) {
        let legacyDirectory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "V2EXClientCache", directoryHint: .isDirectory)
        guard legacyDirectory != directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: legacyDirectory,
                includingPropertiesForKeys: nil
              ) else {
            return
        }

        for source in files {
            let destination = directory.appending(path: source.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }
            try? FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var cacheURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? cacheURL.setResourceValues(values)
    }

    private static func diskUsage(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]),
                  values.isRegularFile == true else {
                continue
            }

            let bytes = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
            total += Int64(bytes)
        }

        return total
    }
}
