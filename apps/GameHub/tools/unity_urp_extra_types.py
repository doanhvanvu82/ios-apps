#!/usr/bin/env python3
"""Khôi phục các class mà game tự nhét vào DLL URP/SRP của nó.

Vài game (vd Beautify của Kronnect) đặt code riêng ngay trong
Unity.RenderPipelines.*.dll. unity_normalize_project.py thay các DLL đó bằng
package URP chuẩn (bản gốc nằm ở PatchBackup/) nên các class này biến mất →
CS0234/CS0246. Script dịch ngược (ilspycmd) mọi kiểu không thuộc namespace
UnityEngine.*/Unity.*/System.*/Microsoft.* trong DLL gốc vào Assets/Scripts/GameHubURPExtras/.

Dùng: unity_urp_extra_types.py <ExportedProject>
"""
import glob
import os
import re
import subprocess
import sys

ILSPY = os.path.expanduser("~/.dotnet/tools/ilspycmd")  # Unity 6 biên dịch C# 9
ENV = dict(os.environ, DOTNET_ROOT=os.path.expanduser("~/.dotnet"), DOTNET_ROLL_FORWARD="Major")


# ilspycmd in thông báo "You are not using the latest version…" ra stdout, lẫn vào mã nguồn.
BANNER = re.compile(r"^(You are not using the latest version of the tool.*|Latest version is '.*)\r?\n?", re.M)
# ilspycmd 8.x sinh `((T)(ref x)).field` khi đọc field của struct qua địa chỉ → C# không hợp lệ.
REF_CAST = re.compile(r"\(\(([\w.]+)\)\(ref ([\w.\[\]]+)\)\)")


# Gọi tường minh `LayerMask.op_Implicit(x)` (chuyển kiểu ngầm) → CS0571; bỏ tên hàm, C# tự chuyển kiểu.
OP_IMPLICIT = re.compile(r"\b[A-Z]\w*\.op_Implicit(?=\()")


# `x..ctor(args);` (gọi constructor struct đã khởi tạo `default`) — C# đọc `..` là toán tử range
# (hàng loạt lỗi "Cannot convert … to System.Index"). Đổi thành `x = new Kiểu(args);`, Kiểu lấy từ
# dòng khai báo gần nhất của biến.
CTOR = re.compile(r"(?m)^(\s*)([\w.]+)\.\.ctor\((.*)\);[ \t]*$")


def fix_ctor(src):
    def repl(m):
        decls = re.findall(r"(?m)^\s*([\w.<>\[\]?]+) " + re.escape(m.group(2)) + r" = ", src[:m.start()])
        return f"{m.group(1)}{m.group(2)} = new {decls[-1]}({m.group(3)});" if decls else m.group(0)
    return CTOR.sub(repl, src)


def clean(src):
    return fix_ctor(OP_IMPLICIT.sub("", REF_CAST.sub(r"\2", BANNER.sub("", src))))


# Phần vẽ của Beautify dùng API nội bộ URP 12 (ScriptableRenderer.SwapColorBuffer…, internal ở URP 17)
# nên bản dịch ngược không biên dịch được. Giữ kiểu rỗng (asset renderer vẫn tham chiếu được),
# game chỉ mất hiệu ứng hậu kỳ Beautify.
STUBS = {
    "Beautify.Universal.BeautifyRendererFeature": """using UnityEngine.Rendering.Universal;

namespace Beautify.Universal
{
	public class BeautifyRendererFeature : ScriptableRendererFeature
	{
		public override void Create()
		{
		}

		public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
		{
		}
	}
}
""",
}


def apply_stubs(out_dir):
    for name, source in STUBS.items():
        path = os.path.join(out_dir, name + ".cs")
        if os.path.exists(path) and open(path, encoding="utf-8").read() != source:
            open(path + ".tmp", "w", encoding="utf-8").write(source)
            os.replace(path + ".tmp", path)
            print(f"⚠️  URP extras: {name} thay bằng lớp rỗng (mất hiệu ứng hậu kỳ, game vẫn chạy)")


def extra_types(dll):
    out = subprocess.run([ILSPY, "-l", "cisde", dll], env=ENV, capture_output=True, text=True).stdout
    listed = [m.group(2) for m in (re.match(r"^(Class|Interface|Struct|Delegate|Enum) (\S+)$", l.strip()) for l in out.splitlines())
              if m and "<" not in m.group(2)]
    # Bỏ kiểu lồng: ilspycmd -t với kiểu cha đã kèm kiểu con.
    nested = {n for n in listed if any(n.startswith(p + ".") for p in listed)}
    names = []
    for name in listed:
        if name in nested:
            continue
        # Kiểu không namespace thuộc URP chuẩn hoặc do Unity sinh (UnitySourceGenerated…).
        if "." not in name or name.split(".")[0] in ("UnityEngine", "Unity", "UnityEditor", "System", "Microsoft") \
                or name.startswith("UnitySourceGenerated"):
            continue
        names.append(name)
    return names


def main():
    project = os.path.abspath(sys.argv[1])
    out_dir = os.path.join(project, "Assets", "Scripts", "GameHubURPExtras")
    if os.path.isdir(out_dir):
        # Project dựng trước khi có clean(): sửa lại file đã sinh.
        fixed = 0
        for path in glob.glob(os.path.join(out_dir, "*.cs")):
            old = open(path, encoding="utf-8").read()
            new = clean(old)
            if new != old:
                open(path + ".tmp", "w", encoding="utf-8").write(new)
                os.replace(path + ".tmp", path)
                fixed += 1
        print(f"✅ URP extras: đã khôi phục từ trước — bỏ qua" + (f" (làm sạch {fixed} file)." if fixed else "."))
        apply_stubs(out_dir)
        return
    if not os.access(ILSPY, os.X_OK):
        print("⚠️  URP extras: không có ilspycmd — bỏ qua.")
        return
    restored = []
    for dll in sorted(glob.glob(os.path.join(project, "PatchBackup", "Unity.RenderPipelines.*.dll"))):
        for name in extra_types(dll):
            src = subprocess.run([ILSPY, "-lv", "CSharp9_0", "-t", name, dll], env=ENV, capture_output=True, text=True).stdout
            if not src.strip():
                continue
            os.makedirs(out_dir, exist_ok=True)
            with open(os.path.join(out_dir, name + ".cs"), "w", encoding="utf-8") as fh:
                fh.write(clean(src))
            if name not in restored:
                restored.append(name)
    if restored:
        apply_stubs(out_dir)
        print(f"✅ URP extras: khôi phục {len(restored)} kiểu game nhúng trong DLL URP: {', '.join(restored[:6])}{'…' if len(restored) > 6 else ''}")
    else:
        print("✅ URP extras: DLL URP của game không có kiểu riêng.")


if __name__ == "__main__":
    main()
