# AdsBlocker — Safari Web Extension chặn quảng cáo cho iPhone/iPad

Chặn quảng cáo trong Safari, đặc biệt là kiểu **bấm vào trang thì mở tab quảng cáo mới**. Khi trang vẫn còn
quảng cáo, người dùng có hai cách:

- **Chọn quảng cáo để ẩn**: tự chạm vào quảng cáo (giống "Ẩn mục gây xao nhãng" của Safari), rồi bấm **Ẩn**
  (xử lý ngay trên máy) hoặc **Ẩn bằng AI** (Gemini mở rộng rule để bắt cả các quảng cáo cùng loại).
- **Quét trang bằng AI**: Gemini tự tìm quảng cáo trên cả trang.

Rule được duyệt lưu theo site và tự áp dụng ở các lần sau mà không cần gọi AI nữa.

## Build & cài

```bash
cd ~/Documents/Code/ios/apps/AdsBlocker
./build.sh          # pipeline chung ../../toolkit/build_app.sh → xtool/AdsBlocker.ipa
```

1. Ksign → source **iOS apps (máy nhà)** (`http://<IP máy tính>:8765/source.json`) → ký và cài **AdsBlocker**
   (hoặc tải `AdsBlocker.ipa` rồi import vào Ksign).
2. **Cài đặt › Ứng dụng › Safari › Tiện ích mở rộng › AdsBlocker** → bật, cho phép **Mọi trang web**.
3. Trong Safari: biểu tượng ô ghép hình trên thanh địa chỉ › **AdsBlocker** › **Cài đặt AI**: dán API key
   (tạo miễn phí tại aistudio.google.com), bấm **Tải danh sách model** rồi chọn model.

AdsBlocker dùng 2 App ID (app + extension); Ksign ký bằng chứng chỉ nên không vướng hạn mức App ID.

## Cách hoạt động

| Lớp | Chạy ở | Làm gì |
|-----|--------|--------|
| 1. Chặn mạng | ruleset `ads_custom` (`rules/ad_domains.json`), `ads` (EasyList + ABPVN), `tracking` (EasyPrivacy + `tools/lists/`) | ~46k domain quảng cáo, ~47k domain theo dõi, ping bên thứ ba, widget mạng xã hội; mạng popunder bị chặn cả khi mở thành tab mới |
| | `content/content.js` + background `cosmetic` | Ẩn phần tử theo bộ lọc: selector theo tên miền ngay khi tải, selector chung chỉ cho id/class đang có trên trang |
| 2. Popup & lớp phủ | `content/main_world.js` (JS của trang) | Bọc `window.open`, `a.click()`, `dispatchEvent(click)`: chỉ cho mở tab mới khi người dùng thật sự bấm vào nút/link và đích đến khớp link đó |
| | `content/main_world.js` (Navigation API) | **Tab-under**: trong 3 giây sau khi trang mở tab mới (cùng một cú chạm), tab hiện tại chuyển sang site khác → huỷ (`navigate.preventDefault`), log `tabunder`, rồi đóng tab mới và mở URL của nó ngay tại tab hiện tại (giữ lịch sử Back). Tab không có handle (`target=_blank`, noopener) do background đóng (`tabUnder`: tab vừa tạo có `openerTabId` = tab này, hoặc cùng cửa sổ khi Safari không điền); chuyển hướng không do người dùng tới domain đã chặn tab mới cũng bị huỷ |
| | `content/content.js` | Gỡ lớp phủ trong suốt bắt click (quét lúc tải trang 30 giây đầu, và ngay khi bị chạm), ẩn phần tử theo rule CSS |
| 3. Quét bằng AI | `background.js` → `SafariWebExtensionHandler.swift` → Gemini | Snapshot các khối nghi là quảng cáo (HTML **đã bỏ chữ**) + ảnh chụp có đánh số + domain bên thứ ba + nhật ký popup → Gemini trả rule JSON → `rules/validate.js` lọc → người dùng duyệt |

### Công tắc: Chặn quảng cáo / Chống theo dõi / Chặn quảng cáo YouTube

Đầu popup. Lưu `storage.local.features`; background bật/tắt ruleset tĩnh (`updateEnabledRulesets`) và **dựng lại toàn bộ
rule động từ storage** (`rebuildDynamicRules`) theo tính năng đang bật — rule chặn domain mang `feature` ("ads" | "tracking").

