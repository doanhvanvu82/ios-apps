# AGENTS.md — Workspace app iOS (build trên Linux bằng xtool, cài qua SideStore)

Trả lời bằng tiếng Việt. Máy là **Ubuntu, không có Xcode/macOS**: mọi app iOS ở đây build bằng
SwiftPM + xtool trên Linux, cài lên iPhone qua SideStore (Apple ID miễn phí). Không làm được app macOS.

## Cấu trúc

```
~/Documents/Code/ios/
├── toolkit/                 — đồ dùng chung, KHÔNG chép sang từng app
│   ├── build_app.sh <app> [clean]  — pipeline build: toolchain → sync SDK → bump version → xtool → icon → SideStore
│   ├── bump_version.sh <app>       — tăng <app>/VERSION, ghi vào <app>/Info.plist
│   ├── patch_icon.sh <ipa> <png>   — chèn icon (resize từ 1024×1024) vào IPA
│   ├── sidestore_source.py         — gộp apps/*/xtool/*.ipa thành sidestore/source.json
│   ├── dev_server.py, serve_sidestore.sh [stop] — server LAN port 8765 (+ POST /clipboard; POST /log → .state/iphone_log.txt)
│   ├── publish_github.sh <app>     — sinh source.json trỏ GitHub Releases + push + upload IPA (URL cố định cho SideStore)
│   ├── pull_app_logs.sh <bundleID> — iPhone cắm USB: chép Documents/Logs của app → .state/logs/<bundleID>/ (cần ifuse)
│   ├── xtool.AppImage              — xtool 1.22.2
│   └── xtool-src/                  — clone mã nguồn xtool để tra cứu (PackLib/ = cách đóng gói)
├── sidestore/               — output phục vụ LAN (sinh tự động, đừng sửa tay)
├── source/                  — source.json đã publish lên GitHub (sinh bởi publish_github.sh)
├── .state/                  — pid/log server, iphone_clipboard.txt
└── apps/<App>/              — mỗi app một thư mục
```

App hiện có: `apps/GameHub` (chơi game PC trên iPhone; dữ liệu build game nằm trong `apps/GameHub/workspace/`),
`apps/AdsBlocker` (Safari Web Extension chặn quảng cáo),
`apps/Mangalate` (Safari Web Extension dịch truyện tranh: Vision OCR trên máy, chỉ gửi text lên Gemini, dán bản dịch
đè lên bong bóng thoại).

## Môi trường build (đã cài sẵn)

- Toolchain: `~/swift-dev` (Swift 6.5-dev snapshot; SDK Xcode 27.1 cần clang ≥ 22). Swift **không** nằm trong `PATH`;
  đổi bằng `IOS_TOOLCHAIN`.
- Darwin SDK: `~/.swiftpm/swift-sdks/darwin.artifactbundle` (`build_app.sh` tự đồng bộ `clang/include`).
- `python3` + Pillow (icon), `zip`/`unzip`. Biến môi trường khác: `XTOOL`, `SIDESTORE_PORT`, `APP_ICON`.

## Tạo app mới

```
apps/<App>/
├── Package.swift     — swift-tools 6.0, platforms [.iOS(.v17)], đúng 1 library product cho app
│                       (+ 1 product cho mỗi app extension); `.swiftLanguageMode(.v5)` nếu vướng strict concurrency
├── xtool.yml         — version: 1, bundleID: vn.vudv.<app-lowercase>, infoPath: Info.plist
│                       (+ product:/extensions: nếu có extension — xem toolkit/xtool-src/Documentation/xtool.docc/Appex.md)
├── Info.plist        — CFBundleDisplayName, các key riêng; version do bump_version.sh ghi
├── <Ext>-Info.plist  — (nếu có extension) đặt tên đuôi `-Info.plist` để bump_version.sh ghi cùng version với app
├── VERSION           — số build, bắt đầu 0
├── AppIcon.png       — 1024×1024
├── build.sh          — bọc mỏng: `cd "$(dirname "$0")"; exec ../../toolkit/build_app.sh . "$@"`
├── .gitignore        — /.build /xtool *.ipa
└── Sources/<App>/    — `@main struct …: App` (SwiftUI)
```

Build: `apps/<App>/build.sh` (lần đầu hoặc sau khi di chuyển thư mục: `build.sh clean`). Kết quả `apps/<App>/xtool/<Product>.ipa`,
`sidestore/source.json` tự có app mới, server LAN tự bật.

## Cài lên iPhone

1. Một lần: SideStore → Sources → + → `http://<IP máy tính>:8765/source.json` (build in ra URL; cùng Wi-Fi).
2. Mỗi lần build: SideStore → My Apps → làm mới → Update. App mới: Browse → source "iOS apps (máy nhà)".

`xtool install` / `xtool dev run` qua USB **không dùng được** (đăng nhập Apple bằng mật khẩu bị từ chối `-80046`).

