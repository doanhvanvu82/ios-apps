import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Trình chọn **một tệp bất kỳ** ở chế độ mở (`asCopy: false`) để lấy security scope.
///
/// Chọn folder bằng picker đang hỏng trên iOS 27.2 với app này (trả rỗng,
/// `Could not resolve bookmark`), nên người dùng chọn một tệp nằm trong thư mục
/// game; `GameLibrary.handleFolderPick` lấy thư mục cha của tệp đó.
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
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
