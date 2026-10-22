import Foundation

// Ported from YIClass feat/ai-planner-ios-widget (9fd890b), ios/Shared/SharedGroup.swift.
// Re-signers can replace the configured group with a provisioned group. The
// operating system's container lookup, rather than a profile declaration, grants access.
enum SharedGroup {
    static let defaultIdentifier = "group.com.ddyec.YIClassNative"

    static func candidates(configured: String?, profile: Data?) -> [String] {
        var identifiers = [configured, defaultIdentifier].compactMap { $0 }
        if let profile, profile.count < 5_000_000,
           let start = profile.range(of: Data("<?xml".utf8)),
           let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
           let root = (try? PropertyListSerialization.propertyList(from: profile[start.lowerBound..<end.upperBound], options: [], format: nil)) as? [String: Any],
           let entitlements = root["Entitlements"] as? [String: Any],
           let groups = entitlements["com.apple.security.application-groups"] as? [String] {
            identifiers.append(contentsOf: groups.sorted())
        }
        var seen = Set<String>()
        return identifiers.filter { $0.hasPrefix("group.") && !$0.contains("*") && seen.insert($0).inserted }
    }

    static func containers() -> [(identifier: String, url: URL)] {
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return candidates(configured: Bundle.main.object(forInfoDictionaryKey: "YIClassAppGroup") as? String, profile: profile)
            .compactMap { identifier in
                FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
                    .map { (identifier, $0) }
            }
    }
}
