# iOS apps (build trên Linux, cài qua Ksign)

Ba app iOS build bằng **SwiftPM + [xtool](https://github.com/xtool-org/xtool) trên Ubuntu** (không cần Xcode/macOS),
phân phối qua **Ksign** (đọc source AltStore) với một URL cố định trên GitHub:

```
https://raw.githubusercontent.com/doanhvanvu82/ios-apps/main/source/source.json
```

## App

| App | Bundle ID | Mô tả |
|---|---|---|
| [AdsBlocker](apps/AdsBlocker) | `vn.vudv.adsblocker` | Safari Web Extension chặn quảng cáo (EasyList/ABPVN/EasyPrivacy) |
| [GameHub](apps/GameHub) | `vn.vudv.gamehub` | Chơi game PC (Unity/Godot/Ren'Py/KiriKiri/Flash) trên iPhone |
| [Mangalate](apps/Mangalate) | `vn.vudv.mangalate` | Safari Web Extension dịch truyện tranh (Vision OCR + Gemini) |

## Cài đặt

1. Một lần: cài **Ksign** trên iPhone → Sources → **+** → dán URL ở trên (hoặc tải IPA ở
   `releases/download/builds/` rồi import vào Ksign để ký và cài).
2. Mỗi bản mới: mở source trong Ksign → tải/cài bản mới.

IPA tải từ `releases/download/builds/`, tên file có version (`GameHub-1.122.ipa`) nên không dùng cache bản cũ.

## Build

Yêu cầu: Swift toolchain (`~/swift-dev`), Darwin SDK trong `~/.swiftpm/swift-sdks`,
`python3` + Pillow, `zip`/`unzip`. Chi tiết môi trường và các bẫy đã gặp: [AGENTS.md](AGENTS.md).

```bash
# Tải công cụ nặng (không commit vào repo)
#   toolkit/xtool.AppImage  — xtool 1.22.2
#   toolkit/xtool-src/      — mã nguồn xtool để tra cứu cách đóng gói
apps/GameHub/build.sh        # → apps/GameHub/xtool/GameHub.ipa
apps/AdsBlocker/build.sh
apps/Mangalate/build.sh
```

Build xong thì source LAN (`sidestore/`) được cập nhật và server port 8765 tự bật — dùng khi không muốn publish.

## Publish lên GitHub (URL cố định)

```bash
toolkit/publish_github.sh            # sinh source.json + commit/push + upload IPA lên release
toolkit/publish_github.sh --dry-run  # chỉ sinh source.json để xem
```

Biến môi trường: `GH_OWNER` (mặc định `doanhvanvu82`), `GH_REPO` (`ios-apps`), `GH_TAG` (`builds`),
`GH_TOKEN` (không có thì đọc mục `github.com` trong `~/.git-credentials`).

Cấu trúc URL:

| Thứ | URL |
|---|---|
| `source.json` | `https://raw.githubusercontent.com/<owner>/<repo>/main/source/source.json` |
| IPA / icon | `https://github.com/<owner>/<repo>/releases/download/<tag>/<file>` |

`source.json` được commit vào `source/`; IPA (~74 MB) và icon nằm ở GitHub Releases, không nằm trong repo.
Mỗi lần publish, asset của bản cũ bị xoá khỏi release để release không phình ra.

## Cấu trúc

```
toolkit/           — build, version, icon, source AltStore (Ksign), server LAN, publish (dùng chung)
source/            — source.json đã publish (sinh bởi toolkit/publish_github.sh)
apps/<App>/        — mỗi app một thư mục (Package.swift, xtool.yml, Info.plist, Sources/)
```

Không commit: `.build/`, `xtool/`, `*.ipa`, `apps/GameHub/workspace/` (21 GB dữ liệu build game),
bộ lọc sinh lúc build, `toolkit/xtool.AppImage`, `.state/`, `sidestore/` — xem [.gitignore](.gitignore).

## Giới hạn

- Ksign + chứng chỉ: không giới hạn số app/App ID (khác Apple ID miễn phí); rủi ro là chứng chỉ bị thu hồi
  → app ngừng mở, phải ký/cài lại.
- Không chạy được app/simulator trên Linux — chỉ build + kiểm tra IPA; hành vi thực tế do người dùng thử trên iPhone.
- Repo public: bất kỳ ai có URL đều tải được IPA; IPA build ra chưa ký nên người khác tải về phải tự ký bằng Ksign.
