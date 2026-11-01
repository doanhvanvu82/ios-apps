// Patch spine-unity.dll để build Unity WebGL không bị lỗi
// "Destroy may not be called from edit mode! Use DestroyImmediate instead."
//
// Nguyên nhân: Spine runtime (bản 3.x/4.0) implement
//     SmartMesh.Dispose() { if (mesh != null) { Object.Destroy(mesh); mesh = null; } }
// Object.Destroy() chỉ hợp lệ ở play mode. Khi Unity Editor build player trong
// batchmode, các object trong scene bị destroy ở edit mode → log error → build fail.
//
// Fix: đổi thành
//     if (Application.isPlaying) Object.Destroy(mesh);
//     else                    Object.DestroyImmediate(mesh);
//
// Cách dùng:
//   mono patch_spine_editmode.exe <đường-dẫn-tới-spine-unity.dll>
//
using System;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

public static class PatchSpine
{
    const string ObjectType = "UnityEngine.Object";

    public static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.Error.WriteLine("Usage: patch_spine_editmode <spine-unity.dll>");
            return 1;
        }

        string dllPath = args[0];
        if (!File.Exists(dllPath))
        {
            Console.Error.WriteLine("Không tìm thấy: " + dllPath);
            return 1;
        }

        // Backup phải nằm NGOÀI Assets/ — nếu để trong Assets/Unity sẽ import
        // file .orig như một plugin DLL khác.
        string backupDir = BackupDir(dllPath);
        Directory.CreateDirectory(backupDir);
        string backup = Path.Combine(backupDir, Path.GetFileName(dllPath) + ".orig");

        if (File.Exists(backup)) {
            // Luôn patch lại từ bản gốc → idempotent và tự sửa được bản patch hỏng.
            File.Copy(backup, dllPath, true);
        } else {
            File.Copy(dllPath, backup);
            Console.WriteLine("→ Backup bản gốc: " + backup);
        }

        int patched;
        string tmp = dllPath + ".patched";

        // Cecil cần resolve được UnityEngine.* để ghi metadata.
        var resolver = new DefaultAssemblyResolver();
        foreach (var dir in ResolveDirs())
            resolver.AddSearchDirectory(dir);

        using (var assembly = AssemblyDefinition.ReadAssembly(dllPath,
            new ReaderParameters { AssemblyResolver = resolver }))
        {
            patched = PatchAssembly(assembly);

            if (patched > 0)
            {
                // Không ghi đè file đang mở (Cecil giữ file handle) → ghi ra file tạm.
                assembly.Write(tmp);
            }
        }

        if (patched == 0)
        {
            Console.WriteLine("ℹ️  Không có method nào cần patch (có thể đã patch rồi).");
            return 0;
        }

        File.Copy(tmp, dllPath, true);
        File.Delete(tmp);

        Console.WriteLine("✅ Đã patch " + patched + " method trong " + Path.GetFileName(dllPath));
        return 0;
    }

    /// <summary>Tìm thư mục cha của Assets/ để đặt bản backup ra ngoài Assets.</summary>
    static string BackupDir(string dllPath)
    {
        var dir = new DirectoryInfo(Path.GetDirectoryName(Path.GetFullPath(dllPath)));
        while (dir != null && !string.Equals(dir.Name, "Assets", StringComparison.OrdinalIgnoreCase))
            dir = dir.Parent;
        if (dir == null || dir.Parent == null) return Path.GetTempPath();
        return Path.Combine(dir.Parent.FullName, "PatchBackup");
    }

    static string[] ResolveDirs()
    {
        string home = Environment.GetEnvironmentVariable("HOME") ?? "";
        string unity = Environment.GetEnvironmentVariable("UNITY_HOME")
            ?? Path.Combine(home, "Unity");

        return new[]
        {
            Path.Combine(unity, "Editor", "Data", "Managed"),
            Path.Combine(unity, "Editor", "Data", "Managed", "UnityEngine"),
            Path.Combine(unity, "Editor", "Data", "PlaybackEngines", "WebGLSupport", "Managed"),
            Path.Combine(home, ".local", "share", "unity3d"),
        };
    }

    static int PatchAssembly(AssemblyDefinition assembly)
    {
        int patched = 0;

        foreach (var module in assembly.Modules)
        {
            foreach (var type in module.GetTypes())
            {
                foreach (var method in type.Methods)
                {
                    if (!method.HasBody) continue;
                    if (method.Name != "Dispose") continue;

                    var callDestroy = method.Body.Instructions.FirstOrDefault(i =>
                        i.OpCode == OpCodes.Call &&
                        i.Operand is MethodReference mr &&
                        mr.Name == "Destroy" &&
                        mr.DeclaringType.FullName == ObjectType);

                    if (callDestroy == null) continue;

                    // Đã patch rồi → bỏ qua.
                    if (method.Body.Instructions.Any(i =>
                        i.OpCode == OpCodes.Call &&
                        i.Operand is MethodReference mr2 &&
                        mr2.Name == "DestroyImmediate"))
                        continue;

                    var destroyRef = (MethodReference)callDestroy.Operand;

                    // op_Inequality(Object, Object) — lấy từ body gốc.
                    var opInequality = method.Body.Instructions
                        .Where(i => i.OpCode == OpCodes.Call && i.Operand is MethodReference m)
                        .Select(i => (MethodReference)i.Operand)
                        .FirstOrDefault(m => m.Name == "op_Inequality" && m.DeclaringType.FullName == ObjectType);

                    if (opInequality == null) continue;

                    var meshField = method.DeclaringType.Fields.FirstOrDefault(f => f.Name == "mesh");
                    if (meshField == null) continue;

                    // UnityEngine.Object.DestroyImmediate(Object)
                    var destroyImmediateRef = new MethodReference(
                        "DestroyImmediate", destroyRef.ReturnType, destroyRef.DeclaringType)
                    {
                        HasThis = destroyRef.HasThis
                    };
                    foreach (var p in destroyRef.Parameters)
                        destroyImmediateRef.Parameters.Add(p);

                    // UnityEngine.Application.get_isPlaying()
                    // Lưu ý: `isPlaying` là **static property** → getter cũng phải static
                    // (HasThis = false), nếu không runtime sẽ ném MissingMethodException.
                    // Scope phải là UnityEngine.CoreModule (lấy từ chính UnityEngine.Object).
                    var appType = new TypeReference("UnityEngine", "Application", module,
                        destroyRef.DeclaringType.Scope);
                    var isPlayingRef = new MethodReference("get_isPlaying",
                        module.TypeSystem.Boolean, appType)
                    {
                        HasThis = false
                    };

                    // --- Dựng lại toàn bộ method body ---
                    var lEnd = Instruction.Create(OpCodes.Nop);
                    var lPlay = Instruction.Create(OpCodes.Nop);

                    var body = new System.Collections.Generic.List<Instruction>
                    {
                        Instruction.Create(OpCodes.Ldarg_0),
                        Instruction.Create(OpCodes.Ldfld, meshField),
                        Instruction.Create(OpCodes.Ldnull),
                        Instruction.Create(OpCodes.Call, opInequality),
                        Instruction.Create(OpCodes.Brfalse, lEnd),

                        Instruction.Create(OpCodes.Call, isPlayingRef),
                        Instruction.Create(OpCodes.Brtrue, lPlay),

                        Instruction.Create(OpCodes.Ldarg_0),
                        Instruction.Create(OpCodes.Ldfld, meshField),
                        Instruction.Create(OpCodes.Call, destroyImmediateRef),
                        Instruction.Create(OpCodes.Br, lEnd),

                        lPlay,
                        Instruction.Create(OpCodes.Ldarg_0),
                        Instruction.Create(OpCodes.Ldfld, meshField),
                        Instruction.Create(OpCodes.Call, destroyRef),

                        lEnd,
                        Instruction.Create(OpCodes.Ldarg_0),
                        Instruction.Create(OpCodes.Ldnull),
                        Instruction.Create(OpCodes.Stfld, meshField),
                        Instruction.Create(OpCodes.Ret)
                    };

                    method.Body.Instructions.Clear();
                    var il = method.Body.GetILProcessor();
                    foreach (var ins in body)
                        il.Append(ins);

                    patched++;
                }
            }
        }

        return patched;
    }
}
