import Foundation
import ImageIO
import UniformTypeIdentifiers
import YIClassCore

enum ImageAttachment {
    static func read(_ data: Data) async throws -> ChatImage {
        try await Task.detached(priority: .userInitiated) {
            guard data.count <= 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let identifier = CGImageSourceGetType(source) else { throw AppFailure("无法读取图片，请选择 20 MB 以下的图片。") }
            let type = UTType(identifier as String)
            let formats: [(UTType, String)] = [(.jpeg, "image/jpeg"), (.png, "image/png"), (.gif, "image/gif"), (.webP, "image/webp")]
            if let mime = formats.first(where: { type?.conforms(to: $0.0) == true })?.1 {
                return ChatImage(data: data, mimeType: mime)
            }
            // Convert unsupported formats such as HEIC to PNG at the same pixel resolution.
            let output = NSMutableData()
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
                throw AppFailure("图片格式无法转换，请使用 JPEG 或 PNG。")
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            CGImageDestinationAddImage(destination, image, properties)
            guard CGImageDestinationFinalize(destination), output.length <= 20_000_000 else { throw AppFailure("转换后的图片超过 20 MB，请使用 JPEG 或 PNG。") }
            return ChatImage(data: output as Data, mimeType: "image/png")
        }.value
    }
    static func plainText(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?m)^\[x=[^\]]+\]\s*"#, with: "", options: .regularExpression)
    }
}
