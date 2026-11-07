# YouTube — mod (chặn quảng cáo + phát nền/PiP)

Tiêm dylib ObjC++ vào IPA YouTube **đã giải mã** (bản dump từ thiết bị), bật:

- **Chặn quảng cáo**: trả `NO` cho các cờ monetized/preroll của `YTIPlayerResponse`,
  chặn `YTAdBreakServiceImpl` request ad và bỏ qua toàn bộ pipeline dựng slot ad.
- **Phát nền / PiP**: ép `isBackgroundableByUserSettings` /
  `isPlayableInBackground` / `isPlayableInPictureInPicture` = `YES`,
  `HAMPlayer.setAllowsBackgroundPlayback:` = `YES`, tắt `isPipOffByDefault`.
- Menu nổi nhỏ (nút **YT** góc phải dưới) để bật/tắt từng tính năng, lưu vào
  `NSUserDefaults` suite `vn.vudv.youtube.mod`.

Đây là mod **client-side** cho máy đã cài app qua Ksign. Không mở khoá tài khoản
YouTube Premium thật (server vẫn là nguồn sự thật); mục tiêu là bỏ quảng cáo và
giữ tiếng khi khoá máy như uYou/YouTube Reborn.

## Nội dung

```
mods/youtube/
├── build.sh              pipeline: IPA gốc → IPA đã tiêm dylib (+ .deb)
├── source.env.example    mẫu khai báo IPA nguồn (IPA= hoặc IPA_URL=)
├── src/
│   ├── common.h          khai báo chung
│   ├── config.mm         NSUserDefaults + log Documents/Logs/<ngày>.log
│   ├── hooks.h           bảng hook + API cài đặt
│   ├── hook_impls.mm     thân hook + YTM_HOOKS (class/selector/type encoding)
│   ├── hooks.mm          swizzling bằng ObjC runtime, đọc cấu hình
│   ├── menu.mm           menu nổi UIKit
│   └── main.mm           constructor → cài hook sau khi app launch
├── tools/inject_dylib.py chèn LC_LOAD_DYLIB vào padding header (không đụng LINKEDIT)
├── work/                 trung gian (gitignore)
└── out/                  IPA/deb (gitignore)
```

## Build

```bash
cd mods/youtube

# 1) đặt IPA nguồn (một lần) — chọn 1 trong 3:
cp source.env.example source.env && sửa IPA=/đường/dẫn/YouTube.ipa
export IPA=/đường/dẫn/YouTube.ipa
export IPA_URL=https://…/YouTube-21.44.4.ipa   # tải về work/ (CI)

# 2) build
./build.sh                 # → out/YouTube_mod_21.44.4.ipa (+ YouTubeMod_1.0.deb)
SUFFIX= ./build.sh         # giữ bundle id gốc com.google.ios.youtube
./build.sh --check         # exit 0 nếu có IPA nguồn, 3 nếu thiếu (build_all dùng)

# hoặc build cùng mọi app:
toolkit/build_all.sh mods  # bỏ qua mục trong build-exclude.txt
```

Bundle id mặc định `vn.vudv.youtube.mod` (cài song song với YouTube gốc, đăng
nhập lại Google). `.deb` chỉ dùng cho máy jailbreak.

Mỗi lần build tăng `CFBundleVersion` (YouTube ghi version dạng `21.44.4` nên
lần đầu dùng epoch giây, các lần sau +1) — Ksign dựa vào đó để nhận cập nhật;
tên IPA trong source cũng có build (`YouTubeMod-21.44.4-<build>.ipa`).

Toolchain: `~/swift-dev` (clang), Swift SDK Darwin (`~/.swiftpm/swift-sdks`),
`ld64.lld` của xtool toolset, `ldid` tải vào `work/tools`. Override bằng
`IOS_TOOLCHAIN`, `IOS_SDK`, `IOS_LD`, `LDID`. Trên macOS/CI có Xcode thì tự dùng
`xcrun` + `ldid_macosx_*` (không cần `IOS_TOOLCHAIN`).

## Cơ chế hook

- Tất cả class cần sửa đều là **ObjC** trong binary chính (`YouTube`), kể cả các
  class Swift chỉ cần `@objc`. Dylib dùng `class_replaceMethod` của runtime —
  **không vá trang `__TEXT`** như mod Unity IL2CPP (bản ký Ksign có
  `CS_HARD|CS_KILL`, sửa code sau khi ký thì kernel giết app).
