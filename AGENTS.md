# AGENTS.md — Workspace app iOS (build trên Linux bằng xtool, cài qua Ksign)

Trả lời bằng tiếng Việt. Máy là **Ubuntu, không có Xcode/macOS**: mọi app iOS ở đây build bằng
SwiftPM + xtool trên Linux, cài lên iPhone qua **Ksign** (app ký/cài IPA chạy trên máy, dùng chứng chỉ;
không giới hạn số app / App ID như Apple ID miễn phí). Không làm được app macOS.

## Cấu trúc

```
~/Documents/Code/ios/
├── toolkit/                 — đồ dùng chung, KHÔNG chép sang từng app
│   ├── build_app.sh <app> [clean]  — pipeline build: toolchain → sync SDK → bump version → xtool → icon → source/serve
│   ├── bump_version.sh <app>       — tăng <app>/VERSION, ghi vào <app>/Info.plist
│   ├── patch_icon.sh <ipa> <png>   — chèn icon (resize từ 1024×1024) vào IPA
│   ├── build_all.sh [apps|mods]    — build mọi app + mod, bỏ qua mục trong build-exclude.txt
│   ├── sidestore_source.py         — gộp apps/*/xtool/*.ipa + mods/*/out/*.ipa thành sidestore/source.json
│   ├── dev_server.py, serve_sidestore.sh [stop] — server LAN port 8765 (+ POST /clipboard; POST /log → .state/iphone_log.txt)
│   ├── publish_github.sh [--dry-run] — sinh source.json trỏ GitHub Releases + push + upload IPA (URL cố định cho Ksign)
│   ├── pull_app_logs.sh <bundleID> — iPhone cắm USB: chép Documents/Logs của app → .state/logs/<bundleID>/ (cần ifuse)
│   ├── xtool.AppImage              — xtool 1.22.2
│   └── xtool-src/                  — clone mã nguồn xtool để tra cứu (PackLib/ = cách đóng gói)
├── sidestore/               — output phục vụ LAN (sinh tự động, đừng sửa tay)
├── source/                  — source.json đã publish lên GitHub (sinh bởi publish_github.sh)
├── .state/                  — pid/log server, iphone_clipboard.txt
├── build-exclude.txt        — tên/đường dẫn KHÔNG build tự động (CI + build_all.sh)
├── .github/workflows/build.yml — CI build app + mod, upload IPA artifact (publish tay)
├── apps/<App>/              — mỗi app một thư mục
└── mods/<Mod>/              — mod IPA có sẵn (tiêm dylib), pipeline riêng
```

App hiện có: `apps/GameHub` (chơi game PC trên iPhone; dữ liệu build game nằm trong `apps/GameHub/workspace/`),
`apps/AdsBlocker` (Safari Web Extension chặn quảng cáo),
`apps/Mangalate` (Safari Web Extension dịch truyện tranh: Vision OCR trên máy, chỉ gửi text lên Gemini, dán bản dịch
đè lên bong bóng thoại),
`apps/MyDrive` (client Google Drive: upload nền bằng background URLSession, đồng bộ thư mục).

