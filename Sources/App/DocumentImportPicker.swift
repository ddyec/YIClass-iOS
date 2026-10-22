import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor struct DocumentImportPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onSelection: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }

    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onSelection: (URL?) -> Void
        private var finished = false
        init(onSelection: @escaping (URL?) -> Void) { self.onSelection = onSelection }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
        private func finish(_ url: URL?) {
            guard !finished else { return }
            finished = true
            onSelection(url)
        }
    }
}
