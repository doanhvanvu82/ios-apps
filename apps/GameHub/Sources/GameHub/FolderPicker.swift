import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Trình chọn thư mục ở chế độ **mở** (`asCopy: false`), trả URL có security scope.
///
/// Không dùng `.fileImporter` của SwiftUI: trên iOS 27 nó mở picker ở chế độ import,
/// hệ thống không materialize được folder từ FileProvider ("On My iPhone/Tải về")
/// nên trả về danh sách rỗng và callback không bao giờ chạy.
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
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
