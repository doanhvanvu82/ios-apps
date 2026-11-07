# GameHub — Trình chơi game đa engine trên iOS

App iOS chơi game trực tiếp trên thiết bị, **không cần port từng game** — và với
Godot / KiriKiri2 / Flash, **không cần build lại game trên máy tính**.

## Kiến trúc

```
iPhone (Files app)
  └─ On My iPhone/GameHub/
       ├─ Imports/    ← copy game (.zip hoặc thư mục) vào đây
       └─ Games/      ← app tự giải nén & dời game vào đây
```

App quét `Games/`, **tự nhận diện engine**, rồi chạy game qua `WKWebView` + **HTTP server nội bộ** (`127.0.0.1`) — cách duy nhất để game HTML5 hoạt động đúng vì WKWebView chặn `file://` cross-origin.

### Chơi game Windows GỐC không cần build (runtime đi kèm app)

App **bundle sẵn runtime web** cho 3 engine (98 MB trong IPA). Khi gặp game gốc
Windows, server phục vụ **file game gốc** kèm runtime tương ứng:

| Engine gốc | Runtime trong app | Cách nạp game |
|---|---|---|
| Godot 3.x/4.x (`.pck` có magic `GDPC`) | `godot.js` + `index.wasm` | `mainPack` → đọc `.pck` gốc (Godot 3: stream pck thẳng vào 1 buffer rồi giao cho MEMFS không chép — `ownToFS` trong `godot3/godot.js`; bản gốc giữ 2 bản pck trong RAM → iOS giết tiến trình. VRAM: `godot3/gamehub_texture.js` thu nhỏ texture RGBA ≥128² lúc đưa lên GPU (2/3 — vẫn nét vì canvas iPhone chỉ hiện ~0.64×; texture cạnh luỹ thừa 2 dùng 0.5 để giữ mipmap) + `override.cfg` ép renderer GLES2/WebGL 1 (GLES3/WebGL 2 của Godot 3 mất WebGL context trên WebKit iOS → màn đen) và tắt shadow atlas 4096² — Buchicome từ 1,6 GB xuống ~680 MB. Godot 4: pck đọc lazy theo chunk 1 MB — `mountLazyFile` trong `godot4/godot.js`, XHR đồng bộ lấy đoạn Range dạng base64 qua `?gh_b64=1` của `LocalWebServer` (nhị phân qua text hỏng khi đoạn bắt đầu bằng byte giống BOM); texture 0.5× qua cùng `gamehub_texture.js` (symlink)) |
| KiriKiri2 (`.xp3`) | kirikiroid2-web | WebDAV `PROPFIND` quét thư mục game + đọc file lazy qua HTTP Range — **không cần nén zip**. Runtime không có `json.dll` → `KiriKiriPatch.swift` thêm `patch.xp3` ảo chứa `PluginLoader.tjs` = `kiriki/json_polyfill.tjs` + chạy bản gốc (game KAG có `plugin/json.dll`) |
| Flash (`.swf`) | Ruffle | nhúng `.swf` gốc |

`EngineRuntime.swift` sinh `index.html` động (điền config đúng tên `.pck`, kích
thước file…), server trả nó thay cho `index.html` thật; các file runtime được
tra cứu fallback vào `Bundle/Runtime/<engine>/` khi không có trong thư mục game.

### Engine được nhận diện

| Engine | Nhận diện bằng | Trạng thái |
|---|---|---|
| RPG Maker MV/MZ | `index.html` + `js/rpg_core.js` / `js/rmmz_core.js` | ✅ Chơi được |
| TyranoBuilder (NW.js) | `index.html` + `tyrano/` — kể cả khi nằm trong `app.asar` hoặc zip gắn cuối `.exe` | ✅ Chơi được |
| Ren'Py (web build) | `index.html` + `renpy.js` / `renpy/*renpy.js` | ✅ Chơi được |
| Unity WebGL | `index.html` + `Build/*.loader.js` / `TemplateData/` | ✅ Chơi được |
| HTML5 generic | `index.html` + `js/`, `assets/`, `data/` | ✅ Chơi được |
| Godot 3.x/4.x (bản gốc Windows) | file `.pck` có magic `GDPC`, hoặc pck nhúng cuối `.exe` (12 byte cuối = size + `GDPC`) | ✅ Chơi được: 3.x → `godot3`, 4.0–4.2 → `godot4`, 4.3+ → `godot45` (template spine-godot 4.2 / Godot 4.5.1, có module Spine) |
| KiriKiri2 (bản gốc Windows) | file `.xp3` | ✅ Chơi được — WebDAV trong app (cần iOS 18.4+ vì JSPI) |
| Flash (bản gốc) | file `.swf` | ✅ Chơi được — Ruffle trong app |
| Ren'Py 8.3.x (bản gốc PC) | `renpy/` + `game/` + `<Tên>.py`, `renpy/vc_version.py` = 8.3.* | ✅ Chơi được: runtime web Ren'Py 8.3.7 trong app (`RenPyNative.swift`) |
| Ren'Py desktop khác 8.3 | như trên, phiên bản khác | ❌ Cần runtime web cùng phiên bản, hoặc build bản web (`tools/renpy_web_build.sh`) |
| Unity Windows Mono | `globalgamemanagers` / `UnityPlayer.dll`, không có `GameAssembly.dll` | ❌ Cần dựng lại project → xem `tools/unity_extract.sh` |
| Unity Windows IL2CPP | có `GameAssembly.dll` | ❌ Logic đã biên dịch thành mã máy Windows |
| GameMaker / Unreal / Pixel Game Maker MV / ExHIBIT | `data.win` / `.utoc`·`.pak`+`Engine/` / `libcocos2d.dll`+`Resources/data/project.json` / `rld/` | ❌ Không có runtime chạy được bản Windows |