## Giới hạn / bẫy đã gặp

- Apple ID miễn phí: tối đa 3 app active (tính cả SideStore), 10 App ID / 7 ngày; mỗi app extension tốn thêm 1 App ID.
- Không có asset catalog → icon chèn sau build (`patch_icon.sh`); không có storyboard → dùng `UILaunchScreen` trong Info.plist.
- Dependency SwiftPM khai báo system library (vd `zlib`) sẽ link nhầm thư viện Linux → vendor vào `Vendor/` và bỏ phần đó
  (xem `apps/GameHub/Package.swift`).
- Không chạy được app/simulator trên máy này: kiểm tra bằng build thành công + `unzip -l` IPA; hành vi thực tế do người dùng thử trên iPhone.
  Lỗi chỉ xảy ra trên máy thật: ghi log ra file trên máy (mẫu `apps/AdsBlocker/Sources/AdsBlocker/AppLog.swift`: Documents/Logs/<ngày>.log,
  Info.plist `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`), người dùng cắm USB → `toolkit/pull_app_logs.sh <bundleID>`
  rồi đọc `.state/logs/<bundleID>/`. Cách cũ (app POST log về `dev_server.py` `/log`, xem `apps/GameHub/build.sh`) cần cùng Wi-Fi.
- WKWebView chưa gắn vào cửa sổ: WebKit hoãn tải trang, lượt tải dở hoàn tất muộn và đè lên điều hướng sau đó. Webview tải trước
  (ẩn) phải nằm trong cửa sổ (vd dưới webview khác) và chờ `didFinish` (xem `apps/AdsBlocker` › player dự phòng).
- WKWebView + PiP: khoá máy lúc video đang PiP thì mở khoá xong trang player kẹt (không nhận chạm, video
  `webkitPresentationMode` vẫn `picture-in-picture`), chỉ thoát được ở lần đưa app lên foreground sau. Vẫn phải vào PiP khi khoá
  (đó là thứ giữ tiếng nền), nên ở foreground phải kiểm tra + thử thoát PiP lại nhiều lần rồi mới tải lại trang; lúc khoá iOS báo
  `didBecomeActive` chớp nhoáng → mọi việc khôi phục phải hoãn ~0,6 giây và huỷ khi app rời đi, **không tải lại trang khi đang ở nền**
  (mất tiếng nền). Xem `apps/AdsBlocker` › `scheduleRecovery`, `recoverPlayer`.
- Sau khi di chuyển thư mục app phải `build.sh clean` (`.build` lưu đường dẫn tuyệt đối).
- **App extension (appex) bị rỗng code**: xtool dựng appex từ stub chỉ trỏ entry point vào `_NSExtensionMain`, không tham
  chiếu code của target extension → linker bỏ sạch, iOS báo `RBSLaunchRequest … Launch failed`. Target extension phải có
  `linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_OBJC_CLASS_$_<PrincipalClass>"])]` và lớp principal khai
  báo `@objc(<PrincipalClass>)`. Kiểm tra sau build: `~/swift-dev/usr/bin/llvm-nm <appex>/<binary> | wc -l` phải hàng trăm symbol, không phải 3.
- Safari Web Extension sau khi cập nhật app qua SideStore: Safari có thể giữ extension cũ đến khi nạp lại → lỗi
  `RBSLaunchRequest … Launch failed` khi gọi native. Cần thử lại + nút `browser.runtime.reload()` trong popup
  (xem `apps/AdsBlocker`); không được thì đóng hẳn Safari.
- Safari Web Extension cần dữ liệu lớn (bộ lọc): sinh lúc build bằng script trong `tools/` của app (xem `apps/AdsBlocker/tools/build-filters.mjs`,
  gọi trong `build.sh` trước `build_app.sh`), thêm thư mục vào `xtool.yml › extensions › resources`.
- Safari Web Extension: API `browser.*` ném lỗi kiểm tra tham số **ngay lúc gọi** ("Invalid call to …"), không trả promise bị
  từ chối → `browser.x(...).catch(...)` không bắt được; dùng `try { await browser.x(...) }` (helper `attempt` trong
  `apps/AdsBlocker/WebExtension/background.js`). declarativeNetRequest: một rule hỏng làm hỏng cả lệnh `updateDynamicRules`;
  `requestDomains` phải ASCII, không rỗng; `regexFilter` không hỗ trợ nhóm lựa chọn `(a|b)` → dùng nhiều rule `urlFilter`.
- Safari Web Extension: `storage.session` trên iOS báo "Exceeded storage quota" dù chỉ vài KB → dùng `storage.local`.
- Safari Web Extension: Safari đọc background/content script không có charset thành Latin-1 → file JS có chữ không phải ASCII
  phải bắt đầu bằng BOM UTF-8 (xem `apps/AdsBlocker/tests/encoding.test.js`).
