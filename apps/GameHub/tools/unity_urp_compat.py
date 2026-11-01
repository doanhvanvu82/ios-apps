#!/usr/bin/env python3
"""Cho game URP cũ (URP 10–14) biên dịch được trên Unity 6 / URP 17.

    unity_urp_compat.py <project-dir>

URP 17 đánh dấu các API cũ `[Obsolete(..., true)]` (lỗi CS0619) và thân hàm
ném NotSupportedException: `RenderTargetHandle`, `cameraColorTarget`,
`ConfigureTarget(RenderTargetIdentifier)`, `Blit(RenderTargetIdentifier…)`…
Mã game dịch ngược bằng AssetRipper dùng các API này → "Scripts have
compiler errors".

Cách làm: nhúng bản URP đi kèm Editor vào `Packages/` (package nhúng được ưu
tiên hơn bản trong registry), đổi các Obsolete-error thành cảnh báo và cài lại
thân hàm cũ bằng API RTHandle tương ứng. Chỉ chạy khi mã game thật sự dùng API
cũ. Lưu ý: Unity 6 bật RenderGraph mặc định — pass cũ chỉ có Execute() sẽ bị
URP bỏ qua (mất hiệu ứng riêng) nhưng game vẫn chạy.
"""
import json
import os
import re
import shutil
import sys

PKG = "com.unity.render-pipelines.universal"
EDITOR = os.environ.get("UNITY_HOME", os.path.expanduser("~/Unity")) + "/Editor"
BUILTIN = os.path.join(EDITOR, "Data/Resources/PackageManager/BuiltInPackages", PKG)

LEGACY_API = re.compile(
    r"\bRenderTargetHandle\b|\bcameraColorTarget\b(?!Handle)|\bcameraDepthTarget\b(?!Handle)"
    r"|\bcolorAttachment\b(?!Handle)|\bdepthAttachment\b(?!Handle)")

COMPAT_CS = '''using System.Collections.Generic;
using UnityEngine.Rendering;

namespace UnityEngine.Rendering.Universal
{
    // GameHub: bọc RenderTargetIdentifier thành RTHandle cho các API cũ
    // (unity_urp_compat.py). Cache theo identifier để không cấp phát mỗi frame.
    internal static class GameHubRTCompat
    {
        static readonly Dictionary<RenderTargetIdentifier, RTHandle> s_Handles = new Dictionary<RenderTargetIdentifier, RTHandle>();

        internal static RTHandle Wrap(RenderTargetIdentifier id)
        {
            if (!s_Handles.TryGetValue(id, out var handle))
            {
                handle = RTHandles.Alloc(id);
                s_Handles[id] = handle;
            }
            return handle;
        }

        internal static RTHandle[] Wraps(RenderTargetIdentifier[] ids)
        {
            var handles = new RTHandle[ids.Length];
            for (int i = 0; i < ids.Length; i++) handles[i] = Wrap(ids[i]);
            return handles;
        }

        internal static RenderTargetIdentifier Id(RTHandle handle)
        {
            return handle != null ? handle.nameID : (RenderTargetIdentifier)BuiltinRenderTextureType.CameraTarget;
        }

        internal static RenderTargetIdentifier[] Ids(RTHandle[] handles)
        {
            var ids = new RenderTargetIdentifier[handles.Length];
            for (int i = 0; i < handles.Length; i++) ids[i] = Id(handles[i]);
            return ids;
        }
    }
}
'''