**Ghi chú:**
- **Save game web**: mỗi game có port server cố định (băm từ tên thư mục), nên localStorage/IndexedDB không bị mất giữa các lần mở. Bản trước dùng port ngẫu nhiên nên save web không giữ được qua lần mở sau.
- **RPG Maker bản NW.js sửa `main.js`** (gọi `require`, nạp plugin bằng `nw.Window.get().evalNWBin('….bin')`): tệp `.bin` là bytecode V8 do nwjc biên dịch, iOS không chạy được. Shim nạp tệp `.js` cùng tên thay thế. Nếu thư mục game không có tệp đó, server trả bản đi kèm app trong `Resources/Runtime/rpgmv/` (hiện có `js/plugins/ChimakiSpine.js` 5.1.0, Spine 4.1, lấy từ Taiwan Love Story). Muốn bổ sung tệp bù cho game khác thì đặt vào đó theo đúng đường dẫn trong game.
- **RPG Maker bản Electron** (`package.json` có khai báo electron, plugin gọi thẳng `require('fs')`/`require('electron')`): app chèn shim Node (`ElectronShim.swift`). `fs` đọc file game qua HTTP/PROPFIND, còn ghi (save) thì vào localStorage.
- **TyranoBuilder** bản Windows để `;configSave=file` thì app tự phục vụ `Config.tjs` đã đổi sang `webstorage` (`TyranoPatch.swift`). App không giả lập Node cho Tyrano: Tyrano 5 thấy có `process`/`require` là chuyển sang đường lưu file của Electron.
- **Thanh tải khi vào game** (`LoadProgress.swift`): hiện số tệp, dung lượng và tệp vừa nạp từ server của app, cùng số lỗi JS mới (chạm vào để xem log). Thanh tự ẩn khi màn hình game đã sáng và hết tải, hoặc sau 20s không có dữ liệu mới.
- **Log riêng mỗi game**: khi đang chơi, mọi dòng log được ghi kèm vào `Documents/GameHub/logs/games/<tên thư mục game>.log` (giữ 3000 dòng cuối, mỗi lần mở game có dòng `▶︎ Mở game`). Màn log có lựa chọn "Game này / Toàn app"; xem lại sau khi thoát qua nút "Xem log của game" trong sheet thông tin.
- Video: game xin `X.mp4` mà chỉ có `X.webm` (hoặc ngược lại) thì server trả file còn lại.
- Test RPG Maker trên máy: `GH_NO_RUNTIME=1 tools/gamehub_sim_server.py <game-dir> [port]`.

### Ren'Py bản PC (không build lại)

Runtime web Ren'Py (`Resources/Runtime/renpy`, lấy từ `renpy-8.3.7-web.zip`) chỉ chứa CPython 3.11 + stdlib; bản build web chuẩn giải nén cả `game.zip` vào RAM. `RenPyNative.swift` làm khác:
- `game.zip` dựng trong RAM lúc mở game: `main.py` (= `<Tên>.py`), `renpy/` của chính game (bỏ `.pyc` 3.9, web biên dịch lại từ `.py`), script và tệp ≤ 64 KB trong `game/`.
- Tệp lớn liệt kê ở `gh_lazy.json`; `gamehub_lazyfs.js` gắn vào FS, đọc theo Range (`?gh_b64=1`) khi Python mở, bộ đệm LRU chung 48 MB.
- Video khai báo `video -` trong `game/renpyweb_remote_files.txt`: Ren'Py web chỉ phát video qua URL, video đọc từ FS làm `video_stop` ném lỗi và treo game.
- Test trên máy: `tools/renpy_test_server.py <game-dir> Sources/GameHub/Resources/Runtime/renpy [port]`.

