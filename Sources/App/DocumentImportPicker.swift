import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Present and finish in UIKit; document pickers can dismiss themselves without a
// SwiftUI fullScreenCover onDismiss callback, so that callback must not start I/O.
@MainActor struct DocumentImportPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let contentTypes: [UTType]
    let onSelection: (URL?) -> Void

    func makeUIViewController(context: Context) -> Presenter { Presenter() }
    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.contentTypes = contentTypes
        controller.onSelection = { url in
            isPresented = false
            onSelection(url)
        }
        controller.requested = isPresented
        controller.showIfReady()
    }

    @MainActor final class Presenter: UIViewController, UIDocumentPickerDelegate {
        var contentTypes: [UTType] = []
        var onSelection: ((URL?) -> Void)?
        var requested = false
        private var picker: UIDocumentPickerViewController?
        private var finishing = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            showIfReady()
        }
        func showIfReady() {
            guard requested, picker == nil, viewIfLoaded?.window != nil else { return }
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
            documentPicker.delegate = self
            documentPicker.allowsMultipleSelection = false
            documentPicker.shouldShowFileExtensions = true
            picker = documentPicker
            present(documentPicker, animated: true)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls.first, controller: controller) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil, controller: controller) }
        private func finish(_ url: URL?, controller: UIDocumentPickerViewController) {
            guard !finishing else { return }
            finishing = true
            requested = false
            let complete = { [self] in
                picker = nil
                onSelection?(url)
                finishing = false
            }
            if controller.presentingViewController != nil { controller.dismiss(animated: true, completion: complete) }
            else { complete() }
        }
    }
}
