#!/usr/bin/env python3
"""Đổi VideoPlayer dùng asset VideoClip sang phát theo URL (StreamingAssets).

Unity WebGL không phát được VideoClip asset (chỉ phát video theo URL) → nền/cutscene video
đen xì (vd NTR_Kazoku: "BG Video" ở màn title). Với mỗi VideoPlayer có m_DataSource: 0 và
m_VideoClip trỏ tới tệp video trong Assets: chép tệp vào Assets/StreamingAssets/GameHubVideo/,
đặt m_DataSource: 1 + m_Url tương đối so với index.html, bỏ m_VideoClip.

Dùng: unity_videoclip_to_url.py <ExportedProject>
"""
import os
import re
import shutil
import sys

ASSET_EXT = (".unity", ".prefab")
VIDEO_EXT = (".mp4", ".webm", ".mov", ".m4v")
BLOCK = re.compile(r"(--- !u!328 &\d+\nVideoPlayer:\n.*?)(?=^--- |\Z)", re.S | re.M)
CLIP = re.compile(r"^  m_VideoClip: \{fileID: \d+, guid: (\w+), type: 3\}$", re.M)


def video_by_guid(assets):
    found = {}
    for dp, _, fns in os.walk(assets):
        for fn in fns:
            if fn.lower().endswith(VIDEO_EXT) and os.path.isfile(os.path.join(dp, fn + ".meta")):
                meta = open(os.path.join(dp, fn + ".meta"), encoding="utf-8", errors="ignore").read()
                found[re.search(r"^guid:\s*(\w+)", meta, re.M).group(1)] = os.path.join(dp, fn)
    return found


def main():
    project = os.path.abspath(sys.argv[1])
    assets = os.path.join(project, "Assets")
    videos = video_by_guid(assets)
    if not videos:
        return
    dest = os.path.join(assets, "StreamingAssets", "GameHubVideo")
    fixed = 0

    for dp, _, fns in os.walk(assets):
        for fn in fns:
            if not fn.endswith(ASSET_EXT):
                continue
            path = os.path.join(dp, fn)
            text = open(path, encoding="utf-8", errors="ignore").read()
            if "VideoPlayer:" not in text:
                continue

            def patch(m):
                nonlocal fixed
                block = m.group(1)
                clip = CLIP.search(block)
                src = clip and videos.get(clip.group(1))
                if not src or "  m_DataSource: 0\n" not in block:
                    return block
                os.makedirs(dest, exist_ok=True)
                name = os.path.basename(src)
                shutil.copy2(src, os.path.join(dest, name))
                block = block.replace("  m_DataSource: 0\n", "  m_DataSource: 1\n")
                block = CLIP.sub("  m_VideoClip: {fileID: 0}", block)
                block = re.sub(r"^  m_Url:.*$", "  m_Url: StreamingAssets/GameHubVideo/" + name, block, flags=re.M)
                fixed += 1
                return block

            new = BLOCK.sub(patch, text)
            if new != text:
                open(path + ".tmp", "w", encoding="utf-8").write(new)
                os.replace(path + ".tmp", path)
    if fixed:
        print(f"✅ VideoClip: đổi {fixed} VideoPlayer sang URL StreamingAssets (WebGL không phát VideoClip asset)")


if __name__ == "__main__":
    main()
