---
description: "Mod YouTube: bundle id gốc + không đổi CFBundleVersion (clientVersion)"
evidence:
  - path: "mods/youtube/build.sh"
    quote: "KHÔNG đổi CFBundleVersion/CFBundleShortVersionString: YouTube gửi chúng"
  - path: "mods/youtube/build.sh"
    quote: "if [ -z \"${SUFFIX+x}\" ]; then SUFFIX=\"\"; fi"
  - path: "mods/youtube/README.md"
    quote: "server chỉ chấp nhận version thật của\nbản app. Version lạ (vd epoch) → mọi API trả 404"
---
Mod YouTube phải giữ bundle id gốc `com.google.ios.youtube` để đăng nhập Google (id lạ bị chặn "không thể xác nhận ứng dụng là an toàn"). Lỗi không tải được trang chủ/video (skeleton, API trả 404) KHÔNG do bundle id mà do `CFBundleVersion` bị bump thành epoch: app gửi nó làm InnerTube `clientVersion`; chỉ version thật `21.44.4` được chấp nhận (HTTP 200), epoch/lạ → 404. `build.sh` giờ không đụng version.