| Tắt | Ngừng |
|-----|-------|
| Chặn quảng cáo | ruleset `ads_custom`/`ads`, ẩn phần tử (bộ lọc + rule riêng), chặn popup/tab mới, gỡ lớp phủ, rule domain "ads"; nút Chọn/Quét quảng cáo bị khoá |
| Chống theo dõi | ruleset `tracking`, xoá tham số, gỡ link bọc, chặn beacon, ô widget, rule domain "tracking" |
| Chặn quảng cáo YouTube | toàn bộ mục *Quảng cáo YouTube* bên dưới (độc lập với Chặn quảng cáo) |

### Quảng cáo YouTube (Safari)

Video quảng cáo tải từ cùng `googlevideo.com` với video thật nên không chặn ở tầng mạng được. Chỉ chạy trên `*.youtube.com`/`youtube-nocookie.com`:

- `content/main_world.js` bỏ `adPlacements`, `adSlots`, `playerAds`, `adBreakHeartbeatParams` khỏi dữ liệu player trước khi player đọc:
  setter `window.ytInitialPlayerResponse` (script inline), `JSON.parse`, `Response.prototype.json` (`youtubei/v1/player`…).
- Dự phòng khi lọt (`.ad-showing`): tắt tiếng, tua hết quảng cáo, bấm Bỏ qua; hết quảng cáo trả lại tiếng.
- `YOUTUBE_HIDE` (cũng trong `main_world.js`): `<style>` ẩn quảng cáo trong feed/tìm kiếm/trang xem (`ad-slot-renderer`, `ytm-promoted-*`…).
- YouTube đổi cấu trúc thường xuyên; quảng cáo ghép thẳng vào luồng video ở server (SSAI) thì không bỏ được.

### Chống theo dõi

- **Bộ lọc**: EasyPrivacy + `tools/lists/session_replay.txt` (Hotjar, Clarity, FullStory, LogRocket…), `fingerprinting.txt`
  (FingerprintJS…), `social.json` (widget Facebook/X/Instagram/TikTok/LinkedIn/Pinterest) + chặn `ping` bên thứ ba.
  Không chặn dịch vụ chống gian lận ngân hàng (ThreatMetrix, iovation).
- **Tham số theo dõi** (`utm_*`, `fbclid`, `gclid`, `msclkid`, `ttclid`, `igshid`…; `si` chỉ trên Spotify/YouTube — `cleanUrl`):
  rule DNR `redirect` + `queryTransform` (Safari từ chối thì bỏ, popup ghi chú) và `content/privacy.js` xoá trên thanh địa chỉ + link lúc chạm.
- **Link bọc chuyển hướng** (`google.com/url`, `l.facebook.com/l.php`, `out.reddit.com`, `youtube.com/redirect`… — `unwrapLink`): đổi thành link đích lúc chạm.
- **Beacon**: `main_world.js` bỏ `navigator.sendBeacon` tới tên miền khác; bỏ thuộc tính `ping` trên link.
- **Widget mạng xã hội**: ô "Chạm để tải" → background thêm rule allow cho tên miền widget, khởi nguồn từ trang này (`site.allowWidgets`), tải lại trang. Popup liệt kê/chặn lại.
- **Theo dõi trên trang này** (popup): domain bên thứ ba (resource timing + `src` trong DOM) phân nhóm bằng `filters/tracker_index.json`;
  có trong DOM mà không tải được → "Đã chặn". **Quét theo dõi bằng AI** chỉ gửi danh sách domain (không ảnh/HTML, `mode: "trackers"`),
  đề xuất chặn domain chưa có trong bộ lọc (feature "tracking", mọi trang).
- **App**: mục 4 hướng dẫn bật Ngăn theo dõi chéo trang, Ẩn IP, Bảo vệ nâng cao chống theo dõi & lấy dấu vân tay (Tất cả lượt duyệt web).

### Trang bị lỗi? Chẩn đoán (popup)

1. Người dùng **mô tả vấn đề** ("ảnh truyện không hiện", "nút đăng nhập không bấm được"…).
2. `content.js › diagnostics` thu dấu hiệu: ảnh lỗi, ảnh lazy-load chưa nạp, script/iframe/stylesheet có trong DOM mà không có
   trong resource timing (có thể bị chặn; ghi chú nếu bộ đệm timing ~250 mục đã đầy), khối đang bị extension ẩn (kèm số khối có ảnh/video).
