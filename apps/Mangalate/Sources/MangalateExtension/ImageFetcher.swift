import Foundation
import UIKit

/// Tải ảnh trang truyện để OCR. Appex không có cookie của Safari, nên chỉ gửi kèm Referer + cookie
/// không-HttpOnly mà content script đọc được; nhiều CDN ảnh chỉ cần Referer.
enum ImageFetcher {
    static func download(url: String, referer: String?, cookie: String?) async throws -> UIImage {
        guard let url = URL(string: url) else {
            throw MangalateError("URL ảnh không hợp lệ.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer, !referer.isEmpty { request.setValue(referer, forHTTPHeaderField: "Referer") }
        if let cookie, !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw MangalateError("Tải ảnh thất bại (HTTP \(status)).")
        }
        guard data.count <= 30_000_000 else {
            throw MangalateError("Ảnh quá lớn (\(data.count / 1_000_000) MB).")
        }
        guard let image = UIImage(data: data), image.cgImage != nil else {
            throw MangalateError("Dữ liệu ảnh không đọc được.")
        }
        return image
    }
}