### Không hỗ trợ được và vì sao

| Loại | Ví dụ | Lý do |
|---|---|---|
| Unity IL2CPP | Hitonatsu, Lifeguard Holic, Secret Atelier, Ride Me Taxi Driver | `GameAssembly.dll` là mã máy x86-64 Windows |
| Unity Mono | NTR Kazoku, Mad Island, The Censor | Không có runtime Unity chạy bản build Windows; phải xuất project và build WebGL trên máy tính |
| GameMaker `data.win` | BodysmithTales, ApartmentStory | Không có runtime web cho `data.win` |
| Pixel Game Maker MV | 6th Month for You and Me | Logic nằm trong engine C++ của exe |
| Unreal Engine 5, ExHIBIT, engine riêng | nemuikizuna, idgap, Tsumakan2, SPITE, bộ Alibi (`.ta`/`.tad`) | Không có runtime |
| Bản tải thiếu | Molester Game (`.rar.part`), A Story About A Beloved Wife (`app.asar` chỉ có mp3) | Thiếu dữ liệu game |

### Game đóng gói `.asar` (NW.js/Electron)

Game NW.js thường đóng gói toàn bộ trong `app.asar` nặng 700–850 MB. App **đọc thẳng byte range từ archive** (`AsarArchive.swift`) và stream ra WebView — **không cần giải nén ra đĩa**, nên không tốn gấp đôi dung lượng trên iPhone.

## Công cụ chuyển đổi (chạy trên Linux)

| Script | Việc |
|---|---|
| `tools/renpy_web_build.sh <game-dir> [out]` | Build bản web cho game Ren'Py desktop → chơi được trên iOS |
| `tools/renpy_batch_build.sh [lib] [out]` | Batch build web cho **mọi** game Ren'Py trong thư viện |
| `tools/unity_extract.sh <unity-game> [out]` | Dựng lại project Unity từ game đã build (AssetRipper) |
| `tools/unity_build_webgl.sh <project-dir> [out]` | Build project Unity → **WebGL** để chơi được trên iOS (tự vá 5 lỗi phổ biến) |
| `tools/patch_spine.sh --project <project-dir>` | Vá `spine-unity.dll` (lỗi "Destroy in edit mode") |
| `tools/fix_always_included_shaders.py <project> [log]` | Thêm shader bị thiếu vào `m_AlwaysIncludedShaders` |
| `tools/register_global_settings.cs` | Đăng ký `UniversalRenderPipelineGlobalSettings` (fix shader null runtime) |
| `tools/unity_test_server.py <webgl-dir> [port]` | Server test để kiểm tra bản WebGL trong trình duyệt |
| `tools/gamehub_sim_server.py <game-dir> [port]` | Mô phỏng server của app (kèm WebDAV PROPFIND) — test game KiriKiri gốc ngay trên máy |
| `tools/unity_diagnostics.cs` | Script chẩn đoán trong Editor (kiểm tra global settings, shader) |
| `tools/detector-cli` | Chạy chính `EngineDetector.swift` của app trên máy (symlink mã nguồn, không lệch với app): `swift build -c release --package-path tools/detector-cli`, rồi `tools/detector-cli/.build/release/detector-cli <thư-mục-game>…` → JSON. `tools/phan_loai.sh` tự build và dùng nó |
| `tools/asar_probe.py <file.asar>` | Khảo sát cấu trúc file `.asar` |

### Quy trình đưa game Unity Windows lên iOS

```
game.exe  --AssetRipper-->  project Unity  --unity_build_webgl.sh-->  WebGL  --> copy vào iPhone
```

1. **Dựng project** (chỉ làm được với game dùng scripting backend **Mono**; game IL2CPP không decompile được logic):

   ```bash
   ./tools/unity_extract.sh ~/Documents/Game/NTR_Kazoku ~/Documents/Code/ios/apps/GameHub/workspace/unity-projects/NTR_Kazoku
   ```

   AssetRipper 2.0 chỉ có GUI (chạy headless, điều khiển qua web UI ở `http://127.0.0.1:8900`).

2. **Build WebGL**:

   ```bash
   ./tools/unity_build_webgl.sh \
       ~/Documents/Code/ios/apps/GameHub/workspace/unity-projects/NTR_Kazoku/ExportedProject \
       ~/Documents/Code/ios/apps/GameHub/workspace/unity-webgl/NTR_Kazoku
   ```

   Script tự động vá 5 lỗi thường gặp (xem bảng bên dưới).