3. `background.js › buildCandidates` truy nguồn: domain → ruleset `ads`/`tracking`/`ads_custom` (tra tên miền cha trong file ruleset)
   hoặc rule của người dùng; selector → bộ lọc/có sẵn/rule riêng/rule mọi trang/cấu trúc; nhật ký chặn tab mới/gỡ lớp phủ.
   Mỗi nghi phạm kèm các cách sửa hợp lệ; domain tải lỗi không do extension vẫn được liệt kê nhưng không có cách sửa.
4. **Chẩn đoán bằng AI** (`diagnose`, Swift): gửi vấn đề + dấu hiệu + nghi phạm (không ảnh/HTML) → Gemini trả `summary` + `fixes`;
   `checkFixes` chỉ giữ đề xuất trỏ nghi phạm có thật với cách sửa hợp lệ. **Chỉ xem dấu hiệu** chạy không cần AI.
5. Cách sửa = **ngoại lệ chỉ cho trang này** (lưu ở site gốc, áp cả tên miền dùng chung), huỷ được ở mục *Ngoại lệ của trang này*:
   `allow_domain` (rule DNR allow priority 4 — thắng mọi rule chặn), `unhide_selector`, `allow_popups`, `keep_overlays`, `delete_rule`.

### Bộ lọc lúc build (`tools/build-filters.mjs`)

`./build.sh` tải EasyList, ABPVN, EasyPrivacy (cache `.filters-cache/`, mất mạng thì dùng cache) → `WebExtension/filters/`.
Chỉ nhận rule `||domain^$tuỳ-chọn` (≈90% rule mạng; regex/đường dẫn/`$redirect`/`$csp` bỏ qua) và gộp domain cùng điều kiện vào
`requestDomains` (≤ 1000/rule) → ~480 rule thay vì ~93k, vì giới hạn rule tĩnh của Safari chưa rõ. Bộ lọc cập nhật mỗi lần build lại.

### Chọn quảng cáo để ẩn (`content/picker.js`)

1. Popup › **Chọn quảng cáo để ẩn** → popup đóng, trang phủ một lớp chắn trong suốt. Chạm vào quảng cáo không mở
   tab/không chạy script của trang, vẫn cuộn trang được. Chạm trúng iframe quảng cáo thì chọn cả iframe.
2. Tự chọn **khung chứa**: tổ tiên cao nhất cùng cỡ với chỗ chạm (khung đặt quảng cáo thường cố định dù nội dung đổi).
   Chỉnh bằng **▲ Rộng hơn / ▼ Hẹp hơn**.
3. **Ẩn** lưu một rule gồm:
   - `selector`: selector có nghĩa (id/class ổn định, `data-ad*`) đã đo trên trang: trúng khối, ≤ 50 khối, ≤ 30% trang;
   - `fallback`: tối đa 2 selector dự phòng (`iframe[src*="domain"]`, selector duy nhất);
   - `structural`: đường dẫn `:nth-of-type`, chỉ dùng khi mọi selector trên không còn trúng (trang đổi class), và chỉ
     ẩn khi trúng đúng 1 khối ≤ 30% trang;
   - các domain đã tick: **Chặn luôn domain** (tài nguyên trong khối, áp cho mọi trang) / **Chặn tab mới tới** (link trong khối).
4. **Ẩn bằng AI** chỉ gửi khối đã chọn (HTML bỏ chữ, 4 tổ tiên, ≤ 5 khối anh em, ảnh chụp có khung đỏ) với
   `mode: "picked"`. Đề xuất qua `validateRules` rồi hiện cạnh rule cơ bản để tick chọn → **Lưu rule đã chọn**.

Rule tự chọn mang nhãn **Tự chọn** trong "Rule đã lưu", xoá là khối hiện lại.

### Hộp thoại bắt tắt chặn quảng cáo (mở khoá cuộn)

Trang hiện hộp thoại thường khoá cuộn (`overflow:hidden` trên html/body hoặc class kiểu `modal-open`, body `position:fixed;
top:-Ypx`, `touch-action:none`, `preventDefault` trên `touchmove`/`wheel` ở document) và có lớp nền mờ riêng. Chỉ ẩn hộp
thoại thì trang vẫn không cuộn được. Bật **mở khoá cuộn** theo trang:

- Bảng chọn: ô **Mở khoá cuộn trang** tự tick khi khối chọn phủ ≥ 50% màn hình và được ghim (fixed), hoặc trang đang khoá cuộn;
  rule lưu cờ `unlockScroll` (nhãn *Mở khoá cuộn* trong "Rule đã lưu", xoá rule là thôi mở khoá). Khối này được vượt giới hạn 30% diện tích.
  Lúc lưu, bảng chọn tìm luôn **lớp nền mờ** (phần tử anh em của khối/tổ tiên: fixed, phủ ≥ 90% màn hình, không chữ/ảnh) và để
  selector của nó đầu `fallback` → CSS ẩn ngay khi trang chèn vào; chỉ dò bằng JS thì lớp nền kịp hiện một khung hình (màn hình nháy tối mỗi lần tải).
- Popup › **Mở khoá cuộn trang này** (`site.unlockScroll`): khi hộp thoại đã bị bộ lọc ẩn sẵn, không có rule riêng.
- `content.js › unlockScroll`: style inline `!important` chỉ cho thuộc tính đang khoá (thắng cả class), body bị ghim → `static`
  rồi cuộn về đúng chỗ; dò lớp nền mờ chưa có selector; chạy **ngay trong callback MutationObserver** (trước khi trình duyệt vẽ),
  trang giành lại khoá liên tục thì sau 5 lần trong một task chuyển sang hẹn giờ 100ms (tránh treo).
- `main_world.js`: bỏ qua `preventDefault()` của `touchmove`/`wheel` gắn ở window/document/html/body (phần tử con như carousel vẫn chặn được).

### Nhật ký chặn → Chặn luôn

