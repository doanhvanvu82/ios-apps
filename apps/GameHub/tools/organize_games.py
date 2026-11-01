#!/usr/bin/env python3
"""
Phân loại game trong ~/Documents/Game vào 4 nhóm:

    1-ChoiDungTrucTiep/   — chạy được ngay (RPG Maker, TyranoBuilder, HTML5,
                            Godot/KiriKiri/Flash/Ren'Py 8.3 bản gốc nhờ runtime
                            trong app, game NW.js đóng gói trong .exe)
    2-DaBuildLai/         — bản web ĐÃ build xong (output của tools/build_all.sh)
    2-CanBuildLai/        — cần build lại (Unity Mono, Ren'Py khác 8.3, NSIS-Godot…)
    3-ChuaChoiDuoc/       — chưa chơi được (Unity IL2CPP, GameMaker, BGI…)

Dùng:
    python3 tools/organize_games.py              # xem kế hoạch (mặc định)
    python3 tools/organize_games.py --apply      # di chuyển thật
    python3 tools/organize_games.py --status     # chỉ báo game MỚI / ĐỔI NHÓM

Nguyên tắc:
  • Game mới thả vào `~/Documents/Game/` (gốc) → sẽ tự được phân loại.
  • Game đã nằm trong nhóm → giữ nguyên, trừ khi detector đổi kết luận
    (ví dụ bạn nâng cấp detector) thì sẽ được chuyển sang nhóm đúng.
  • `2-DaBuildLai/` KHÔNG bị đụng tới: đó là output build, không phải game gốc.
  • Không bao giờ xoá game.
"""
import glob
import json
import os
import shutil
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
# Nhận diện bằng chính EngineDetector.swift của app (tools/detector-cli) — trước
# đây dùng bản Python viết lại nên lệch mỗi khi app thêm loại game mới.
DETECTOR_PKG = os.path.join(_HERE, "detector-cli")
DETECTOR_BIN = os.path.join(DETECTOR_PKG, ".build", "release", "detector-cli")

GAMES_DIR = os.path.expanduser("~/Documents/Game")
APPLY = "--apply" in sys.argv
STATUS = "--status" in sys.argv

# 2-DaBuildLai là OUTPUT của build — chỉ liệt kê, không phân loại lại.
BUILT_GROUP = "2-DaBuildLai"
GROUPS = ("1-ChoiDungTrucTiep", "2-DaBuildLai", "2-CanBuildLai", "3-ChuaChoiDuoc")
GROUP_PREFIX = ("1-", "2-", "3-")

def ensure_detector():
    """Build detector-cli nếu chưa có hoặc mã nhận diện của app mới hơn."""
    sources = glob.glob(os.path.join(DETECTOR_PKG, "Sources", "detector-cli", "*.swift"))
    newest = max(os.path.getmtime(os.path.realpath(f)) for f in sources)
    if os.path.isfile(DETECTOR_BIN) and os.path.getmtime(DETECTOR_BIN) >= newest:
        return
    print("… build tools/detector-cli (EngineDetector của app)", flush=True)
    # Cùng toolchain với build.sh — swift không nằm trong PATH.
    toolchain = os.environ.get("IOS_TOOLCHAIN", os.path.expanduser("~/swift-dev"))
    swift = shutil.which("swift") or os.path.join(toolchain, "usr", "bin", "swift")
    subprocess.run([swift, "build", "-c", "release", "--package-path", DETECTOR_PKG],
                   check=True, stdout=subprocess.DEVNULL)


def detect_all(paths):
    """→ {path: {"engine", "name", "playable", "reason", "entry", "packed"}}"""
    if not paths:
        return {}
    ensure_detector()
    out = subprocess.run([DETECTOR_BIN, *paths], check=True, capture_output=True, text=True).stdout
    rows = [json.loads(line) for line in out.splitlines() if line.strip()]
    return {r["path"]: r for r in rows}


def has_real_mono_assembly(path):
    """Game IL2CPP nhưng còn giữ bản Mono gốc (Managed/Assembly-CSharp.dll).

    Dev thường build Mono trước rồi mới đổi sang IL2CPP, và quên dọn thư mục
    backup (`*_BackUpThisFolder*`). Bản Mono đó **có IL thật** → decompile được
    → build lại WebGL được.
    """
    for dp, dn, fn in os.walk(path):
        depth = dp.count(os.sep) - path.count(os.sep)
        if depth > 4:
            dn[:] = []
            continue
        if os.path.basename(dp) != "Managed":
            continue
        if "Assembly-CSharp.dll" not in fn:
            continue
        # BepInEx interop là proxy → không có logic
        if "BepInEx" in dp or "interop" in dp.lower():
            continue
        return True
    return False


def has_flash_swf(path):
    """Có file .swf (Adobe Flash) → chạy được bằng Ruffle."""
    n = 0
    for dp, dn, fn in os.walk(path):
        for f in fn:
            if f.lower().endswith(".swf"):
                n += 1
                if n >= 2:
                    return True
    return False


