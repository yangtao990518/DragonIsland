import Foundation

enum CharacterMemoryError: LocalizedError {
    case invalid, tooLarge, unreadable, noSources
    var errorDescription: String? {
        switch self {
        case .invalid: return "记忆文件格式无效，原文件已保留。"
        case .tooLarge: return "单条记忆最多 6000 字、24 KB；每个角色最多 40 个文件、合计 12000 字。"
        case .unreadable: return "记忆文件暂时无法读取，请在关于的记忆管理中检查，原文件未修改。"
        case .noSources: return "这个会话还没有可整理的已完成用户文字消息。"
        }
    }
}

struct CharacterMemoryDocument: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let characterID: String
    var title: String
    var text: String
    var modifiedAt: Date
    var filename: String { id.uuidString + ".md" }
    var data: Data { Data(("# " + title + "\n\n" + text).utf8) }
    var byteCount: Int { data.count }
    func validate() throws {
        guard Self.validRole(characterID), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 80, !title.contains("\n"), !title.contains("\r"), !title.contains("\0"),
              !text.contains("\0"), modifiedAt.timeIntervalSince1970.isFinite else { throw CharacterMemoryError.invalid }
        guard text.count <= 6000, byteCount <= 24 * 1024 else { throw CharacterMemoryError.tooLarge }
    }
    static func validRole(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 120 && value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }
    static func validate(_ documents: [Self]) throws {
        guard documents.count <= 1000, Set(documents.map(\.id)).count == documents.count else { throw CharacterMemoryError.invalid }
        for document in documents { try document.validate() }
        for group in Dictionary(grouping: documents, by: \.characterID).values {
            guard group.count <= 40, group.reduce(0, { $0 + $1.text.count }) <= 12000 else { throw CharacterMemoryError.tooLarge }
        }
    }
}

/// Authoritative UTF-8 files, separate from the legacy shared history JSON.
struct CharacterMemoryFiles: Sendable {
    let directory: URL
    init(historyURL: URL) { directory = historyURL.deletingLastPathComponent().appendingPathComponent("Memory", isDirectory: true) }
    init(directory: URL) { self.directory = directory }
    func folder(_ characterID: String) throws -> URL {
        guard CharacterMemoryDocument.validRole(characterID) else { throw CharacterMemoryError.invalid }
        let url = directory.appendingPathComponent(characterID, isDirectory: true)
        try rejectSymlink(directory); try rejectSymlink(url)
        return url
    }
    func url(for document: CharacterMemoryDocument) throws -> URL {
        try document.validate()
        let url = try folder(document.characterID).appendingPathComponent(document.filename)
        try rejectSymlink(url)
        return url
    }
    func documents(for characterID: String) throws -> [CharacterMemoryDocument] {
        let folder = try folder(characterID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isRegularFileKey])
        var result: [CharacterMemoryDocument] = []
        for url in urls where url.pathExtension == "md" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw CharacterMemoryError.invalid }
            let info = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard info.isSymbolicLink != true, info.isRegularFile == true, let size = info.fileSize, size <= 24 * 1024,
                  let raw = String(data: try Data(contentsOf: url), encoding: .utf8), raw.hasPrefix("# "),
                  let split = raw.range(of: "\n\n") else { throw CharacterMemoryError.unreadable }
            let document = CharacterMemoryDocument(id: id, characterID: characterID,
                title: String(raw[raw.index(raw.startIndex, offsetBy: 2)..<split.lowerBound]),
                text: String(raw[split.upperBound...]), modifiedAt: info.contentModificationDate ?? .distantPast)
            try document.validate(); result.append(document)
        }
        try CharacterMemoryDocument.validate(result)
        return result.sorted { $0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt }
    }
    func snapshot() throws -> [CharacterMemoryDocument] {
        try rejectSymlink(directory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        var result: [CharacterMemoryDocument] = []
        for folder in folders {
            let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true else { throw CharacterMemoryError.invalid }
            if info.isDirectory == true { result += try documents(for: folder.lastPathComponent) }
        }
        try CharacterMemoryDocument.validate(result)
        return result
    }
    func save(_ document: CharacterMemoryDocument) throws {
        try document.validate()
        var next = try documents(for: document.characterID).filter { $0.id != document.id }
        next.append(document); try CharacterMemoryDocument.validate(next)
        let url = try url(for: document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try document.data.write(to: url, options: .atomic)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var target = directory; try target.setResourceValues(values)
        target = url; try target.setResourceValues(values)
        try FileManager.default.setAttributes([.modificationDate: document.modifiedAt], ofItemAtPath: url.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    func delete(_ document: CharacterMemoryDocument) throws { try FileManager.default.removeItem(at: url(for: document)) }
    func actualByteCount(of document: CharacterMemoryDocument) throws -> Int {
        try url(for: document).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }
    private func rejectSymlink(_ url: URL) throws {
        if let info = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), info.isSymbolicLink == true { throw CharacterMemoryError.invalid }
    }
    func stage(_ documents: [CharacterMemoryDocument]) throws -> URL {
        try CharacterMemoryDocument.validate(documents)
        let staging = directory.deletingLastPathComponent().appendingPathComponent("Memory-import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do { let files = CharacterMemoryFiles(directory: staging); for document in documents { try files.save(document) }; return staging }
        catch { try? FileManager.default.removeItem(at: staging); throw error }
    }
    /// Keep the original directory until the history JSON is safely committed.
    func install(staging: URL) throws -> URL? {
        try rejectSymlink(directory)
        let old = directory.deletingLastPathComponent().appendingPathComponent("Memory-previous-" + UUID().uuidString, isDirectory: true)
        let existed = FileManager.default.fileExists(atPath: directory.path)
        if existed { try FileManager.default.moveItem(at: directory, to: old) }
        do { try FileManager.default.moveItem(at: staging, to: directory); return existed ? old : nil }
        catch { if existed { try? FileManager.default.moveItem(at: old, to: directory) }; throw error }
    }
    func rollback(previous: URL?) throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        if let previous { try FileManager.default.moveItem(at: previous, to: directory) }
    }
}