3. **Kiểm tra trong trình duyệt** (trước khi copy sang iPhone):

   ```bash
   python3 tools/unity_test_server.py ~/Documents/Code/ios/apps/GameHub/workspace/unity-webgl/NTR_Kazoku 8099
   # mở http://127.0.0.1:8099/index.html
   ```

4. **Copy** thư mục kết quả (có `index.html` + `Build/`) vào `Files → On My iPhone → GameHub → Imports`.

> **Lưu ý dung lượng:** bản WebGL của game 1,2 GB có thể lên tới ~1,3 GB (file `.data` nén sẵn `.br` chỉ ~96 MB).
> App đã hỗ trợ server trả file nén sẵn kèm header `Content-Encoding` nên `.br`/`.gz` vẫn chạy được.

### 5 lỗi chặn build Unity WebGL (đã có tool xử lý tự động)

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `error CS0104: 'Event' is an ambiguous reference` | Code decompile có cả `using Spine;` và `using UnityEngine;` | `unity_build_webgl.sh` tự sửa tham số thành `Spine.Event` |
| `IndexOutOfRangeException` trong `WebGlBuildPostprocessor.PostProcess` | Project export để trống `webGLTemplate` → `template.Split(':')[1]` lỗi | Set `webGLTemplate: APPLICATION:Default` |
| `emcc: error: INITIAL_MEMORY must be larger than STACK_SIZE` | `webGLInitialMemorySize`/`MaximumMemorySize` = 0 | Set 32 MB / 2048 MB + `memoryGrowthMode: Linear` |
| `Destroy may not be called from edit mode!` (72 lỗi) | Spine runtime 3.x/4.0 gọi `Object.Destroy()` trong `OnDestroy` ở edit mode | `tools/patch_spine.sh` — vá IL của `spine-unity.dll` sang `DestroyImmediate` khi không play mode |
| `Cannot create required material because shader is null` (runtime crash) | Asset `UniversalRenderPipelineGlobalSettings` không được đăng ký → Unity **loại khỏi build** → các shader của URP (CoreBlit, Sampling, BlitHDROverlay, Light2D…) thành null | `tools/register_global_settings.cs` gọi `EditorGraphicsSettings.SetRenderPipelineGlobalSettingsAsset()`; `tools/fix_always_included_shaders.py` thêm shader chỉ được tham chiếu bởi pipeline settings vào `m_AlwaysIncludedShaders` |

> **Không cần Unity license** cho tới bước build player — editor chỉ báo warning `com.unity.editor.headless was not found`.

### Yêu cầu cho các công cụ

```bash
# Ren'Py SDK (cho bản web)
curl -O https://www.renpy.org/dl/8.5.2/renpy-8.5.2-sdk.tar.bz2
tar xjf renpy-8.5.2-sdk.tar.bz2 -C ~/renpy --strip-components=1
# Runtime WebAssembly đi kèm (bắt buộc, SDK không chứa sẵn):
curl -O https://www.renpy.org/dl/8.5.2/renpy-8.5.2-web.zip
unzip -q renpy-8.5.2-web.zip -d ~/renpy     # → ~/renpy/web/

# AssetRipper (cho Unity)
curl -L -o ar.tar.xz https://github.com/AssetRipper/AssetRipper/releases/download/2.0.0/AssetRipper_linux_x64.tar.xz
tar xJf ar.tar.xz -C ~/assetripper

# Unity Editor 6000.0.54f1 + module WebGL (cho bước build WebGL)
mkdir -p ~/unity-dl && cd ~/unity-dl
curl -L -O https://download.unity3d.com/download_unity/4c506e5b5cc5/LinuxEditorInstaller/Unity.tar.xz
curl -L -O https://download.unity3d.com/download_unity/4c506e5b5cc5/TargetSupportInstaller/UnitySetup-WebGL-Support-for-Editor-6000.0.54f1.tar.xz
mkdir -p ~/Unity
tar xJf Unity.tar.xz -C ~/Unity
tar xJf UnitySetup-WebGL-Support-for-Editor-6000.0.54f1.tar.xz -C ~/Unity
~/Unity/Editor/Unity -version      # → 6000.0.54f1
```


## Build file .ipa (Linux, bằng xtool)

```bash
cd ~/Documents/Code/ios/apps/GameHub
./build.sh          # build incremental
./build.sh clean    # xóa cache rồi build lại từ đầu
```

Kết quả: **`xtool/GameHub.ipa`**

