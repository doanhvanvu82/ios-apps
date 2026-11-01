// Vá DLL plugin biên dịch với TextMeshPro cũ để IL2CPP của Unity 6 link được.
//
// TextMeshPro cũ: `TMP_Asset.material`, `hashCode`, `materialHashCode` là FIELD.
// TextMeshPro trong com.unity.ugui 2.0 (Unity 6) đổi thành PROPERTY → DLL dựng
// sẵn (vd Elringus.BlendModes.Runtime.dll) làm IL2CPP báo
// "Unresolved field reference : UnityEngine.Material TMPro.TMP_Asset::material".
//
// Fix: ldfld/stfld tới các field đó → callvirt get_/set_ tương ứng.
//
// Tương tự với struct của URP 12 (CameraData, RenderingData, LightData,
// ShadowData, PostProcessingData): URP 17 đổi mọi field public thành property,
// phần lớn trả về ref → IL2CPP báo "Unresolved field reference …
// CameraData::cameraTargetDescriptor". Property nào trả ref đọc từ mã nguồn URP
// (đối số --urp-source <UniversalRenderPipelineCore.cs>).
//   ldflda F → call get_F                     (getter ref trả về địa chỉ)
//   ldfld  F → call get_F [+ ldobj/ldind.ref]  (receiver là giá trị → biến tạm)
//   stfld  F → giá trị vào biến tạm, call get_F, ghi qua địa chỉ
//
// Kiểu 2D của URP cũ (UnityEngine.Experimental.Rendering.Universal.*) → đổi
// namespace sang UnityEngine.Rendering.Universal, assembly …Universal.2D.Runtime.
//
// Cách dùng: mono patch_tmp_fields.exe [--urp-source <file>] <dll>...
// (backup ở <project>/PatchBackup/)
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Mono.Cecil;
using Mono.Cecil.Cil;

public static class PatchTmpFields
{
    static readonly HashSet<string> Fields = new HashSet<string> { "material", "hashCode", "materialHashCode" };
    static readonly HashSet<string> Types = new HashSet<string> {
        "TMPro.TMP_Asset", "TMPro.TMP_FontAsset", "TMPro.TMP_SpriteAsset", "TMPro.TMP_ColorGradient"
    };

    const string UrpNamespace = "UnityEngine.Rendering.Universal.";
    // "CameraData.cameraTargetDescriptor" → true nếu property trả về ref.
    static readonly Dictionary<string, bool> UrpProperties = new Dictionary<string, bool>();

