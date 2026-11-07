import SwiftUI
import PhotosUI
import QuickLook
import UIKit
import UniformTypeIdentifiers

/// QuickLook preview (ảnh/video/pdf/text…).
/// QLPreviewController nhúng trần vào .sheet thì KHÔNG có nút Done (không cách
/// nào đóng, vuốt-xuống bị cử chỉ media nuốt) — phải bọc trong
/// UINavigationController thì QL tự thêm nút "Xong" để dismiss.
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        context.coordinator.url = url
        (nav.viewControllers.first as? QLPreviewController)?.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

/// Share sheet hệ thống.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// PHPicker (ảnh/video không cần quyền Photo Library).
struct PhotoPicker: UIViewControllerRepresentable {
    protocol Item {
        var suggestedName: String? { get }
        func loadFileURL() async throws -> URL
    }

    var onDone: ([any Item]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.selectionLimit = 20
        cfg.filter = .any(of: [.images, .videos])
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onDone: ([any Item]) -> Void
        init(onDone: @escaping ([any Item]) -> Void) { self.onDone = onDone }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let provider = results.map(\.itemProvider)
            var items: [Item] = []
            let group = DispatchGroup()
            let lock = NSLock()

            for p in provider {
                // Ảnh/video: tải file gốc về tmp để copy vào mirror.
                if p.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    group.enter()
                    p.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                        defer { group.leave() }
                        guard let url else { return }
                        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + (p.suggestedName ?? url.lastPathComponent))
                        try? FileManager.default.copyItem(at: url, to: dest)
                        lock.lock()
                        items.append(RealItem(name: p.suggestedName ?? dest.lastPathComponent, fileURL: dest))
                        lock.unlock()
                    }
                } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    p.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                        defer { group.leave() }
                        guard let url else { return }
                        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + (p.suggestedName ?? url.lastPathComponent))
                        try? FileManager.default.copyItem(at: url, to: dest)
                        lock.lock()
                        items.append(RealItem(name: p.suggestedName ?? dest.lastPathComponent, fileURL: dest))
                        lock.unlock()
                    }
                }
            }

            group.notify(queue: .main) { [onDone] in
                onDone(items)
            }
        }

        struct RealItem: Item {
            var name: String
            var fileURL: URL
            var suggestedName: String? { name }
            func loadFileURL() async throws -> URL { fileURL }
        }
    }
}

/// Camera (chụp ảnh / quay video).
enum CameraMode {
    case photo
    case video
}

enum CameraResult {
    case image(UIImage)
    case video(URL)
}

struct CameraPicker: UIViewControllerRepresentable {
    var mode: CameraMode
    var onDone: (CameraResult?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            vc.sourceType = .camera
        } else {
            vc.sourceType = .photoLibrary   // máy không có camera — hiếm gặp
        }
        switch mode {
        case .photo:
            vc.mediaTypes = [UTType.image.identifier]
        case .video:
            vc.mediaTypes = [UTType.movie.identifier]
            vc.videoQuality = .typeHigh
        }
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (CameraResult?) -> Void
        init(onDone: @escaping (CameraResult?) -> Void) { self.onDone = onDone }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                onDone(.image(image))
            } else if let url = info[.mediaURL] as? URL {
                onDone(.video(url))
            } else {
                onDone(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onDone(nil)
        }
    }
}

/// UIDocumentPicker (trên iOS 27.2 app sideload có thể trả rỗng — đã ghi trong AGENTS.md).
struct DocumentPicker: UIViewControllerRepresentable {
    var onDone: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        vc.allowsMultipleSelection = true
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDone: ([URL]) -> Void
        init(onDone: @escaping ([URL]) -> Void) { self.onDone = onDone }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onDone(urls)
        }
    }
}

/// UIDocumentPicker chọn thư mục (asCopy → trả bản copy của cây thư mục trong
/// tmp; copy sang mirror xong phải xoá để tmp không phình to).
struct FolderDocumentPicker: UIViewControllerRepresentable {
    var onDone: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDone: (URL?) -> Void
        init(onDone: @escaping (URL?) -> Void) { self.onDone = onDone }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onDone(urls.first)
        }
    }
}
