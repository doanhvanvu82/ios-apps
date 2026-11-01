// Sửa tham chiếu hàm Unity.Collections cũ trong DLL dựng sẵn (Mono.Cecil).
//
// DLL dựng sẵn (vd A* Pathfinding Project) được biên dịch với Collections cũ; Collections 2.x đổi
// vài chữ ký nên IL2CPP báo "Unresolved method reference". Các chỗ lệch đã gặp:
//   a) NativeReferenceUnsafeUtility / NativeListUnsafeUtility.GetUnsafePtr<T>: trả `void*` → `T*`.
//   b) NativeArrayExtensions.Contains<T,U>(NativeList<T>, U): chuyển sang NativeListExtensions.
//   c) UnsafeList<T>.CopyFrom(UnsafeList<T>): nay nhận `in UnsafeList<T>` → lưu vào biến tạm, truyền địa chỉ.
//   d) EarlyInitHelpers.JobReflectionDataCreationFailed(Exception, Type): nay chỉ (Exception) → bỏ đối số Type.
// Chỉ đụng tới các tham chiếu này, DLL không có thì không đổi gì.
//
// Cách dùng: mono fix_collections_refs.exe [--lib <thư mục assembly>]... <dll>...
// (--lib: nơi có UnityEngine.CoreModule.dll… — Cecil cần phân giải kiểu enum khi ghi file)
// Bản gốc lưu cạnh dll: <dll>.orig; mỗi lần chạy vá lại từ bản gốc (idempotent).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

public static class FixCollectionsRefs
{
    const string RefUtility = "Unity.Collections.LowLevel.Unsafe.NativeReferenceUnsafeUtility";
    const string ListUtility = "Unity.Collections.LowLevel.Unsafe.NativeListUnsafeUtility";

    public static int Main(string[] args)
    {
        var libs = new List<string>();
        var dlls = new List<string>();
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--lib" && i + 1 < args.Length) libs.Add(args[++i]);
            else dlls.Add(args[i]);
        }
        foreach (var dll in dlls)
        {
            string orig = dll + ".orig";
            if (File.Exists(orig)) File.Copy(orig, dll, true);

            var resolver = new DefaultAssemblyResolver();
            resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(dll)));
            foreach (var lib in libs) resolver.AddSearchDirectory(lib);

            int changes = 0;
            using (var module = ModuleDefinition.ReadModule(dll, new ReaderParameters { AssemblyResolver = resolver, InMemory = true }))
            {
                var patched = new HashSet<MethodReference>();
                foreach (var type in module.GetTypes())
                    foreach (var method in type.Methods.Where(m => m.HasBody))
                        changes += Fix(module, method, patched);
                if (changes == 0) continue;
                if (!File.Exists(orig)) File.Copy(dll, orig);
                string tmp = dll + ".tmp";
                module.Write(tmp);
                File.Delete(dll);
                File.Move(tmp, dll);
            }
            Console.WriteLine("✅ " + Path.GetFileName(dll) + ": sửa " + changes + " chỗ gọi Unity.Collections cũ");
        }
        return 0;
    }

    static int Fix(ModuleDefinition module, MethodDefinition method, HashSet<MethodReference> patched)
    {
        int changes = 0;
        var il = method.Body.GetILProcessor();
        var instructions = method.Body.Instructions;
        for (int i = 0; i < instructions.Count; i++)
        {
            var call = instructions[i].Operand as MethodReference;
            if (call == null) continue;
            var member = call is GenericInstanceMethod generic ? generic.ElementMethod : call;
            var declaring = member.DeclaringType;
            if (declaring == null) continue;
            string type = declaring.GetElementType().FullName;

            // a) void* → T*
            if ((type == RefUtility || type == ListUtility) && (member.Name == "GetUnsafePtr" || member.Name == "GetUnsafeReadOnlyPtr")
                && member.ReturnType is PointerType pointer && pointer.ElementType.FullName == "System.Void" && member.GenericParameters.Count == 1)
            {
                member.ReturnType = new PointerType(member.GenericParameters[0]);
                changes++;
            }
            // b) Contains trên NativeList
            else if (type == "Unity.Collections.NativeArrayExtensions" && member.Name == "Contains" && member.Parameters.Count == 2
                && member.Parameters[0].ParameterType.GetElementType().FullName == "Unity.Collections.NativeList`1")
            {
                member.DeclaringType = new TypeReference("Unity.Collections", "NativeListExtensions", module, declaring.Scope);
                changes++;
            }
            // c) UnsafeList<T>.CopyFrom(UnsafeList<T>) → CopyFrom(in UnsafeList<T>)
            else if (type == "Unity.Collections.LowLevel.Unsafe.UnsafeList`1" && member.Name == "CopyFrom" && member.Parameters.Count == 1
                && (member.Parameters[0].ParameterType is GenericInstanceType || patched.Contains(member)))
            {
                if (!patched.Contains(member))
                {
                    member.Parameters[0].ParameterType = new ByReferenceType(member.Parameters[0].ParameterType);
                    patched.Add(member);
                }
                var temp = new VariableDefinition(declaring);
                method.Body.Variables.Add(temp);
                il.InsertBefore(instructions[i], il.Create(OpCodes.Stloc, temp));
                il.InsertBefore(instructions[i], il.Create(OpCodes.Ldloca, temp));
                i += 2;
                changes++;
            }
            // d) JobReflectionDataCreationFailed(Exception, Type) → (Exception)
            else if (type == "Unity.Jobs.EarlyInitHelpers" && member.Name == "JobReflectionDataCreationFailed"
                && (member.Parameters.Count == 2 || patched.Contains(member)))
            {
                if (!patched.Contains(member))
                {
                    member.Parameters.RemoveAt(1);
                    patched.Add(member);
                }
                il.InsertBefore(instructions[i], il.Create(OpCodes.Pop));
                i += 1;
                changes++;
            }
        }
        return changes;
    }
}