    public static int Main(string[] args)
    {
        var dlls = new List<string>();
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--urp-source" && i + 1 < args.Length) LoadUrpProperties(args[++i]);
            else dlls.Add(args[i]);
        }
        foreach (var dll in dlls)
        {
            try { Patch(dll); }
            catch (Exception e)
            {
                // Cecil không resolve được kiểu (vd enum làm giá trị mặc định của tham số) khi ghi.
                string backup = BackupPath(dll);
                if (File.Exists(backup)) File.Copy(backup, dll, true);
                Console.Error.WriteLine("⚠️  " + Path.GetFileName(dll) + ": không vá được (" + e.GetType().Name + ": " + e.Message + ") — giữ bản gốc");
            }
        }
        return 0;
    }

    static void LoadUrpProperties(string path)
    {
        if (!File.Exists(path)) return;
        string current = null;
        var structDecl = new Regex(@"^\s*public\s+(?:readonly\s+)?struct\s+(\w+)");
        var prop = new Regex(@"^\s*public\s+(ref\s+)?[\w.<>\[\], ]+?\s+(\w+)\s*=>");
        foreach (var line in File.ReadAllLines(path))
        {
            var s = structDecl.Match(line);
            if (s.Success) { current = s.Groups[1].Value; continue; }
            var p = prop.Match(line);
            if (current != null && p.Success) UrpProperties[current + "." + p.Groups[2].Value] = p.Groups[1].Success;
        }
    }

    static bool IsAddress(Instruction prev, MethodDefinition method)
    {
        if (prev == null) return false;
        var code = prev.OpCode.Code;
        if (code == Code.Ldarga || code == Code.Ldarga_S || code == Code.Ldloca || code == Code.Ldloca_S
            || code == Code.Ldflda || code == Code.Ldsflda || code == Code.Ldelema) return true;
        ParameterDefinition param = null;
        int offset = method.HasThis ? 1 : 0;
        if (code == Code.Ldarg_0 || code == Code.Ldarg_1 || code == Code.Ldarg_2 || code == Code.Ldarg_3)
        {
            int idx = (code - Code.Ldarg_0) - offset;
            if (idx >= 0 && idx < method.Parameters.Count) param = method.Parameters[idx];
        }
        else if (code == Code.Ldarg || code == Code.Ldarg_S) param = prev.Operand as ParameterDefinition;
        if (param != null) return param.ParameterType.IsByReference;
        if ((code == Code.Ldloc || code == Code.Ldloc_S) && prev.Operand is VariableDefinition v) return v.VariableType.IsByReference;
        if (code == Code.Call || code == Code.Callvirt) return ((MethodReference)prev.Operand).ReturnType.IsByReference;
        return false;
    }

    // Trả về số lệnh đã thay.
    static int PatchUrpStruct(MethodDefinition method, ModuleDefinition module, Instruction ins, FieldReference field, bool isRef)
    {
        var il = method.Body.GetILProcessor();
        var structType = field.DeclaringType;
        var fieldType = field.FieldType;
        var getter = new MethodReference("get_" + field.Name, isRef ? (TypeReference)new ByReferenceType(fieldType) : fieldType, structType) { HasThis = true };
        var getRef = module.ImportReference(getter);
        Func<Instruction> loadIndirect = () => fieldType.IsValueType ? il.Create(OpCodes.Ldobj, module.ImportReference(fieldType)) : il.Create(OpCodes.Ldind_Ref);
        Func<Instruction> storeIndirect = () => fieldType.IsValueType ? il.Create(OpCodes.Stobj, module.ImportReference(fieldType)) : il.Create(OpCodes.Stind_Ref);
        method.Body.InitLocals = true;
        var prev = ins.Previous;

        if (ins.OpCode == OpCodes.Ldflda && isRef)
        {
            il.Replace(ins, il.Create(OpCodes.Call, getRef));
            return 1;
        }
        if (ins.OpCode == OpCodes.Ldfld)
        {
            var call = il.Create(OpCodes.Call, getRef);
            if (!IsAddress(prev, method))
            {
                var tmp = new VariableDefinition(module.ImportReference(structType));
                method.Body.Variables.Add(tmp);
                il.InsertBefore(ins, il.Create(OpCodes.Stloc, tmp));
                il.InsertBefore(ins, il.Create(OpCodes.Ldloca, tmp));
            }
            il.Replace(ins, call);
            if (isRef) il.InsertAfter(call, loadIndirect());
            return 1;
        }
        if (ins.OpCode == OpCodes.Stfld && isRef)
        {
            // stack: [receiver(địa chỉ), value] → value vào biến tạm, lấy địa chỉ field, ghi.
            var tmp = new VariableDefinition(module.ImportReference(fieldType));
            method.Body.Variables.Add(tmp);
            var store = il.Create(OpCodes.Stloc, tmp);
            il.Replace(ins, store);
            var call = il.Create(OpCodes.Call, getRef);
            il.InsertAfter(store, call);
            var load = il.Create(OpCodes.Ldloc, tmp);
            il.InsertAfter(call, load);
            il.InsertAfter(load, storeIndirect());
            return 1;
        }
        Console.Error.WriteLine("⚠️  " + method.FullName + ": " + ins.OpCode + " " + field.FullName + " — không đổi được");
        return 0;
    }

    static void Patch(string dllPath)
    {
        string backup = BackupPath(dllPath);
        if (File.Exists(backup)) File.Copy(backup, dllPath, true);  // vá lại từ bản gốc → idempotent

        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(Path.GetDirectoryName(dllPath));
        int count = 0;
        using (var module = ModuleDefinition.ReadModule(dllPath, new ReaderParameters { AssemblyResolver = resolver, ReadWrite = false, InMemory = true }))
        {
            // URP 17 chuyển kiểu 2D (PixelPerfectCamera, Light2D…) từ namespace
            // UnityEngine.Experimental.Rendering.Universal sang UnityEngine.Rendering.Universal,
            // trong assembly riêng Unity.RenderPipelines.Universal.2D.Runtime. Không đổi thì
            // linker sinh kiểu stub, C++ của IL2CPP báo "no matching function".
            AssemblyNameReference urp2d = null;
            foreach (var tr in module.GetTypeReferences())
            {
                if (tr.Namespace != "UnityEngine.Experimental.Rendering.Universal") continue;
                if (urp2d == null)
                {
                    urp2d = module.AssemblyReferences.FirstOrDefault(a => a.Name == "Unity.RenderPipelines.Universal.2D.Runtime");
                    if (urp2d == null)
                    {
                        urp2d = new AssemblyNameReference("Unity.RenderPipelines.Universal.2D.Runtime", new Version(0, 0, 0, 0));
                        module.AssemblyReferences.Add(urp2d);
                    }
                }
                tr.Namespace = "UnityEngine.Rendering.Universal";
                tr.Scope = urp2d;
                count++;
            }
            foreach (var type in module.GetTypes())
            foreach (var method in type.Methods.Where(m => m.HasBody))
            {
                var il = method.Body.GetILProcessor();
                foreach (var ins in method.Body.Instructions.ToList())
                {
                    var field = ins.Operand as FieldReference;
                    if (field == null || field is FieldDefinition) continue;
                    string urpKey = field.DeclaringType.FullName.StartsWith(UrpNamespace)
                        ? field.DeclaringType.Name + "." + field.Name : null;
                    if (urpKey != null && UrpProperties.ContainsKey(urpKey))
                    {
                        count += PatchUrpStruct(method, module, ins, field, UrpProperties[urpKey]);
                        continue;
                    }
                    if (!Fields.Contains(field.Name) || !Types.Contains(field.DeclaringType.FullName)) continue;
                    if (ins.OpCode == OpCodes.Ldfld)
                    {
                        var getter = new MethodReference("get_" + field.Name, field.FieldType, field.DeclaringType) { HasThis = true };
                        il.Replace(ins, il.Create(OpCodes.Callvirt, module.ImportReference(getter)));
                        count++;
                    }
                    else if (ins.OpCode == OpCodes.Stfld)
                    {
                        var setter = new MethodReference("set_" + field.Name, module.TypeSystem.Void, field.DeclaringType) { HasThis = true };
                        setter.Parameters.Add(new ParameterDefinition(field.FieldType));
                        il.Replace(ins, il.Create(OpCodes.Callvirt, module.ImportReference(setter)));
                        count++;
                    }
                    else
                    {
                        Console.Error.WriteLine("⚠️  " + method.FullName + ": " + ins.OpCode + " " + field.FullName + " — không đổi được");
                    }
                }
            }
            if (count == 0) { Console.WriteLine("✅ " + Path.GetFileName(dllPath) + ": không dùng field TMP/URP cũ"); return; }
            Directory.CreateDirectory(Path.GetDirectoryName(backup));
            if (!File.Exists(backup)) File.Copy(dllPath, backup);
            module.Write(dllPath);
        }
        Console.WriteLine("✅ " + Path.GetFileName(dllPath) + ": đổi " + count + " truy cập field TMP/URP cũ → property");
    }

    // Backup ngoài Assets/ để Unity không import bản .orig như plugin khác.
    static string BackupPath(string dllPath)
    {
        string dir = Path.GetDirectoryName(Path.GetFullPath(dllPath));
        while (dir != null && Path.GetFileName(dir) != "Assets") dir = Path.GetDirectoryName(dir);
        string root = dir != null ? Path.GetDirectoryName(dir) : Path.GetDirectoryName(dllPath);
        return Path.Combine(root, "PatchBackup", "tmp-fields", Path.GetFileName(dllPath) + ".orig");
    }
}
