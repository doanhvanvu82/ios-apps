import SwiftUI

/// Capsule kính mờ kiểu "liquid glass" của iOS 26 (Files/Drive đang dùng):
/// ưu tiên API chính thức `.glassEffect(.regular.interactive)`; iOS cũ hơn
/// fallback về material thường. Dùng cho thanh hành động selection.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
    }
}