Script sẽ tự động:
1. Đưa Swift toolchain đúng vào `PATH` (mặc định `~/swift-dev`).
2. Đồng bộ `clang/include` của Darwin SDK với toolchain (bắt buộc — xem mục "Lưu ý kỹ thuật").
3. Chạy `xtool dev build --ipa`.

Toàn bộ bước trên nằm trong pipeline chung `../../toolkit/build_app.sh` (xem `~/Documents/Code/ios/AGENTS.md`); `build.sh` của GameHub chỉ vẽ icon và ghi `GameHubDevServer` trước khi gọi pipeline.

Cài lên iPhone — **cập nhật qua Ksign, không cần chép IPA**:

`build.sh` cập nhật "source" AltStore **chung cho mọi app** ở `~/Documents/Code/ios/sidestore/` (`source.json` + icon + `GameHub-1.<N>.ipa`)
và bật server LAN (`toolkit/serve_sidestore.sh`, port 8765, chạy nền).

1. Một lần: Ksign → **Sources** → **+** → `http://<IP máy tính>:8765/source.json`
   (`build.sh` in ra đúng URL). iPhone và máy tính phải cùng Wi-Fi.
2. Mỗi lần build: mở source trong Ksign → tải/cài bản mới của GameHub.

`../../toolkit/serve_sidestore.sh stop` để tắt server.

Server này (`toolkit/dev_server.py`) còn nhận log: màn **Log** trong app có nút 🖥 **Gửi về máy tính** → nội dung
vào thẳng clipboard máy tính + lưu `~/Documents/Code/ios/.state/iphone_clipboard.txt`. Địa chỉ máy tính được `build.sh` ghi vào
`Info.plist` (`GameHubDevServer`) mỗi lần build.

> `xtool install` / `xtool dev run` (cài thẳng qua USB) cần `xtool auth login`; đăng nhập bằng
> mật khẩu bị Apple từ chối (`-80046`) nên không dùng.

### Lưu ý kỹ thuật (vì sao build trên Linux phức tạp)

| Vấn đề | Nguyên nhân | Cách xử lý |
|---|---|---|
| `this SDK is not supported by the compiler` | Xcode 27.1 build bằng Swift 6.4, máy chỉ có 6.0.3 | Cài toolchain mới hơn |
| `module '_c_standard_library_obsolete' requires feature 'found_incompatible_headers__check_search_paths'` | clang của toolchain cũ hơn clang của SDK | Đồng bộ `clang/include` trong SDK (script tự làm) |
| `cyclic dependency in module '_Builtin_float'` | Cũng do lệch phiên bản clang | Như trên |
| `ld64.lld: /usr/lib/x86_64-linux-gnu/libz.so: unhandled file type` | Manifest của ZIPFoundation được evaluate trên Linux → khai báo system library `zlib` → SwiftPM thêm `-lz` của Linux vào link line | Vendor ZIPFoundation trong `Vendor/` và bỏ dependency `CZLib` (trên iOS ZIPFoundation dùng framework `Compression` của Apple nên không cần zlib) |

Toolchain cần dùng: **Swift development snapshot** (`~/swift-dev`) — vì bản release mới nhất của swift.org là 6.4.1 (clang 21) nhưng Xcode 27.1 cần clang ≥ 22.

## Màn điều khiển ảo (gamepad trên màn hình)

