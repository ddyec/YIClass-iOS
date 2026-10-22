import Foundation
import YIClassCore

enum SharedLibrary {
    static let group = "group.com.ddyec.YIClassNative"
    static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget-library.json")
    }
    static func read() -> AppData? {
        guard let file, let bytes = try? Data(contentsOf: file),
              let data = try? JSONCoding.decoder().decode(AppData.self, from: bytes), (try? data.validate()) != nil else { return nil }
        return data
    }
    static func write(_ data: AppData) throws {
        guard let file else { throw AppFailure("小组件共享容器不可用，请检查 App Group 签名配置。") }
        try JSONCoding.encoder().encode(data).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
