import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Trình chọn thư mục ở chế độ mở (`asCopy: false`), trả URL có security scope.
///
/// Không dùng `.fileImporter` của SwiftUI: nó mở picker ở chế độ import.
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Initializer legacy: trên iOS 27.2 đường UTType mới trả về selection rỗng
        // (bookmark không resolve được) với app này; thử đường cũ.
        let picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (Result<[URL], Error>) -> Void
        private var finished = false

        init(onPick: @escaping (Result<[URL], Error>) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard !finished else { return }
            finished = true
            onPick(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !finished else { return }
            finished = true
            onPick(.failure(CocoaError(.userCancelled)))
        }
    }
}