Mod: `mods/youtube` (chặn quảng cáo + phát nền/PiP cho YouTube 21.44.4: tiêm dylib ObjC++ vào IPA đã giải mã),
`mods/cherrytale` (game IL2CPP — mod tĩnh, **loại trừ** khỏi build tự động/CI). Mod cần IPA gốc (không nằm trong repo):
`IPA=/đường/dẫn/…` hoặc `IPA_URL=…` (file `mods/<mod>/source.env`, không commit). Chi tiết: `mods/youtube/README.md`.

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
├── VERSION           — số build, bắt đầu 0 (tăng 1 mỗi lần build)
├── AppIcon.png       — 1024×1024
├── build.sh          — bọc mỏng: `cd "$(dirname "$0")"; exec ../../toolkit/build_app.sh . "$@"`
├── .gitignore        — /.build /xtool *.ipa
└── Sources/<App>/    — `@main struct …: App` (SwiftUI)
```

Version hiển thị = `(1 + VERSION/100).(VERSION % 100)` với minor **luôn 2 chữ số, tối đa 99**:
build 99 → `1.99`, build 100 → `2.00`, build 199 → `2.99`, build 200 → `3.00`. CFBundleVersion
vẫn là số build tăng dần (Ksign dựa vào đó để nhận cập nhật).

Build: `apps/<App>/build.sh` (lần đầu hoặc sau khi di chuyển thư mục: `build.sh clean`). Kết quả `apps/<App>/xtool/<Product>.ipa`,
`sidestore/source.json` tự có app mới, server LAN tự bật.

## Mod IPA (tiêm dylib)

`mods/<Mod>/` là mod cho IPA **có sẵn** (không build từ SwiftPM): pipeline riêng trong `mods/<Mod>/build.sh`
(giải nén IPA → biên dịch dylib arm64 bằng clang + Darwin SDK → chèn `LC_LOAD_DYLIB` → sửa Info.plist → ký `ldid` → zip).
IPA gốc không nằm trong repo: đặt `IPA=/đường/dẫn/…` hoặc `IPA_URL=…` trong `mods/<Mod>/source.env` (không commit).

```bash
mods/youtube/build.sh          # → mods/youtube/out/YouTube_mod_<ver>.ipa (+ .deb)
mods/youtube/build.sh --check  # exit 3 nếu thiếu IPA gốc (build_all.sh dùng để skip)
```

- **Không vá code trong `__TEXT`**: bản ký Ksign có `CS_HARD|CS_KILL` — sửa code sau khi ký thì kernel giết app.
  Hook bằng method swizzling ObjC runtime trong dylib; chỉ chèn `LC_LOAD_DYLIB` vào **padding header**
  (`tools/inject_dylib.py`), không dựng lại `__LINKEDIT` (LIEF `add_library` làm hỏng bind/chained fixups của app lớn).
- `toolkit/build_all.sh [apps|mods]` build mọi app + mod; `build-exclude.txt` (gốc repo) loại trừ mục không build tự động
  (hiện: `cherrytale` — cần IPA 1,4 GB + dump.cs sinh trên máy).
- CI: `.github/workflows/build.yml` build app + mod, upload artifact `ipa-<run>`; publish tay bằng workflow_dispatch
  (`publish=true`). IPA YouTube gốc giữ ở repo private `doanhvanvu82/ios-mod-sources`, CI tải bằng
  `secrets.SOURCE_IPA_TOKEN` (hoặc đặt `secrets.YOUTUBE_IPA_URL`).
- Log trên máy: dylib ghi `Documents/Logs/<ngày>.log`, lấy bằng `toolkit/pull_app_logs.sh <bundleID>`.
- **Mod IPA có appex: đổi bundle id của appex theo app chính và xoá mọi `_CodeSignature` cũ.**
  Apple bắt buộc bundle id appex bắt đầu bằng bundle id app (`<bid>.<suffix>`); để `com.google.ios.youtube.*`
  khi app chính đã đổi thành `vn.vudv.youtube.mod` thì `installd` từ chối cài. `_CodeSignature` của từng
  appex/framework còn chứa hash bản gốc cũng làm hỏng chữ ký. Xem `mods/youtube/build.sh` › `patch_app`.

## Cài lên iPhone

Cài bằng **Ksign** (đã cài trên iPhone): ký lại IPA bằng chứng chỉ rồi cài — không giới hạn số app/App ID.
Hai cách đưa bản build sang máy:

1. **Qua source**: một lần Ksign → Sources → **+** → `http://<IP máy tính>:8765/source.json` (build in ra URL; cùng Wi-Fi)
   hoặc URL GitHub ở README; mỗi lần build mở source → tải/cài bản mới. App mới cũng nằm trong source.
2. **Qua file**: tải `<App>.ipa` (LAN hoặc GitHub Releases) rồi import vào Ksign để ký và cài.

Chứng chỉ dùng để ký có thể bị thu hồi → app không mở được, phải ký/cài lại.

`xtool install` / `xtool dev run` qua USB **không dùng được** (đăng nhập Apple bằng mật khẩu bị từ chối `-80046`).

## Giới hạn / bẫy đã gặp

- Ksign ký bằng chứng chỉ nên không có hạn mức 3 app / 10 App ID của Apple ID miễn phí; đổi lại chứng chỉ có thể bị
  thu hồi → app ngừng mở, phải ký/cài lại.
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
- Safari Web Extension sau khi cập nhật app qua Ksign: Safari có thể giữ extension cũ đến khi nạp lại → lỗi
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
- **iOS 27.2 + app cài sideload: chọn thư mục/tệp ngoài container luôn trả rỗng.** `UIDocumentPickerViewController` (mọi
  biến thể API, kể cả chọn file) log `didPickDocumentURLs … empty array` + `Could not resolve bookmark. Cocoa 257`; app
  App Store (a-Shell) và app cài bằng Xcode thì chọn bình thường (xem seedds/nxnative#1148). Không sửa được bằng code hay
  SDK/Info.plist — dùng thư mục mặc định trong container (`Documents/GameHub/Games`, xem `apps/GameHub`); giữ bản gốc dữ
  liệu người dùng ở ngoài app và copy vào container thay vì move. MyDrive 1.24 thực tế chọn được file lẫn folder từ
  picker (app sideload) — ghi chép ban đầu này có thể chỉ đúng với một số nguồn mở (Files app nội bộ…).
- **`UIDocumentPickerViewController` chọn THƯ MỤC phải `asCopy: false`** — `asCopy: true` với content type `.folder`
  ném exception ngay khi tạo picker → app crash. File (`.data`) mới được copy; folder chỉ được mở tại chỗ (nhận URL
  security-scoped, caller tự copy cả cây rồi `stopAccessingSecurityScopedResource`, đừng xoá URL đó — là thư mục thật
  của người dùng). Xem `apps/MyDrive` › `FolderDocumentPicker`, `importDroppedFolder`.