Mục *Nhật ký chặn* trong popup: dòng **Popup**/**Tab-under** có nút **Chặn luôn &lt;domain&gt;** (`blockPopupDomain` → `global.popupDomains`):
từ đó chặn tab mới + chuyển hướng tới domain này ở mọi trang (DNR `main_frame`/`sub_frame`). Không hiện cho domain của chính trang,
CDN dùng chung, domain đã chặn. Quét AI cũng nhận log `tabunder` trong `popupLog`.

### Phạm vi rule và dùng chung giữa tên miền

| Rule | Phạm vi | Lưu ở |
|------|---------|-------|
| Ẩn phần tử | **Trang này** (mặc định) hoặc **Mọi trang** | `site:<site gốc>` / `global` |
| Chặn domain | Mọi trang (rule DNR), hiện ở trang tạo ra nó | `site:<site gốc>.blockDomains` |
| Chặn tab mới tới domain | Mọi trang (DNR + chặn `window.open`) | `global.popupDomains` |

- **Mọi trang** chỉ được chọn khi selector có dấu hiệu quảng cáo rõ (`globalScopeProblem` trong `rules/validate.js`):
  từ khoá quảng cáo trong id/class/attribute (`a.ads-banner`, `[data-ad-slot]`) hoặc `src/href` trỏ domain
  (`iframe[src*="adnet.com"]`). Tên do trang tự đặt (`div.w-overlay`) và đường dẫn `:nth-of-type` luôn chỉ áp trang này.
  Chọn khi lưu (bảng chọn, kết quả AI — chạm nhãn phạm vi) hoặc chuyển sau trong "Rule đã lưu".
- **Dùng chung rule với tên miền khác** (trang hay đổi tên miền như truyenqqko → truyenqqto): popup gợi ý tên miền giống
  (`similarSites`) hoặc chọn tay. Rule riêng của tên miền hiện tại được gộp sang site gốc; `aliases` luôn trỏ thẳng tới gốc.

### Sau khi cập nhật app

Safari có thể giữ extension cũ: popup báo lỗi phần native (`RBSLaunchRequest … Launch failed`). Background tự thử lại 1 lần;
còn lỗi thì popup hiện banner **Tải lại extension** (`browser.runtime.reload()`, cũng có ở cuối popup). Vẫn lỗi → đóng hẳn
Safari (vuốt khỏi đa nhiệm) rồi mở lại, tải lại các trang đang mở.

Rule AI được lọc trước khi hiển thị: bỏ selector quá chung (`div`, `body > div`…), selector ẩn hơn 30% trang
hoặc trúng hơn 50 phần tử, domain của chính trang, CDN dùng chung, độ tin cậy dưới 0.5.

- **API key** chỉ đi một chiều từ popup vào Keychain của extension (`KeychainStore.swift`); JS không bao giờ đọc lại được.
- **Trang nhạy cảm** (ngân hàng, email, các domain có chữ "bank", danh sách sửa được trong Cài đặt AI) không cho quét.

## Cấu trúc

```
Sources/AdsBlocker/            app SwiftUI: hướng dẫn bật extension
Sources/AdsBlockerExtension/   SafariWebExtensionHandler (native messaging), KeychainStore, GeminiClient (prompt + responseSchema)
WebExtension/                  manifest.json, background.js, content/, popup/, rules/, filters/ (sinh lúc build) — xtool copy vào gốc appex
tools/build-filters.mjs        tải + chuyển bộ lọc ABP → ruleset DNR, dữ liệu ẩn phần tử, chỉ mục tracker
tools/lists/                   danh sách tự soạn: ghi lại phiên, lấy dấu vân tay, widget mạng xã hội
tests/                         node:test cho logic thuần + smoke test Chrome headless
```

## Kiểm thử

```bash
node --test tests/*.test.js        # validate.js, candidates.js, build-filters.mjs, background.js (node:vm + browser giả), BOM
node tests/browser-smoke.mjs       # content script trên Chrome headless: overlay, click-hijack, snapshot, validate, rule,
                                   # chế độ chọn (khung chứa, rộng/hẹp, Ẩn, structural, Ẩn bằng AI, Huỷ)
node tests/youtube-smoke.mjs      # YouTube trên Chrome headless (CDP Fetch giả m.youtube.com): bỏ quảng cáo khỏi dữ liệu player, ẩn feed, tua/bỏ qua, công tắc
node tests/popup-smoke.mjs [ảnh.png]  # popup với background giả: trạng thái đang xử lý / xong / lỗi của từng nút
node tests/page-guard-smoke.mjs   # Chrome headless: chặn tab-under (click thật qua CDP Input), mở khoá cuộn sau khi ẩn hộp thoại
```

Không có Safari trên Linux, nên smoke test chạy bằng Chrome với `browser.*` giả lập. Những gì riêng của Safari
(native messaging, `captureVisibleTab`, `world: "MAIN"`, hạn mức storage, badge) chỉ kiểm được trên iPhone.

## Giới hạn đã biết

- Chưa xác nhận trên Safari: giới hạn rule tĩnh, `requestDomains`, `redirect.transform.queryTransform`. Popup cảnh báo nếu
  Safari không bật được ruleset (`getEnabledRulesets` lệch công tắc) và ghi chú nếu không xoá tham số được ở tầng mạng.
- Ẩn phần tử chung của EasyList có thể ẩn nhầm ở vài trang — tắt Chặn quảng cáo hoặc xoá/ghi ngoại lệ trong bộ lọc.
- Báo cáo theo dõi là "phát hiện" (DOM + resource timing), không phải số request bị chặn chính xác (Safari không cho extension đếm).

- Nếu Safari bỏ qua `"world": "MAIN"`, `main_world.js` tự chèn lại vào trang qua `<script src>`. Cách này chạy hơi
  trễ và có thể bị CSP của trang chặn.
- Trang dùng thẻ `div` có `onclick` để mở tab mới (không phải nút/link thật) cũng bị chặn. Extension luôn chặn, không có
  công tắc riêng: cần thì tắt AdsBlocker cho trang đó bằng quyền theo từng trang web trong menu tiện ích của Safari.
- Tab-under chỉ chặn được khi Safari có Navigation API (`window.navigation`, chưa kiểm chứng trên iOS); không có thì chỉ còn
  danh sách chặn domain. Trang chuyển tab cũ **trước** rồi mới mở tab mới, hoặc chuyển sau hơn 3 giây, thì không bắt được.
  Trang thật bị chặn nhầm → ngoại lệ "Cho trang này mở tab mới" (tắt cả chặn tab-under trên trang).
- Nếu Safari không cho chụp màn hình, Gemini chỉ dựa vào HTML nên kết quả kém hơn (popup sẽ báo "không có ảnh chụp").
- Thống kê và kết quả quét theo tab lưu ở `storage.local` (khoá `tab:*`), dọn khi đóng tab và khi Safari khởi động lại.
  Không dùng `storage.session` vì Safari iOS báo vượt hạn mức dù dữ liệu chỉ vài KB.
- Chọn quảng cáo: bật xong phải vuốt đóng popup. Popup không tự gọi `window.close()` vì trên Safari iOS sau đó popup
  có thể không mở lại được ở tab đó cho tới khi tắt hẳn Safari.
  Trong iframe quảng cáo chỉ ẩn được cả iframe, không chọn được từng phần bên trong.
- **Ẩn bằng AI** cần đã đồng ý gửi dữ liệu một lần (qua nút **Quét trang bằng AI** trong popup).
