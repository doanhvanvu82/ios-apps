# Cherry Tale — mod menu (dylib)

Tiêm một dylib mod menu vào IPA Cherry Tale (Unity IL2CPP, arm64) để chỉnh
client-side trong lúc chơi. **Không** đổi kim cương, không đổi roster — dữ liệu
đó do server quyết định.

Thư mục này độc lập với `apps/`, `toolkit/`, `source/`, `sidestore/`; không sửa
gì ngoài `mods/cherrytale/`.

## Nội dung

```
mods/cherrytale/
├── build.sh            pipeline: nhận PHASE + SUFFIX, luôn sinh 2 IPA
├── vendor/dobby/       libdobby.a arm64 iOS + dobby.h (+ build.sh)
├── src/
│   ├── common.h        khai báo dùng chung
│   ├── il2cpp.h.mm     resolve class/method theo TÊN, retry ~90 s
│   ├── hooks.mm        registry hook + bảng tính năng
│   ├── autoclick.mm    engine auto click (ghi/phát/lặp + chấm số)
│   ├── config.mm       NSUserDefaults suite vn.vudv.cherrytale.mod + log
│   ├── recon.mm        PHASE=recon: chỉ resolve, ghi log
│   ├── main.mm         constructor, poll il2cpp, điều phối
│   └── ui/menu.mm      menu nổi UIKit thuần
├── work/               trung gian (gitignore)
└── out/                IPA + report.md (gitignore)
```

## Build

```bash
cd mods/cherrytale

# giai đoạn 1 — recon (không hook)
PHASE=recon ./build.sh

# giai đoạn 2 — menu + hook
PHASE=full ./build.sh

# giữ nguyên bundle id gốc
SUFFIX= PHASE=recon ./build.sh
```

Mỗi lần build ra **hai** IPA:

- `out/CherryTale_mod_2.2.1.ipa` — bản thường
- `out/CherryTale_mod_2.2.1_safe.ipa` — không cài hook, chỉ menu + recon (cứu hộ)
- `out/report.md`

Bundle id mặc định `vn.vudv.cherrytale.mod`; bản `_safe` dùng
`vn.vudv.cherrytale.modsafe` để cài song song.

Toolchain mặc định: `~/swift-dev` (clang), SDK iOS của xtool
(`~/.swiftpm/swift-sdks/darwin.artifactbundle`), `ld64.lld` của xtool toolset,
LIEF trong `work/venv`, `ldid` tải vào `work/tools`. Override bằng
`IOS_TOOLCHAIN`, `IOS_SDK`, `IOS_LD`, `LDID`.

## Giai đoạn recon

`PHASE=recon` dựng dylib **không hook**. Sau khi il2cpp khởi tạo, dylib resolve
từng ứng viên trong `src/recon.mm` rồi ghi:

- `Documents/cherrytale_recon.txt` (bật `UIFileSharingEnabled` nên lấy được
  qua app Files), và
- `NSLog` (xem bằng Console hoặc log thiết bị).

Cài bản recon bằng Ksign, mở game ~1 phút, lấy file log gửi lại. Chỉ sau khi
đối chiếu log mới chuyển sang `PHASE=full`.

## Auto click (tab AutoClick)

Kiểu macro: bấm tay các nút trong game → mỗi lần bấm được ghi thành một bước
(toạ độ chuẩn hoá + nhãn nút), sau đó phát lại tuần hoàn theo thứ tự 1, 2, 3…

- **Ghi** lấy click thật qua hook tĩnh `BtnClickEvent.OnPointerClick` (chỉ tồn
  tại khi build kèm `CT_WITH_CLICK=1`; `build.sh` đã bật). Vì hook chạy trong
  lời gọi click của game, nút Save/Close của menu mod (UIView riêng) **không
  bao giờ** bị ghi nhầm.
