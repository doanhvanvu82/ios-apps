# YouTube — mod (chặn quảng cáo + phát nền/PiP)

Tiêm dylib ObjC++ vào IPA YouTube **đã giải mã** (bản dump từ thiết bị), bật:

- **Chặn quảng cáo**: theo cách YTLite — **không decorate context quảng cáo khi
  gửi InnerTube** (`YTAdsInnerTubeContextDecoratorImpl` và
  `YTAccountScopedAdsInnerTubeContextDecorator`: `decorateContext:serviceType:`,
  `decorateContextWithAdShieldSignals:`, `decorateContextWithIDFA:`) để server
  không trả ad slot/preroll. Chặn bổ sung phía client cho slot/cell đã lỡ nhận:
  hàm `void` của pipeline (`executeWithCommand:`, `didReceiveCommand:`,
  `didReceiveAdSlots:`, `lifecycleDidStartForAdSlots:`,
  `didReceiveAdBreakResponse:`) và cell feed (`didLoadRenderer:`,
  `didBindSlotData:layoutData:`) bỏ thân hàm; getter danh sách trả `[]`;
  `adPlayerResponse` trả nil. Các class ad tải lười nên thử cài lại mỗi 2 giây
  (20 giây đầu) và mỗi lần về foreground (log `ads: OK`, `ads: CHẶN`).
  **Bẫy**: không trả nil từ hàm `init`/`create`/`slotFrom…` trả object
  (`YTAdSlot initWithSlotID…`, `YTSlotFactoryImpl.slotFromAdSlotMetadata…`) —
  caller dùng ngay → `EXC_BAD_ACCESS` tại `objc_retain`.
- **Menu YT**: hiện `YT <phiên bản app> · mod <MOD_VERSION>` và `build <nhãn giờ>`
  để biết đang chạy bản mới hay cũ (version app luôn là `21.44.4`).
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
./build.sh                 # → out/YouTube_orig_21.44.4.ipa (giữ bundle id gốc)
SUFFIX=mod ./build.sh      # → đổi id vn.vudv.youtube.mod, cài song song YouTube gốc
./build.sh --check         # exit 0 nếu có IPA nguồn, 3 nếu thiếu (build_all dùng)

# hoặc build cùng mọi app:
toolkit/build_all.sh mods  # bỏ qua mục trong build-exclude.txt
```

Bundle id mặc định **giữ nguyên** `com.google.ios.youtube` (cài đè YouTube gốc).
Đây là điều kiện để đăng nhập Google: app gửi bundle id lên máy chủ, id lạ bị
chặn với "Không thể đăng nhập … Google không thể xác nhận rằng ứng dụng này là
an toàn". Đổi id cũng làm trang chủ/video không tải được (skeleton mãi) vì
InnerTube từ chối phục vụ app không rõ nguồn gốc.

`SUFFIX=mod` đổi thành `vn.vudv.youtube.mod` để cài **song song** YouTube gốc —
đổi lại **không đăng nhập được Google**. `.deb` chỉ dùng cho máy jailbreak.

Build **không đổi** `CFBundleVersion`/`CFBundleShortVersionString`: YouTube gửi
chúng làm `clientVersion` tới InnerTube, server chỉ chấp nhận version thật của
bản app. Version lạ (vd epoch) → mọi API trả 404 → trang chủ/video chỉ có
skeleton (đã kiểm chứng: `clientVersion=21.44.4` → HTTP 200, epoch → 404).
Muốn cài bản mới thì gỡ app trong Ksign trước rồi cài lại.

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

## Bundle id

Mặc định **giữ nguyên** `com.google.ios.youtube`. `SUFFIX=mod` đổi thành
`vn.vudv.youtube.mod` (khi đó `build.sh` cũng đổi bundle id của 5 appex theo
prefix mới — bắt buộc, nếu không `installd` từ chối cài). Build luôn xoá **mọi**
`_CodeSignature`/`SC_Info` (app chính, appex, framework widevine) — CodeResources
của bản Apple gốc làm iOS báo chữ ký tài nguyên sai.

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
nằm trong repo (133 MB, bản quyền) và repo này public, nên IPA được giữ ở
**repo private `doanhvanvu82/ios-mod-sources`** (release `sources`). Workflow
tải về bằng `gh release download` với secret **`SOURCE_IPA_TOKEN`** (PAT có
quyền đọc repo đó) rồi đặt `IPA=…`; không có secret thì bước tải bị bỏ qua và
mod bị `skip (thiếu IPA gốc)`.

Cách khác: đặt secret `YOUTUBE_IPA_URL` (URL tải công khai) — `build.sh` tự
`curl` về `work/`.

Publish lên Releases chỉ chạy tay: `workflow_dispatch` → `publish=true`.
