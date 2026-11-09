---
description: "Mod YouTube: Ksign cache IPA theo tên file — version mod nằm trong tên IPA"
evidence:
  - path: "mods/youtube/build.sh"
    quote: "# KHÔNG đổi CFBundleVersion/CFBundleShortVersionString: YouTube gửi chúng"
  - path: "toolkit/sidestore_source.py"
    quote: "    mod = re.search(r\"_mod([0-9.]+)\\.ipa$\", ipa)"
---
Mod YouTube giữ nguyên CFBundleVersion=21.44.4 (InnerTube clientVersion — xem memory youtube-mod-bundle-id) nên Ksign KHÔNG nhận biết bản mới qua Info.plist — nó cache theo URL file. build.sh đặt tên mods/youtube/out/YouTube_orig_21.44.4_mod<ver>.ipa; sidestore_source.py lấy <ver> đó đưa vào tên file source (sidestore/YouTube-21.44.4-mod3.33.ipa) và mô tả ("Build 21.44.4 · mod 3.33") để URL đổi theo mỗi bản mod. Sau khi build: chạy `SOURCE_KEEP_MODS=1 python3 toolkit/sidestore_source.py` (thiếu biến này thì mod bị build-exclude bỏ khỏi source) hoặc toolkit/build_all.sh, rồi restart serve_sidestore.sh. IP LAN đổi theo mạng (192.168.1.212 / 192.168.4.200) — source luôn sinh theo IP hiện tại. Kiểm tra bản trong file: unzip Frameworks/libyoutubemod.dylib rồi grep tag.
