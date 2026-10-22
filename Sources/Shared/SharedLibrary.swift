import Foundation
import YIClassCore

enum SharedLibrary {
    static let group = "group.com.ddyec.YIClassNative"
    static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget-library.json")
    }
    static func read() -> AppData? { try? readResult().get() }
    static func readResult() -> Result<AppData, AppFailure> { readResult(from: file) }
    static func readResult(from file: URL?) -> Result<AppData, AppFailure> {
        guard let file else { return .failure(AppFailure("小组件共享权限不可用，请检查重签时的 App Group。")) }
        guard FileManager.default.fileExists(atPath: file.path) else { return .failure(AppFailure("尚未同步课表，请打开应用并在设置中同步小组件。")) }
        do {
            let data = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: file))
            try data.validate()
            return .success(data)
        } catch { return .failure(AppFailure("共享课表读取失败，请解锁并打开应用重新同步。")) }
    }
    static func write(_ data: AppData) throws { try write(data, to: file) }
    static func write(_ data: AppData, to file: URL?) throws {
        guard let file else { throw AppFailure("小组件共享容器不可用，请检查 App Group 签名配置。") }
        try JSONCoding.encoder().encode(data).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