- `tools/inject_dylib.py` chỉ chèn `LC_LOAD_DYLIB` vào **padding header**
  (1168 byte trống giữa load commands và `__text`). Không dựng lại `__LINKEDIT`
  (LIEF `add_library` làm đổi 4 MB LINKEDIT của binary 232 MB — rủi ro hỏng
  bind/chained fixups của app lớn).
- Mỗi hook khai báo type encoding lấy từ dump (`objc2.json`): khi build có thể
  so nhanh `B16@0:8`, `v40@0:8@16@?24@?32`… để phát hiện lệch ABI nếu dùng IPA
  khác bản 21.44.4. Log ghi cảnh báo nếu encoding runtime khác dump.

## Danh sách hook

| Nhóm | Class | Selector |
|---|---|---|
| Ads | `YTIPlayerResponse` | `isMonetized`, `hasPrerollAds`, `isCuepointAdsEnabled`, `adsAllowReuse`, `isDAIEnabledPlayback`, `hasVideoAdTrackingRenderer` |
| Ads | `YTAdBreakServiceImpl` | `makeAdBreakRequest:responseBlock:errorBlock:` (+`retryEnabled:`) |
| Ads | `YTAdBreakResponseReceivedOpportunityAdapterImpl` | `buildAndRegisterSlotsFromAdBreakResponse:…`, `processThrottledAdBreakResponse:…` |
| Ads | `YTContentVideoPlayerResponseSlotOpportunityAdapterImpl` | `addPlayerBytesAndForecastingSlotsFromPlayerResponse:…` |
| Ads | `YTPlayerBytesDAISlotFulfillmentAdapter`, `YTPlayerBytesSlotFulfillmentAdapter` | `playerAdsFromAdBreakResponse:` |
| Ads | `YTPlayerBytesLayoutEnteredOpportunityAdapterImpl` | `inPlayerSlotFromPlayerBytesSlot:…` |
| Nền | `YTIPlayabilityStatus` | `isPlayableInBackground`, `isPlayableInPictureInPicture` |
| Nền | `YTPlayerResponse` | `isPipOffByDefault`, `isPlayableInPictureInPicture` |
| Nền | `HAMPlayer` | `setAllowsBackgroundPlayback:` |

Một số method getter rất ngắn (`ldrb w0,[x0,#x]; ret` — dưới 12 byte) không
swizzle an toàn, nên bỏ qua; nhóm đó không cần thiết vì đã hook getter lớn hơn
(`YTIPlayabilityStatus`, `YTPlayerResponse`) và setter `HAMPlayer`.
`YTBackgroundabilityPolicyImpl.isBackgroundableByUserSettings` cũng thuộc nhóm
này — cờ được bật qua `YTIPlayabilityStatus`.

## Log / debug trên iPhone

Mod ghi `Documents/Logs/<ngày>.log` (bật `UIFileSharingEnabled` nên lấy được
qua app Files), hoặc cắm USB:

```bash
toolkit/pull_app_logs.sh vn.vudv.youtube.mod
```

Log có dòng `hook OK`/`hook MISS` cho từng mục và cảnh báo nếu type encoding
runtime lệch với dump — gửi log lại để chỉnh hook.

## Đã kiểm chứng / chưa kiểm chứng

- Đã build thành công trên Linux: dylib arm64 (link `Foundation`, `UIKit`,
  `CoreFoundation`), IPA 130 MB có `LC_LOAD_DYLIB` đúng 1 lần, `__TEXT.__text`
  và `__LINKEDIT` không đổi so với IPA gốc (chỉ chèn 72 byte vào padding),
  `cryptid 0`, 5 appex được ký lại, dylib 294 symbol.
- **Chưa chạy trên iPhone**: hành vi thực tế (có hết quảng cáo, tiếng chạy khi
  khoá máy) phải thử trên máy. Nếu quảng cáo còn, xem log `hook MISS` và bổ
  sung selector vào `hook_impls.mm`.

## CI (GitHub Actions)

`.github/workflows/build.yml` build app + mod trên push/PR. IPA YouTube gốc không
nằm trong repo nên đặt secret **`YOUTUBE_IPA_URL`** (link tải IPA đã giải mã).
Publish lên Releases chỉ chạy tay: `workflow_dispatch` → `publish=true`.
