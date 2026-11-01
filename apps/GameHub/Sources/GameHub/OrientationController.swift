import UIKit
import Combine

/// Quản lý hướng màn hình TOÀN APP — nguồn sự thật duy nhất.
///
/// ⚠️ NHỮNG BÀI HỌC ĐÃ GẶP THẬT TRÊN iPhone (đừng lặp lại):
///
/// 1. **`UIViewController.attemptRotationToDeviceOrientation()` PHẢI BỎ.**
///    Hàm này ép app theo **hướng cầm tay của thiết bị**. Nếu user đang cầm
///    dọc mà app vừa xoay ngang, hàm này kéo app về dọc ngay lập tức →
///    triệu chứng "vào game xoay ngang được, nhưng thoát ra lại kẹt dọc".
///    (iOS 16+ cũng đã deprecated hàm này.)
///
/// 2. **`requestGeometryUpdate` phải xin CHỈ hướng muốn đến.**
///    Nếu tập xin chứa cả hướng hiện tại, iOS coi như "đã hợp lệ" → không
///    xoay gì cả.
///
/// 3. **Mask khi chơi game = CHỈ 2 hướng ngang.** Nếu mask có cả `.portrait`,
///    iOS sẽ tự quay về dọc theo hướng thiết bị (ngay cả khi user không
///    muốn).
///
/// 4. **iOS hay bỏ qua `requestGeometryUpdate` khi scene vừa trải qua
///    transition** (đóng/mở `fullScreenCover`). Phải thử lại nhiều lần cho
///    tới khi scene thực sự xoay.
///
/// 5. ⚠️ **THỨ TỰ QUAN TRỌNG — đây là lý do log báo
///    "Supported: portrait":**
///    `setNeedsUpdateOfSupportedInterfaceOrientations()` KHÔNG áp dụng mask
///    ngay — nó lên lịch cho lượt layout kế tiếp. Nếu gọi
///    `requestGeometryUpdate` ngay sau đó, VC vẫn còn mask CŨ (`.portrait`)
///    → iOS trả lỗi "None of the requested orientations are supported by the
///    view controller. Requested: landscapeLeft, landscapeRight; Supported:
///    portrait" → lần đó xoay thất bại.
///    → Phải **đợi 1 runloop turn + vài chục ms** rồi mới xin geometry.
///
/// 6. **Khi app bị kill, `onDisappear` KHÔNG chạy.** `OrientationLock.mask`
///    giữ nguyên giá trị cũ → khi mở lại app, scene mới ở hướng dọc nhưng
///    mask lại là landscape-only → app "kẹt" dọc, không xoay được.
///    → cần ép về dọc khi app vào foreground ở màn danh sách.
///
/// 7. **Hai lệnh xoay chồng nhau sẽ đánh nhau.** `forcePortrait()` lúc app
///    vừa mở có thể còn "đang bay" khi user bấm vào game → request portrait
///    đến sau request landscape → app bị kéo về dọc.
///    → `generation` đảm bảo lệnh cũ bị bỏ qua khi có lệnh mới.
@MainActor
final class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    /// Hướng user muốn (nguồn sự thật duy nhất).
    private(set) var desired: UIInterfaceOrientationMask = .portrait

    /// Đếm số lần đổi yêu cầu — mọi vòng thử cũ sẽ dừng khi lệnh mới đến.
    private var generation = 0
    private var retryTask: Task<Void, Never>?

    private init() {}

    // MARK: - Tiện ích

    /// Scene đang chạy (ưu tiên foreground active).
    static func foregroundScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
    }

    /// `true` nếu hướng hiện tại nằm trong tập mask cho phép.
    static func satisfies(_ o: UIInterfaceOrientation, _ mask: UIInterfaceOrientationMask) -> Bool {
        if mask.contains(.landscapeLeft) || mask.contains(.landscapeRight) {
            if o == .landscapeLeft || o == .landscapeRight { return true }
        }
        if mask.contains(.portrait) {
            if o == .portrait || o == .portraitUpsideDown { return true }
        }
        if mask.contains(.portraitUpsideDown) && o == .portraitUpsideDown { return true }
        return false
    }

    /// Tên hướng đọc được (cho log).
    static func name(_ o: UIInterfaceOrientation) -> String {
        switch o {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        default: return "unknown(\(o.rawValue))"
        }
    }

    /// Tên mask đọc được (cho log).
    static func name(_ mask: UIInterfaceOrientationMask) -> String {
        var parts: [String] = []
        if mask.contains(.portrait) { parts.append("portrait") }
        if mask.contains(.portraitUpsideDown) { parts.append("upsideDown") }
        if mask.contains(.landscapeLeft) { parts.append("left") }
        if mask.contains(.landscapeRight) { parts.append("right") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    // MARK: - Hành động

    /// Đặt hướng mong muốn và ép app xoay tới đó (tự thử lại nhiều lần).
    ///
    /// - Parameter mask: tập hướng được phép. Muốn ÉP thì truyền đúng 1 hướng
    ///   (vd `.portrait` hoặc `[.landscapeLeft, .landscapeRight]`).
    func setDesired(_ mask: UIInterfaceOrientationMask, reason: String) {
        desired = mask
        OrientationLock.mask = mask
        generation += 1
        let g = generation
        retryTask?.cancel()
        AppLog.info("Xoay: yêu cầu \(Self.name(mask)) — \(reason)")
        retryTask = Task { [weak self] in
            await self?.run(mask: mask, generation: g)
        }
    }

    /// Ép về dọc (màn danh sách / app vừa mở).
    func forcePortrait(reason: String) {
        setDesired(.portrait, reason: reason)
    }

    /// Ép về ngang (đang chơi game).
    func forceLandscape(reason: String) {
        setDesired([.landscapeLeft, .landscapeRight], reason: reason)
    }

    /// Huỷ mọi lệnh xoay đang chạy.
    func cancel() {
        retryTask?.cancel()
        retryTask = nil
        generation += 1
    }

    // MARK: - Vòng thử

    private func run(mask: UIInterfaceOrientationMask, generation g: Int) async {
        // Mỗi lần thử cách nhau một chút; lần đầu đợi cho transition
        // fullScreenCover commit rồi mới xin xoay.
        let delays: [UInt64] = [250_000_000, 400_000_000, 600_000_000,
                                900_000_000, 1_300_000_000, 1_800_000_000,
                                2_500_000_000]
        for (i, delay) in delays.enumerated() {
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled || g != generation { return }

            guard let scene = Self.foregroundScene() else { continue }
            let current = scene.interfaceOrientation

            // Đã đúng hướng → dừng, khỏi xin thêm.
            if Self.satisfies(current, mask) {
                AppLog.ok("Xoay: đã đúng hướng (\(Self.name(current))) — dừng ở lần \(i + 1)")
                return
            }

            await request(scene: scene, mask: mask, label: "lần\(i + 1)")
        }

        if let scene = Self.foregroundScene() {
            AppLog.warn("Xoay: hết lượt thử, hướng hiện tại = \(Self.name(scene.interfaceOrientation)) (mong muốn \(Self.name(mask)))")
        } else {
            AppLog.warn("Xoay: hết lượt thử, không có scene")
        }
    }

    /// Xin iOS xoay — CÓ THỨ TỰ ĐÚNG (bài học #5).
    private func request(scene: UIWindowScene,
                         mask: UIInterfaceOrientationMask,
                         label: String) async {
        // (a) Đặt mask toàn cục TRƯỚC.
        OrientationLock.mask = mask

        // (b) ⚠️ Báo cho **MỌI** view controller trong cây biết mask đổi.
        //
        //     Đây là lý do log báo:
        //     "None of the requested orientations are supported by the view
        //      controller. Requested: landscapeLeft, landscapeRight;
        //      Supported: portrait"
        //
        //     Vì `fullScreenCover` của SwiftUI tạo MỘT `UIHostingController`
        //     RIÊNG (present VC). Khi game mở, mask lúc đó còn là `.portrait`
        //     → present VC ghi nhớ mask cũ. iOS hỏi **present VC** (không
        //     phải root) khi xử lý geometry update → nó trả về portrait →
        //     request bị từ chối.
        //
        //     → Phải gọi `setNeedsUpdateOfSupportedInterfaceOrientations()`
        //       trên root VC **và** mọi VC đang present (đệ quy).
        notifyOrientationChange(in: scene)

        // (c) ⚠️ Đợi 1 runloop turn + 40ms để VC thực sự có mask mới.
        //     `setNeedsUpdateOfSupportedInterfaceOrientations()` chỉ LÊN
        //     LỊCH cho lượt layout kế tiếp, không áp dụng tức thì.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 60_000_000)
        if Task.isCancelled { return }

        // (d) Giờ mới xin geometry update.
        AppLog.info("Xoay[\(label)]: trước=\(Self.name(scene.interfaceOrientation)), xin \(Self.name(mask))")
        Self.dumpMasks()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            AppLog.ok("Xoay[\(label)] xong → \(Self.name(scene.interfaceOrientation)) (\(error.localizedDescription))")
        }

        // (e) Log trạng thái thực tế sau 0.4s để đối chiếu.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let b = scene.screen.bounds
            AppLog.info("Xoay[\(label)] 0.4s sau: \(Self.name(scene.interfaceOrientation)) màn=\(Int(b.width))x\(Int(b.height))")
        }
    }

    /// Báo mask mới cho MỌI VC trong cây (root + các VC đang present).
    private func notifyOrientationChange(in scene: UIWindowScene) {
        var count = 0
        for window in scene.windows {
            var vc: UIViewController? = window.rootViewController
            while let current = vc {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                count += 1
                vc = current.presentedViewController
            }
        }
        AppLog.info("Xoay: đã báo mask mới cho \(count) view controller")
    }

    /// Log mask THẬT của từng VC — dùng để chẩn đoán vì sao iOS báo
    /// "Supported: portrait" dù app đã đặt mask landscape.
    static func dumpMasks() {
        guard let scene = foregroundScene() else { return }
        var lines: [String] = []
        for window in scene.windows {
            var vc: UIViewController? = window.rootViewController
            while let current = vc {
                let m = current.supportedInterfaceOrientations
                lines.append("\(type(of: current))=\(name(m))")
                vc = current.presentedViewController
            }
        }
        AppLog.info("Xoay: mask từng VC → \(lines.joined(separator: " | "))")
    }
}
