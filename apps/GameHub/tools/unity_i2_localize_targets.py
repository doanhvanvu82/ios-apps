#!/usr/bin/env python3
"""Bỏ các asset I2 Localization `LocalizeTarget_*` mà AssetRipper tách ra thành file riêng.

I2 Localization (hay đi kèm Naninovel) lưu mỗi `Localize` một ScriptableObject
`LocalizeTarget_TextMeshPro_UGUI` (…) trỏ vào thành phần chữ trong scene/prefab.
AssetRipper xuất chúng thành `Assets/MonoBehaviour/MonoBehaviour_N.asset`; khi Unity
import một asset như vậy nó đọc object của scene từ luồng nền và lặp vô hạn dòng
"Do not use ReadObjectThreaded on scene objects!" (hàng chục triệu dòng, ~7 GB RAM,
log nhiều GB) → build treo.

Các asset này chỉ là bộ nhớ đệm đích bản địa hoá: `Localize` tự tìm lại đích khi
thiếu (FindTarget), nên chuyển chúng ra PatchBackup/ là đủ.

Dùng: unity_i2_localize_targets.py <ExportedProject>
"""
import glob
import os
import re
import shutil
import sys

GUID = re.compile(r"^guid: ([0-9a-f]{32})", re.M)
SCRIPT = re.compile(r"m_Script: \{[^}]*guid: ([0-9a-f]{32})")


def main():
    project = os.path.abspath(sys.argv[1])
    assets = os.path.join(project, "Assets")
    guids = set()
    for meta in glob.glob(os.path.join(assets, "**", "LocalizeTarget_*.cs.meta"), recursive=True):
        m = GUID.search(open(meta, encoding="utf-8", errors="ignore").read())
        if m:
            guids.add(m.group(1))
    if not guids:
        return

    moved = 0
    for dp, _, fns in os.walk(assets):
        for fn in fns:
            if not fn.endswith(".asset"):
                continue
            path = os.path.join(dp, fn)
            with open(path, encoding="utf-8", errors="ignore") as fh:
                head = fh.read(800)
            m = SCRIPT.search(head)
            if not m or m.group(1) not in guids:
                continue
            rel = os.path.relpath(path, project)
            backup = os.path.join(project, "PatchBackup", "dropped", rel)
            os.makedirs(os.path.dirname(backup), exist_ok=True)
            for suffix in ("", ".meta"):
                if os.path.exists(path + suffix):
                    shutil.move(path + suffix, backup + suffix)
            moved += 1
    if moved:
        print(f"✅ I2 Localization: chuyển {moved} asset LocalizeTarget ra PatchBackup/ (tránh vòng lặp ReadObjectThreaded)")


if __name__ == "__main__":
    main()