Game web cần bàn phím (RPG Maker, Godot, Ren'Py…) có **màn điều khiển ảo** bắn
`KeyboardEvent` thật vào trang:

- **Preset theo engine** — tự chọn khi vào game:
  - RPG Maker MV/MZ: D-pad + Z (xác nhận), X (huỷ), Shift (chạy nhanh), C (menu)
  - Visual novel (Ren'Py/KiriKiri): Enter (kể tiếp), Ctrl-giữ (skip), ESC (menu), A (log)
  - Godot/hành động: WASD + Z/X
- **Bật/tắt nhanh khi đang chơi**: nút gamepad nổi ở góc trái, hoặc menu 🎮 trên thanh điều hướng
- **Giữ phím** (dash/skip) — hỗ trợ multi-touch, di chuyển vừa bấm xác nhận
- **Tuỳ chỉnh theo từng game**: menu 🎮 → *Tuỳ chỉnh nút & phím*:
  - Đổi phím cho từng nút (30+ phím: KeyZ, Enter, F1-4, Digit, Shift…)
  - Kéo nút để đổi vị trí (trong overlay bấm đúp → icon 🖐 → kéo), lưu tự động
  - Chỉnh độ mờ, reset về preset
- Bố cục lưu riêng từng game trong `Documents/GameHub/Controls/<game>.json`

## Sử dụng

1. Cài app lên iPhone.
2. Lần đầu: bấm **Chọn thư mục** → chọn thư mục chứa game trong Files (có thể chứa thư mục con phân loại). App nhớ thư mục này và quét ngay.
3. Thêm game mới vào thư mục đó → **kéo xuống** ở màn thư viện (hoặc nút 📁 → *Quét lại thư viện*).
4. Bấm thẻ game để chơi. Game chưa hỗ trợ (ảnh xám + ổ khoá) → bấm để xem lý do.
5. **Giữ lâu** thẻ game → menu: Chơi / Thông tin / Xoá ảnh bìa đã chụp / Xoá game (có hỏi xác nhận).

### Giao diện

| Màn | Có gì |
|---|---|
| Thư viện (`LibraryView.swift`) | Tìm kiếm theo tên/engine, lọc *Tất cả / Chơi được / Chưa hỗ trợ*, sắp xếp *Gần đây / Tên*, hàng **Chơi tiếp** (6 game gần nhất), lưới ảnh bìa |
| Ảnh bìa (`CoverStore.swift`) | Ưu tiên: ảnh chụp màn hình lúc thoát game → `cover.jpg`/`cover.png` bạn tự đặt trong thư mục game → ảnh sinh tự động (màu engine + chữ cái đầu). Ảnh chụp quá tối bị bỏ |
| Màn chơi (`ContentView.swift` → `GamePlayView`) | Màn khởi động (ảnh bìa mờ) tới khi trang load xong; nút ở mép màn hình (trên trái: trở về, dưới nó là bật/tắt chuột ảo — touchpad: kéo di chuyển con trỏ, chạm click, giữ click phải, chạm 2 lần + giữ để kéo; loại trừ với điều khiển ảo; trên phải: menu ⋯, dưới nó là bật/tắt điều khiển; khi xoay ngang nằm giữa dải viền tai thỏ nên không che game); thoát game có hỏi xác nhận |
| Log (`DebugLogView.swift`) | Lọc Lỗi/Cảnh báo, tìm kiếm, chia sẻ; dòng lặp liên tiếp được gộp `×N` |

Hệ màu/animation dùng chung ở `Theme.swift` (màu theo engine, `PressableButtonStyle` co + rung khi bấm).

> **Lưu ý quan trọng:** PC game (.exe) trong thư mục của bạn là bản Windows — app chỉ chơi được **bản web build** (nhiều game Ren'Py/RPG Maker có bản web trên itch.io, hoặc tự export bằng engine nếu bạn sở hữu dự án).
> Với game Unity, xem quy trình chuyển đổi ở mục [Quy trình đưa game Unity Windows lên iOS](#quy-trình-đưa-game-unity-windows-lên-ios).

## Công cụ chuyển đổi thêm (10/10)

| Script | Việc |
|---|---|
| `tools/unity_batch_build.sh` | Batch 19 game Unity Mono → WebGL (tự tìm editor theo version game) |
| `tools/unity_fetch_version.sh <ver…>` | Tải Unity Editor + module WebGL cho version cụ thể (vào `~/unity-versions/`) |
| `tools/unity_normalize_project.py <project> [--apply]` | Xoá DLL render pipeline/TMP cũ → dùng package 17.x |
| `tools/godot_web_export.sh <game-dir> [out]` | Export game Godot (.pck) ra HTML5 |
| `tools/unity_headless_test.sh <url> [shot.png]` | Test bản WebGL bằng Chrome headless |
| `tools/check_guid_refs.py`, `check_null_shaders.py`, `check_material_shaders.py` | Chẩn đoán project Unity export |

### Game Godot → HTML5

Godot **không** export được từ `.pck` (cần project source), nhưng có cách khác:

1. Tạo project Godot tối giảu, export HTML5 (sinh ra `index.html` + `index.js` + `index.wasm` + `index.pck`).
2. **Thay `index.pck` bằng `.pck` của game** → engine đọc `project.godot` trong pck → game chạy thật.

```bash
./tools/godot_web_export.sh "$HOME/Documents/Game/Professor_Wakayamas_NTR_Classroom-Demo" \
                            ~/Documents/Code/ios/apps/GameHub/workspace/godot-web/Wakayama
```

> Godot WebGL cần **Cross-Origin Isolation** (`SharedArrayBuffer`) → app đã trả sẵn header
> `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp`.
>
> Godot dùng **C# (Mono)** sẽ không chạy trên web (web export không hỗ trợ C#).

## Game KiriKiri2 → Web (runtime kirikiroid2-web)

Engine KiriKiri2 (吉里吉里2) đã có **port WebAssembly**:
[fenghengzhi/kirikiroid2-web](https://github.com/fenghengzhi/kirikiroid2-web) (MIT).

Runtime nạp game qua tham số URL:

| Tham số | Ý nghĩa |
|---|---|
| `?game=/game.zip` | game đóng gói dạng ZIP (nhiều `.xp3` → nên dùng cách này) |
| `?xp3=/data.xp3` | một file `.xp3` đơn lẻ |
| `&loadMode=eager\|lazy` | tải trước / tải theo yêu cầu |
| `&entry=data.xp3` | chọn `.xp3` khởi động khi game có nhiều archive |

### Đóng gói game

```bash
./tools/kiriki_pack.sh "$HOME/Documents/Game/Iinari! Saimin Kanojo (GVNVH18)" \
                        ~/Documents/Code/ios/apps/GameHub/workspace/kiriki-web/Inari
```

Kết quả: `index.html` + `index.js` + `index.wasm` + `vlfs.js` + `assets.zip` + `game.zip`.
App nhận diện là `kirikiWeb` và tự mở `index.html?game=/game.zip&loadMode=eager`.

### Yêu cầu trình duyệt

| Tính năng | Cần cho | Hỗ trợ |
|---|---|---|
| WebAssembly JSPI | `WebAssembly.Suspending` / `promising` | Safari 18.4+, Chrome 137+ |
| SharedArrayBuffer | cross-origin isolation | app đã trả COOP/COEP |
| OPFS + `DecompressionStream('deflate-raw')` | giải nén `game.zip` | Safari 17+, Chrome 108+ |

> ⚠️ iOS 17–18.3 **không chạy** được (thiếu JSPI).
> Game KiriKiri **EAIRPG** (đuôi `.eog`) không dùng được runtime này — chỉ KiriKiri2 (`.xp3`).

## Game Godot 3.x → Web (không cần editor)

Godot 3.3 bản **headless** trên Linux **không export được** (editor cần X11; bản có
GUI chỉ phát hành cho Windows/macOS). Nhưng bản export template
`webassembly_release.zip` chứa sẵn runtime (`godot.js` + `godot.wasm`) và file
HTML có placeholder `$GODOT_*` → **thay placeholder bằng tay** là xong.

```bash
./tools/godot_web_build.sh "$HOME/Documents/Game/Buchicome ☆ High kick!" \
                            ~/Documents/Code/ios/apps/GameHub/workspace/godot-web/Buchicome
```

Các placeholder được thay:

| Placeholder | Giá trị |
|---|---|
| `$GODOT_PROJECT_NAME` | tên game |
| `$GODOT_URL` | `godot.js` |
| `$GODOT_CONFIG` | `{"args":[],"executable":"index","fileSizes":{"index.pck":N,"index.wasm":M},…}` |
| `$GODOT_HEAD_INCLUDE` | rỗng |

> ⚠️ Godot 3.x runtime nạp `<executable>.wasm` → phải copy `godot.wasm` thành
> **`index.wasm`** (không giữ tên `godot.wasm`).
>
> Game dùng **GDNative** (DragonBones, Live2D…) sẽ báo `Unknown class` vì plugin
> C++ cần `.so` native — các plugin này không chạy được trên web.

## Cấu trúc thư viện game

Thư mục `~/Documents/Game` được chia làm 3 nhóm (tự động bằng
`tools/organize_games.py`):

| Thư mục | Số | Nội dung |
|---|---|---|
| `1-ChoiDungTrucTiep/` | 23 | RPG Maker MV (12), TyranoBuilder (3), Godot gốc (2), KiriKiri2 gốc (3), Flash gốc (2), HTML5 (1) |
| `2-DaBuildLai/` | 5 | **Output của `build_all.sh`** — bản web đã build xong (Unity WebGL, Ruffle…) |
| `2-CanBuildLai/` | 24 | Unity Mono, Ren'Py desktop, NSIS-Godot, IL2CPP+Mono |
| `3-ChuaChoiDuoc/` | 27 | Unity IL2CPP, unknown, GameMaker (2), BGI (1) |

> **`2-DaBuildLai/` là nơi bản build được export.** `tools/build_all.sh` đọc game
> từ `2-CanBuildLai/` và ghi kết quả vào `2-DaBuildLai/` (file trung gian như
> project Unity vẫn ở `~/Documents/Code/ios/apps/GameHub/workspace` để dọn được).

Mỗi thư mục có `README.txt` mô tả cách build và lý do của từng nhóm.

### Thêm game mới

1. Copy thư mục game vào `~/Documents/Game/` (gốc — **đừng** đặt vào trong 3
   thư mục nhóm, để tool tự quyết định).
2. Chạy lệnh phân loại:

```bash
# xem trước (an toàn)
./tools/phan_loai.sh            # hoặc: phanloai

# thực thi di chuyển
./tools/phan_loai.sh --apply    # hoặc: phanloai-apply
```

Tool tự nhận diện engine, chọn nhóm, và **di chuyển** game vào đúng chỗ.
Nếu bạn nâng cấp detector và kết luận của game cũ thay đổi, chạy lại lệnh
`--apply` cũng sẽ chuyển game sang nhóm mới (idempotent, không bao giờ xoá game).


> App iOS lấy game từ `Documents/GameHub/Games` (trong container của app),
> **không** dùng `~/Documents/Game` — nên việc sắp xếp này không ảnh hưởng app.

## Phát hiện mới: 3 engine mới trong nhóm "chưa chơi được"

### 1. Flash / Adobe AIR → Ruffle (WebAssembly)

[Ruffle](https://github.com/ruffle-rs/ruffle) là Flash emulator viết bằng Rust →
biên dịch sang WebAssembly. Bản **self-hosted** dùng để nhúng vào web:

```bash
# tải: https://github.com/ruffle-rs/ruffle/releases → ruffle-<ver>-web-selfhosted.zip
./tools/flash_ruffle_pack.sh "<thư-mục-game>" ~/Documents/Code/ios/apps/GameHub/workspace/flash-web/<tên>
```

Script tự:
1. Trích SWF entry point từ file `.exe` của Flash projector (hoặc dùng
   `top.swf` / `Stage.swf` / `index.swf` nếu có sẵn).
2. Copy toàn bộ `.swf` phụ + ảnh.
3. Đưa runtime Ruffle (`ruffle.js` + `core.ruffle.*.js` + `.wasm`) vào.
4. Tạo `index.html` dùng polyfill `<embed>` của Ruffle.

> Game Adobe AIR cũng chứa file `.swf` → chạy được bằng Ruffle.

### 2. Unity IL2CPP mà còn giữ bản Mono gốc

Nhiều game IL2CPP **vô tình để lại bản Mono** trong thư mục backup của dev:

```
VeteranDriver_BackUpThisFolder_ButDontShipItWithYourGame/Managed/Assembly-CSharp.dll
```

Bản Mono đó có IL thật (khác với BepInEx *interop* chỉ là proxy) → AssetRipper
decompile ra source C# đầy đủ → build WebGL được.

```bash
python3 tools/unity_il2cpp_to_mono.py "<game-dir>" --out /tmp/mono-version --apply
```

Phân biệt Mono gốc vs interop proxy: đọc `AssemblyRef` — proxy trỏ tới
`Il2CppInterop.Runtime` / `Il2Cppmscorlib`, còn Mono gốc trỏ tới
`UnityEngine.*` / `Elringus.Naninovel.Runtime` / `spine-csharp`…

### 3. Game Godot đóng gói trong installer NSIS

`Goodbye_Eternity` chỉ có 1 file `.exe` 1,2 GB — thực ra là installer NSIS
chứa file `pck` của Godot 4.5:

```bash
./tools/nsis_extract.sh "<game-dir>"    # 7-Zip đọc được NSIS → lấy ra `pck`
./tools/godot_web_export.sh "<thư-mục-có-game.pck>" out/
```

Phát hiện bằng magic `GDPC` ở đầu file `pck`.

## 3 lỗi Unity mới (đã tự động hoá)

| Lỗi | Nguyên nhân | Cách sửa |
|---|---|---|
| `CS0246: 'CGViewer' could not be found` | AssetRipper sinh **dummy class** trùng tên (chỉ khác hoa/thường) với file thật → Unity coi là trùng | `tools/unity_fix_duplicate_types.py` — xoá file dummy |
| `CS0457: Ambiguous user defined conversions` | `Naninovel.DecimalParameter` có 2 operator ngầm định (`float?` và `float`) | `tools/unity_fix_naninovel_params.py` — ép qua `.Value` |
| `CS0104: 'Debug' is ambiguous` | `using System.Diagnostics` + `using UnityEngine` | sed đổi `Debug.` → `UnityEngine.Debug.` |

## Script build tổng hợp

```bash
./tools/build_all.sh                 # build tất cả game trong 2-CanBuildLai
./tools/build_all.sh --only Netori   # chỉ build game khớp tên
# → kết quả nằm ở ~/Documents/Game/2-DaBuildLai/<tên-ngắn>/
```

Tự nhận diện loại game (Unity / Godot / KiriKiri / Flash / Ren'Py) và gọi
đúng pipeline tương ứng.
