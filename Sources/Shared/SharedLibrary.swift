import Foundation
import YIClassCore

enum SharedLibrary {
    static let group = SharedGroup.defaultIdentifier
    private static var files: [URL] {
        SharedGroup.containers().map { $0.url.appendingPathComponent("widget-library.json") }
    }
    static func read() -> AppData? { try? readResult().get() }
    static func readResult() -> Result<AppData, AppFailure> {
        let candidates = files.sorted {
            let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return first > second
        }
        guard !candidates.isEmpty else { return readResult(from: nil) }
        var failure = readResult(from: candidates[0])
        for file in candidates {
            let result = readResult(from: file)
            if case .success = result { return result }
            failure = result
        }
        return failure
    }
    static func readResult(from file: URL?) -> Result<AppData, AppFailure> {
        guard let file else { return .failure(AppFailure("小组件共享权限不可用，请检查重签时的 App Group。")) }
        guard FileManager.default.fileExists(atPath: file.path) else { return .failure(AppFailure("尚未同步课表，请打开应用并在设置中同步小组件。")) }
        do {
            let data = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: file))
            try data.validate()
            return .success(data)
        } catch { return .failure(AppFailure("共享课表读取失败，请解锁并打开应用重新同步。")) }
    }
    static func write(_ data: AppData) throws {
        let candidates = files
        guard !candidates.isEmpty else { try write(data, to: nil); return }
        // App and extension profiles can list different additional groups. Publish
        // to every accessible group so their common group receives the same snapshot.
        var written = false
        var failure: (any Error)?
        for file in candidates {
            do { try write(data, to: file); written = true }
            catch { failure = error }
        }
        if !written, let failure { throw failure }
    }
    static func write(_ data: AppData, to file: URL?) throws {
        guard let file else { throw AppFailure("小组件共享容器不可用，请检查 App Group 签名配置。") }
        try JSONCoding.encoder().encode(data).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
