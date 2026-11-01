// Gỡ kiểu khỏi DLL dựng sẵn (Mono.Cecil).
//
// UniTask 2.5.x dựng cho Unity 2023+ có `AsyncInstantiateOperationExtensions`
// (AsyncInstantiateOperation<T>); IL2CPP của Unity 6 gãy khi sinh mã nó:
// "Attempting to get a fully shared method for 'AsyncOperation::get_isDone()'…".
// Game cũ không gọi API này, nên gỡ lớp đó khỏi DLL là đủ.
//
// Cách dùng: mono strip_types.exe <dll> <tên.đầy.đủ.kiểu>...
// Bản gốc lưu cạnh dll: <dll>.orig (chỉ tạo lần đầu). Không có kiểu nào khớp → không đổi gì.
using System;
using System.IO;
using System.Linq;
using Mono.Cecil;

public static class StripTypes
{
    public static int Main(string[] args)
    {
        if (args.Length < 2) { Console.Error.WriteLine("Dùng: strip_types <dll> <kiểu>..."); return 2; }
        string dll = args[0];
        var names = args.Skip(1).ToList();
        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(dll)));

        int removed = 0;
        using (var module = ModuleDefinition.ReadModule(dll, new ReaderParameters { AssemblyResolver = resolver, InMemory = true }))
        {
            foreach (var type in module.Types.Where(t => names.Contains(t.FullName)).ToList())
            {
                module.Types.Remove(type);
                removed++;
            }
            if (removed == 0) return 0;
            string orig = dll + ".orig";
            if (!File.Exists(orig)) File.Copy(dll, orig);
            string tmp = dll + ".tmp";
            module.Write(tmp);
            File.Delete(dll);
            File.Move(tmp, dll);
        }
        Console.WriteLine("✅ " + Path.GetFileName(dll) + ": gỡ " + removed + " kiểu (" + string.Join(", ", names) + ")");
        return 0;
    }
}