- **Phát** chiếu đúng **toạ độ** đã ghi như một ngón tay chạm: dựng
  `PointerEventData` tại điểm đó, gọi `EventSystem.RaycastAll`, lấy kết quả đầu
  tiên (trên cùng), rồi tìm `BtnClickEvent`/`UnityEngine.UI.Button` trên chính
  GameObject đó hoặc cha gần nhất (đúng `ExecuteHierarchy` của Unity) và invoke
  `OnPointerClick`. Điểm không có nút → bước đó bị bỏ qua và ghi log "trượt".
- **Thời gian**: slider cách nhau giữa các click (0,05–5 s) và nghỉ giữa 2 vòng
  (0,05–30 s), kèm nút `−`/`+` chỉnh từng 0,05 s. Giá trị lưu trong
  NSUserDefaults và nạp **lười** khi mở tab (constructor dylib đọc NSUserDefaults
  quá sớm nên dễ rơi về mặc định), vì vậy mở lại app vẫn giữ giá trị cuối.
- Chấm số vẽ đè lên màn hình game (không nhận chạm, nằm dưới panel menu) để
  thấy thứ tự; tắt được bằng công tắc trong tab.

Đừng dùng `GetComponentInChildren` để tìm handler: nó vớ cả handler của object
anh em (không phải cha), khác hẳn ngữ nghĩa một cú chạm và dễ bấm nhầm nút.

Giới hạn: đúng như macro toạ độ — UI đổi bố cục (mở popup khác, list cuộn đi)
thì điểm cũ có thể trượt hoặc trúng nút khác. Nên chỉ ghi các bước trong cùng
một màn hình; bước "vào trận/mở màn mới" chỉ dùng được một lần mỗi vòng.

## Đổi giá trị mặc định

- Sửa `defaultValue` trong bảng `kFeatures` ở `src/hooks.mm`, hoặc
- sửa các biến `g_dmgMul = 3.0f`, `g_critMul`, … ở đầu `src/hooks.mm`, hoặc
- trong game: kéo slider. Giá trị đã lưu trong NSUserDefaults sẽ đè mặc định.

Preset: **An toàn** (3x), **Farm** (10x + tự lặp + bỏ animation),
**Max** (100x + crit + bất tử + mở khoá CG).

## Nếu crash

1. Cài bản `_safe` — không có hook nào, chỉ menu + recon.
2. Trong menu → tab **Debug** → **TẮT TOÀN BỘ (khẩn cấp)**: tắt cờ hành vi và
   ghi `emergency_disabled = YES` để lần khởi động sau không cài hook.
3. Gỡ hẳn: xoá app, cài lại IPA gốc.

Slot mặc định trỏ trampoline (hành vi gốc). Bật tính năng = ghi địa chỉ hook vào slot;
không resolve được thì slot giữ trampoline và mục trong menu hiện xám.

## Rủi ro

- Game có `NumericCalculate.OnVerifyClientDamage` / `NumcVerifyProofs`: server
  đối chiếu sát thương, nên sửa sát thương **có thể bị lệch verify**.
- `Tự thắng trận` và `Quái HP = 1` chạm kết quả mô phỏng — rủi ro cao nhất.
- Đổi bundle id làm **mất keychain cũ** → phải đăng nhập lại. Dùng tài khoản
  rác cho bản mod.
- URL scheme gốc (`com.superhgame.emma`, `erolabsfe8603fd`) không trùng id mới.

## Giới hạn đã biết

- Không chạy được app trên máy Linux: chỉ kiểm chứng cấu trúc IPA.
- `vendor/dobby/` chỉ còn để tham khảo; pipeline dùng hook tĩnh (`tools/make_static_hooks.py`).
- Hook click (`click_btnev`) chỉ có khi generate với `CT_WITH_CLICK=1`; nếu build
  từ `work/gen` cũ thì `make_static_hooks.py generate` cần chạy lại (build.sh tự
  làm khi `dump.cs` mới hơn `ct_targets.h`).
