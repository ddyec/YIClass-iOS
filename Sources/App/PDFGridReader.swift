import Foundation
import PDFKit
import YIClassCore

// PDFKit coordinates use an unrotated bottom-left origin. Keep columns across page breaks.
enum PDFGridReader {
    static func read(_ document: PDFDocument) -> PDFGridDocument? {
        guard let first = document.page(at: 0), let firstText = first.string else { return nil }
        let headerPattern = "星期[一二三四五六日天⼀⼆⽇]"
        guard let regex = try? NSRegularExpression(pattern: headerPattern) else { return nil }
        let headers = regex.matches(in: firstText, range: NSRange(firstText.startIndex..., in: firstText))
        guard headers.count == 7 else { return nil }
        let boxes = headers.compactMap { first.selection(for: $0.range).map { canonical($0.bounds(for: first), page: first) } }.sorted { $0.midX < $1.midX }
        guard boxes.count == 7 else { return nil }
        let spacing = (boxes[6].midX - boxes[0].midX) / 6
        let left = boxes[0].midX - spacing / 2
        var columns = Array(repeating: "", count: 7)
        var other = ""
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex), let text = page.string else { return nil }
            let source = text as NSString
            let otherRange = source.range(of: "其他课程")
            var bottom = Double.greatestFiniteMagnitude
            if otherRange.location != NSNotFound, let selection = page.selection(for: otherRange) {
                bottom = canonical(selection.bounds(for: page), page: page).minY - 1
                other += source.substring(from: otherRange.location + otherRange.length)
                    .components(separatedBy: "打印时间").first ?? ""
            }
            let top = pageIndex == 0 ? boxes.map(\.maxY).max()! : -Double.greatestFiniteMagnitude
            var characters: [(Int, CGFloat, CGFloat, String)] = []
            source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .byComposedCharacterSequences) { value, range, _, _ in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      range.location < page.numberOfCharacters else { return }
                // Avoid constructing a PDFSelection for every character on device.
                var bounds = page.characterBounds(at: range.location)
                for index in (range.location + 1)..<min(NSMaxRange(range), page.numberOfCharacters) {
                    bounds = bounds.union(page.characterBounds(at: index))
                }
                let rect = canonical(bounds, page: page)
                guard rect.midY > top, rect.midY < bottom else { return }
                let column = Int(floor((rect.midX - left) / spacing))
                guard (0..<7).contains(column) else { return }
                characters.append((column, rect.midY, rect.minX, value))
            }
            for column in 0..<7 {
                let ordered = characters.filter { $0.0 == column }.sorted { a, b in abs(a.1 - b.1) > 2 ? a.1 < b.1 : a.2 < b.2 }
                columns[column] += ordered.map { $0.3 }.joined() + "\n"
            }
        }
        // The footer legend follows the semicolon-terminated list and is not a course.
        if let last = other.lastIndex(of: ";") { other = String(other[...last]) }
        other = other.trimmingCharacters(in: CharacterSet(charactersIn: "：: \n"))
        return PDFGridDocument(columns: columns, otherCourses: other)
    }
    private static func canonical(_ rect: CGRect, page: PDFPage) -> CGRect {
        let box = page.bounds(for: .mediaBox)
        switch (page.rotation % 360 + 360) % 360 {
        case 90: return CGRect(x: rect.minY - box.minY, y: rect.minX - box.minX, width: rect.height, height: rect.width)
        case 180: return CGRect(x: box.maxX - rect.maxX, y: rect.minY - box.minY, width: rect.width, height: rect.height)
        case 270: return CGRect(x: box.maxY - rect.maxY, y: box.maxX - rect.maxX, width: rect.height, height: rect.width)
        default: return CGRect(x: rect.minX - box.minX, y: box.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
    }
}
