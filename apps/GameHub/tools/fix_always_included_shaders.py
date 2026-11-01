#!/usr/bin/env python3
"""
Thêm shader của project vào `GraphicsSettings.m_AlwaysIncludedShaders`.

Vì sao cần:
    AssetRipper export project từ game đã build, nhưng các shader chỉ được
    tham chiếu bởi *render pipeline settings* (ví dụ `Renderer2DResources` trong
    `UniversalRenderPipelineGlobalSettings.asset`) thì Unity KHÔNG đưa vào
    build. Thiếu shader → runtime Unity log
    "Cannot create required material because shader is null" rồi crash.

Cách dùng:
    python3 tools/fix_always_included_shaders.py <project-dir> [build-log]
"""
import os
import re
import sys

ROOT = sys.argv[1]
LOG = sys.argv[2] if len(sys.argv) > 2 else "/tmp/unity-build.log"
ASSETS = os.path.join(ROOT, "Assets")
GS = os.path.join(ROOT, "ProjectSettings", "GraphicsSettings.asset")

# --- 1. Shader đã được compile trong build gần nhất ---
compiled = set()
if os.path.isfile(LOG):
    pat = re.compile(r'Serialized binary data for shader (.+?) in ')
    with open(LOG, "r", errors="ignore") as fh:
        for line in fh:
            m = pat.search(line)
            if m:
                compiled.add(m.group(1))

# --- 2. Shader trong project ---
project = []   # (name, guid)
for dirpath, _, files in os.walk(ASSETS):
    for f in files:
        if not f.endswith(".shader"):
            continue
        path = os.path.join(dirpath, f)
        meta = path + ".meta"
        guid = None
        if os.path.isfile(meta):
            with open(meta, "r", errors="ignore") as fh:
                m = re.search(r"^guid:\s*([0-9a-f]{32})", fh.read(), re.M)
            if m:
                guid = m.group(1)
        if not guid:
            continue
        try:
            with open(path, "r", errors="ignore") as fh:
                head = fh.read(4000)
        except OSError:
            continue
        m = re.search(r'Shader\s+"([^"]+)"', head)
        project.append((m.group(1) if m else f, guid))

print(f"Shader trong project: {len(project)}")
print(f"Shader đã compile trong build gần nhất: {len(compiled)}")

missing = [(n, g) for n, g in project if n not in compiled]
if compiled:
    print(f"Shader CHƯA được đưa vào build: {len(missing)}")
    for n, _ in missing:
        print(f"  - {n}")
else:
    print("⚠️  Không đọc được build log — sẽ thêm TẤT CẢ shader của project.")

if not missing:
    print("✅ Không cần thay đổi.")
    sys.exit(0)

# --- 3. Ghi vào GraphicsSettings.asset ---
with open(GS, "r", errors="ignore") as fh:
    text = fh.read()

m = re.search(r"^  m_AlwaysIncludedShaders:\n((?:  - .*\n)*)", text, re.M)
if not m:
    print("❌ Không tìm thấy m_AlwaysIncludedShaders trong GraphicsSettings.asset")
    sys.exit(1)

block = m.group(1)
existing_guids = set(re.findall(r"guid:\s*([0-9a-f]{32})", block))

added = 0
new_lines = []
for name, guid in missing:
    if guid in existing_guids:
        continue
    new_lines.append(f"  - {{fileID: 4800000, guid: {guid}, type: 3}}")
    added += 1

if not added:
    print("✅ Các shader thiếu đã có trong m_AlwaysIncludedShaders.")
    sys.exit(0)

text = text[:m.start(1)] + block + "\n".join(new_lines) + "\n" + text[m.end(1):]
with open(GS, "w", errors="ignore") as fh:
    fh.write(text)

print(f"✅ Đã thêm {added} shader vào m_AlwaysIncludedShaders:")
for line in new_lines:
    print("  " + line)