def is_nsis_with_godot_pck(path):
    """Installer NSIS (.exe lớn) chứa file `pck` của Godot.

    7-Zip đọc được cấu trúc NSIS → lấy được `pck` → export HTML5 được.
    """
    import subprocess
    for dp, dn, fn in os.walk(path):
        for f in fn:
            if not f.lower().endswith(".exe"):
                continue
            p = os.path.join(dp, f)
            try:
                if os.path.getsize(p) < 50 * 1024 * 1024:
                    continue
            except OSError:
                continue
            try:
                out = subprocess.run(["7z", "l", p], capture_output=True, timeout=90).stdout
            except Exception:
                continue
            if b"\tpck" in out or b" pck" in out:
                return True
    return False


def kirikiri_variant(path):
    """→ 'kirikiroid2' | 'eairpg' | 'bgi' | None

    Runtime `kirikiroid2-web` chỉ chạy được engine **KiriKiri2** (archive `.xp3`).
    - EAIRPG dùng đuôi `.eog` và file `qSavedata.dat`
    - BGI/Ethornell dùng `ExHIBIT.*`, `RESIDENT.*` và thư mục `res/`
    """
    xp3 = eog = exhibit = False
    for dp, dn, fn in os.walk(path):
        if dp.count(os.sep) - path.count(os.sep) > 3:
            dn[:] = []
            continue
        for f in fn:
            low = f.lower()
            if low.endswith(".xp3"):
                xp3 = True
            elif low.endswith(".eog") or low.startswith("qsavedata"):
                eog = True
            elif low.startswith("exhibit") or low.startswith("resident."):
                exhibit = True
    if exhibit:
        return "bgi"
    if xp3:
        return "kirikiroid2"
    if eog:
        return "eairpg"
    return None


PLAYABLE_REASONS = {
    "godotNative": "Godot gốc (.pck rời hoặc nhúng trong .exe) — runtime Godot web trong app",
    "kirikiNative": "KiriKiri2 .xp3 gốc — kirikiroid2-web trong app chạy qua WebDAV",
    "flashNative": "Flash .swf gốc — Ruffle trong app chạy được",
    "renpyNative": "Ren'Py 8.3 bản PC — runtime web Ren'Py trong app",
}


def classify(path, row):
    """→ (nhóm, engine, lý do). `row`: kết quả detector-cli của `path`."""
    if row is None:
        return "3-ChuaChoiDuoc", "unknown", "detector-cli không trả kết quả"
    eng = row["engine"]

    if row["playable"]:
        reason = PLAYABLE_REASONS.get(eng, "chạy được ngay")
        if row["packed"]:
            reason += " (đóng gói .asar / zip trong .exe)"
        return "1-ChoiDungTrucTiep", eng, reason

    if eng == "renpyOtherVersion":
        # Khác phiên bản runtime trong app → build bản web (tools/renpy_batch_build.sh).
        return "2-CanBuildLai", eng, "Ren'Py khác 8.3 — build bản web bằng tools/renpy_batch_build.sh"

    if eng == "unityWindows":
        return "2-CanBuildLai", "unityMono", "Unity Mono — build WebGL được"

    if eng == "unityIL2CPP":
        if has_real_mono_assembly(path):
            return "2-CanBuildLai", "unityIL2CPP+mono", "Unity IL2CPP nhưng còn bản Mono gốc → dựng lại được"
        return "3-ChuaChoiDuoc", eng, row["reason"]

    if eng == "adobeAIR":
        # AIR thực chất chỉ là container SWF → Ruffle chạy được
        if has_flash_swf(path):
            return "2-CanBuildLai", "adobeAIR→flash", "Adobe AIR (chứa .swf) — chạy được bằng Ruffle"
        return "3-ChuaChoiDuoc", "adobeAIR", "Adobe AIR — runtime đã ngừng hoạt động"

    if eng == "flashSWF":
        if has_flash_swf(path):
            return "2-CanBuildLai", "flashSWF", "Flash .swf — chạy được bằng Ruffle"
        return "3-ChuaChoiDuoc", "flashSWF", "Flash SWF — không đủ file .swf"

    if eng == "unknown":
        # Installer NSIS chứa pck của Godot
        if is_nsis_with_godot_pck(path):
            return "2-CanBuildLai", "godot-nsis", "Installer NSIS chứa Godot .pck — export HTML5 được"
        return "3-ChuaChoiDuoc", "unknown", "không nhận diện được engine (thiếu file game)"

    if eng in ("kirikiri", "godot", "exhibit"):
        # Game EAIRPG/BGI có thể chứa file `.pck` (voice pack) → detector nhận nhầm
        # là Godot. Kiểm tra lại trước.
        variant = kirikiri_variant(path)
        if variant == "kirikiroid2":
            return "2-CanBuildLai", "kirikiroid2", "KiriKiri2 (.xp3) — runtime kirikiroid2-web chạy được"
        if variant == "eairpg":
            return "3-ChuaChoiDuoc", "eairpg", "EAIRPG (.eog) — runtime kirikiroid2-web không hỗ trợ"
        if variant == "bgi":
            return "3-ChuaChoiDuoc", "bgi", "BGI/Ethornell (ExHIBIT) — chưa có runtime web"
        if eng == "godot":
            return "2-CanBuildLai", "godot", "Godot — export HTML5 được"
        if eng == "exhibit":
            return "3-ChuaChoiDuoc", eng, row["reason"]
        return "3-ChuaChoiDuoc", "kirikiri?", "không xác định được biến thể KiriKiri"

    return "3-ChuaChoiDuoc", eng, row["reason"] or "chưa có pipeline"


