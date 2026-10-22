import Foundation
import PDFKit
import UniformTypeIdentifiers
import UIKit
import YIClassCore

struct ImportPayload: Sendable { let text: String; var grid: PDFGridDocument? = nil }

enum ImportSource {
    static func read(_ data: Data, type: UTType?) async throws -> ImportPayload {
        let text: String
        if type?.conforms(to: .pdf) == true {
            guard let document = PDFDocument(data: data), document.pageCount <= 20 else { throw AppFailure("请选择 20 页以内的 PDF。") }
            if let grid = PDFGridReader.read(document) { return ImportPayload(text: grid.source, grid: grid) }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { continue }
                if let content = page.string, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pages.append("第 \(index + 1) 页：\n" + content)
                } else {
                    let image = page.thumbnail(of: CGSize(width: 2200, height: 3000), for: .mediaBox)
                    guard let bytes = image.pngData() else { throw AppFailure("PDF 页面无法读取。") }
                    pages.append("第 \(index + 1) 页：\n" + (try await ImageTextRecognition.recognize(bytes)))
                }
            }
            text = pages.joined(separator: "\n")
        } else if type?.conforms(to: .image) == true {
            text = try await ImageTextRecognition.recognize(data)
        } else {
            guard let value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw AppFailure("无法读取文本编码，请使用 UTF-8 文本或 CSV。")
            }
            text = value
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure("文件中没有可识别的内容。") }
        guard text.count <= 18_000 else { throw AppFailure("课表内容较长，请按页或分批导入，避免截断漏课。") }
        return ImportPayload(text: text)
    }
}
