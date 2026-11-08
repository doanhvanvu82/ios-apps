---
description: "Mod YouTube phải giữ bundle id gốc mới đăng nhập/tải video được"
evidence:
  - path: "mods/youtube/build.sh"
    quote: "Giữ bundle id gốc là bắt buộc để đăng nhập Google: YouTube gửi bundle id lên"
  - path: "mods/youtube/build.sh"
    quote: "if [ -z \"${SUFFIX+x}\" ]; then SUFFIX=\"\"; fi"
  - path: "mods/youtube/README.md"
    quote: "Bundle id mặc định **giữ nguyên** `com.google.ios.youtube` (cài đè YouTube gốc)."
---
Mod YouTube phải giữ bundle id gốc `com.google.ios.youtube` (mặc định của `mods/youtube/build.sh`). Đổi sang `vn.vudv.youtube.mod` thì Google chặn đăng nhập ("không thể xác nhận ứng dụng là an toàn") và InnerTube không trả trang chủ/video — màn hình skeleton, tắt chặn quảng cáo không cứu được. Log syslog có `I-COR000008` bundle id lệch `GoogleService-Info.plist`. Chỉ dùng `SUFFIX=mod` khi chấp nhận không đăng nhập được.