def scan():
    """→ (mọi game, thay đổi cần làm)

    Mỗi game: {"name", "path", "current", "target", "eng", "reason", "is_new"}
    """
    games = []
    pending = []  # (path, dict game) cần phân loại
    for entry in sorted(os.listdir(GAMES_DIR)):
        p = os.path.join(GAMES_DIR, entry)
        if not os.path.isdir(p):
            continue

        if entry.startswith(GROUP_PREFIX):
            if entry == BUILT_GROUP:
                # Output của build_all.sh — chỉ liệt kê, KHÔNG phân loại lại
                # (detector sẽ nhìn thấy index.html và tưởng là game web gốc).
                for sub in sorted(os.listdir(p)):
                    sp = os.path.join(p, sub)
                    if not os.path.isdir(sp):
                        continue
                    games.append({
                        "name": sub, "path": sp, "current": entry,
                        "target": entry, "eng": "builtWeb",
                        "reason": "bản web đã build — output của tools/build_all.sh",
                        "is_new": False,
                    })
                continue
            # Thư mục nhóm → game nằm bên trong
            for sub in sorted(os.listdir(p)):
                sp = os.path.join(p, sub)
                if not os.path.isdir(sp):
                    continue
                game = {"name": sub, "path": sp, "current": entry, "is_new": False}
                games.append(game)
                pending.append(game)
        else:
            # Game mới nằm ở gốc
            game = {"name": entry, "path": p, "current": None, "is_new": True}
            games.append(game)
            pending.append(game)

    rows = detect_all([g["path"] for g in pending])
    for g in pending:
        g["target"], g["eng"], g["reason"] = classify(g["path"], rows.get(g["path"]))
    return games


def main():
    if not os.path.isdir(GAMES_DIR):
        print(f"❌ Không thấy {GAMES_DIR}")
        return 1

    games = scan()
    total = len(games)
    new = [g for g in games if g["is_new"]]
    changed = [g for g in games if g["current"] and g["current"] != g["target"]]

    # --- Báo cáo ---
    print(f"════════ {GAMES_DIR} ════════\n")
    print(f"  Tổng: {total} game   |   Mới: {len(new)}   |   Đổi nhóm: {len(changed)}\n")

    for group in GROUPS:
        items = [g for g in games if g["target"] == group]
        print(f"┌─ {group} ({len(items)} game)")
        by_eng = {}
        for g in items:
            by_eng.setdefault((g["eng"], g["reason"]), []).append(g)
        for (eng, reason), lst in sorted(by_eng.items(), key=lambda x: -len(x[1])):
            print(f"│  {eng} — {reason}")
            for g in lst:
                mark = "  ← MỚI" if g["is_new"] else (
                    f"  ← đổi từ {g['current']}" if g["current"] != g["target"] else "")
                print(f"│     • {g['name']}{mark}")
        print("└─\n")

    if STATUS:
        if not new and not changed:
            print("✅ Không có gì cần phân loại. Thư mục đã cập nhật.")
        return 0

    if not APPLY:
        if new or changed:
            print(f"→ Có {len(new)} game mới và {len(changed)} game cần đổi nhóm.")
            print("  Chạy lại với --apply để thực hiện.")
        else:
            print("✅ Không có gì cần phân loại.")
        return 0

    # --- Thực thi ---
    moved = 0
    for g in games:
        if g["current"] == g["target"]:
            continue  # đã đúng chỗ
        dest_root = os.path.join(GAMES_DIR, g["target"])
        os.makedirs(dest_root, exist_ok=True)
        dst = os.path.join(dest_root, g["name"])
        if os.path.exists(dst):
            print(f"⚠️  Bỏ qua (đích đã tồn tại): {g['name']}")
            continue
        shutil.move(g["path"], dst)
        print(f"✅ {g['name']} → {g['target']}/")
        moved += 1

    print(f"\n{'✅ Đã phân loại ' + str(moved) + ' game' if moved else '✅ Không có gì cần di chuyển'}!")
    for group in GROUPS:
        p = os.path.join(GAMES_DIR, group)
        n = len([x for x in os.listdir(p) if os.path.isdir(os.path.join(p, x))]) if os.path.isdir(p) else 0
        print(f"   {group}: {n} game")
    return 0


if __name__ == "__main__":
    sys.exit(main())
