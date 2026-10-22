import Foundation
import UniformTypeIdentifiers
import YIClassCore

struct ImportedDocument: Sendable {
    let data: Data
    let type: UTType?
}

enum DocumentFileReader {
    // File providers may need to materialize a document. Never block the picker/UI thread.
    static func read(_ url: URL, maximumBytes: Int) async throws -> ImportedDocument {
        try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var coordinationError: NSError?
            var result: Result<ImportedDocument, any Error>?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
                result = Result {
                    let values = try readableURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                    if let size = values.fileSize, size > maximumBytes { throw AppFailure("文件不能超过 \(maximumBytes / 1_000_000) MB。") }
                    let handle = try FileHandle(forReadingFrom: readableURL)
                    defer { try? handle.close() }
                    var bytes = Data()
                    while let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - bytes.count)), !chunk.isEmpty {
                        bytes.append(chunk)
                        guard bytes.count <= maximumBytes else { throw AppFailure("文件不能超过 \(maximumBytes / 1_000_000) MB。") }
                    }
                    guard !bytes.isEmpty else { throw AppFailure("所选文件为空，请重新选择。") }
                    let type: UTType?
                    if bytes.starts(with: Data("%PDF-".utf8)) { type = .pdf }
                    else { type = values.contentType ?? UTType(filenameExtension: readableURL.pathExtension) }
                    return ImportedDocument(data: bytes, type: type)
                }
            }
            if let coordinationError { throw AppFailure("无法读取所选文件：\(coordinationError.localizedDescription)") }
            guard let result else { throw AppFailure("文件尚不可用，请下载到本机后重试。") }
            return try result.get()
        }.value
    }
}