# (chữ ký hàm cũ, thân mới) — thân cũ chỉ có một lệnh `throw new NotSupportedException(...)`.
METHOD_BODIES = [
    ("public void ConfigureTarget(RenderTargetIdentifier colorAttachment, RenderTargetIdentifier depthAttachment)",
     "ConfigureTarget(GameHubRTCompat.Wrap(colorAttachment), GameHubRTCompat.Wrap(depthAttachment));"),
    ("public void ConfigureTarget(RenderTargetIdentifier[] colorAttachments, RenderTargetIdentifier depthAttachment)",
     "ConfigureTarget(GameHubRTCompat.Wraps(colorAttachments), GameHubRTCompat.Wrap(depthAttachment));"),
    ("public void ConfigureTarget(RenderTargetIdentifier colorAttachment)",
     "ConfigureTarget(GameHubRTCompat.Wrap(colorAttachment));"),
    ("public void ConfigureTarget(RenderTargetIdentifier[] colorAttachments)",
     "ConfigureTarget(GameHubRTCompat.Wraps(colorAttachments));"),
    ("public void Blit(CommandBuffer cmd, RenderTargetIdentifier source, RenderTargetIdentifier destination, Material material = null, int passIndex = 0)",
     "Blit(cmd, GameHubRTCompat.Wrap(source), GameHubRTCompat.Wrap(destination), material, passIndex);"),
    ("public void ConfigureCameraTarget(RenderTargetIdentifier colorTarget, RenderTargetIdentifier depthTarget)",
     "ConfigureCameraTarget(GameHubRTCompat.Wrap(colorTarget), GameHubRTCompat.Wrap(depthTarget));"),
]

# Thuộc tính `=> throw ...;` → giá trị từ RTHandle tương ứng.
PROPERTIES = [
    ("public RenderTargetIdentifier cameraColorTarget", "GameHubRTCompat.Id(m_CameraColorTarget)"),
    ("public RenderTargetIdentifier cameraDepthTarget", "GameHubRTCompat.Id(m_CameraDepthTarget)"),
    ("public RenderTargetIdentifier[] colorAttachments", "GameHubRTCompat.Ids(m_ColorAttachments)"),
    ("public RenderTargetIdentifier[] colorAttachment", "GameHubRTCompat.Ids(m_ColorAttachments)"),
    ("public RenderTargetIdentifier depthAttachment", "GameHubRTCompat.Id(m_DepthAttachment)"),
]


def uses_legacy_api(project):
    for dp, _, fns in os.walk(os.path.join(project, "Assets")):
        for fn in fns:
            if not fn.endswith(".cs"):
                continue
            try:
                text = open(os.path.join(dp, fn), encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            if LEGACY_API.search(text) or ("ScriptableRenderPass" in text and "RenderTargetIdentifier" in text):
                return True
    return False


def patch_package(dst):
    changed = 0
    for dp, _, fns in os.walk(dst):
        for fn in fns:
            if not fn.endswith(".cs"):
                continue
            path = os.path.join(dp, fn)
            text = open(path, encoding="utf-8-sig").read()
            new = re.sub(r"\[Obsolete\(([^\[\]]*?),\s*true\)\]", r"[Obsolete(\1, false)]", text)
            for signature, body in METHOD_BODIES:
                new = re.sub(re.escape(signature) + r"(\s*\{\s*)throw new NotSupportedException\([^;]*\);",
                             lambda m: signature + m.group(1) + body, new)
            for decl, value in PROPERTIES:
                new = re.sub(re.escape(decl) + r"\s*=>\s*throw new NotSupportedException\([^;]*\);",
                             lambda m: decl + " => " + value + ";", new)
            if new != text:
                open(path, "w", encoding="utf-8").write(new)
                changed += 1
    open(os.path.join(dst, "Runtime", "GameHubRTCompat.cs"), "w", encoding="utf-8").write(COMPAT_CS)
    return changed


def main():
    project = os.path.abspath(sys.argv[1])
    manifest = os.path.join(project, "Packages", "manifest.json")
    try:
        deps = json.load(open(manifest)).get("dependencies", {})
    except (OSError, ValueError):
        return
    if PKG not in deps:
        return
    dst = os.path.join(project, "Packages", PKG)
    if os.path.isdir(dst):
        print("✅ URP compat: đã nhúng sẵn — bỏ qua.")
        return
    if not uses_legacy_api(project):
        print("✅ URP compat: mã game không dùng API URP cũ — bỏ qua.")
        return
    if not os.path.isdir(BUILTIN):
        print(f"⚠️  URP compat: không thấy {BUILTIN}", file=sys.stderr)
        return
    shutil.copytree(BUILTIN, dst)
    changed = patch_package(dst)
    print(f"✅ URP compat: nhúng {PKG} vào Packages/, vá {changed} file (API cũ → cảnh báo + cài lại bằng RTHandle).")


if __name__ == "__main__":
    main()
