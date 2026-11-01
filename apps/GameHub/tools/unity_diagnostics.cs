// Kiểm tra asset UniversalRenderPipelineGlobalSettings — liệu các tham chiếu
// shader bên trong (ManagedReference) có được deserialize đúng không.
//
// Chạy:
//   Unity -batchmode -nographics -quit -projectPath <project> \
//         -executeMethod GameHubDiagnostics.CheckGlobalSettings \
//         -logFile /tmp/gs-check.log
using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEngine;

public static class GameHubDiagnostics
{
    public static void CheckGlobalSettings()
    {
        const string path = "Assets/MonoBehaviour/UniversalRenderPipelineGlobalSettings.asset";

        var obj = AssetDatabase.LoadAssetAtPath<UnityEngine.Object>(path);
        if (obj == null)
        {
            Debug.Log("[GH] Global settings: KHÔNG LOAD ĐƯỢC");
            EditorApplication.Exit(1);
            return;
        }
        Debug.Log($"[GH] Global settings: {obj.GetType().FullName}");

        // m_Settings → m_RuntimeSettings → m_List (IList)
        var t = obj.GetType();
        var settings = GetField(t, obj, "m_Settings");
        Debug.Log($"[GH] m_Settings = {(settings == null ? "NULL" : settings.GetType().FullName)}");
        if (settings == null) { EditorApplication.Exit(0); return; }

        var st = settings.GetType();
        var runtimeSettings = GetField(st, settings, "m_RuntimeSettings");
        Debug.Log($"[GH] m_RuntimeSettings = {(runtimeSettings == null ? "NULL" : runtimeSettings.GetType().FullName)}");
        if (runtimeSettings == null) { EditorApplication.Exit(0); return; }

        var listProp = st.GetProperty("settingsList",
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        var list = listProp?.GetValue(settings) as IEnumerable;
        if (list == null)
        {
            Debug.Log("[GH] settingsList = NULL");
            EditorApplication.Exit(0);
            return;
        }

        int i = 0;
        foreach (var item in list)
        {
            if (item == null)
            {
                Debug.Log($"[GH]   [{i++}] NULL");
                continue;
            }
            var it = item.GetType();
            Debug.Log($"[GH]   [{i++}] {it.FullName}");
            foreach (var f in it.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
            {
                if (f.FieldType != typeof(Shader) && f.FieldType != typeof(Texture2D)) continue;
                var v = f.GetValue(item);
                string desc = v == null ? "NULL" : $"'{((UnityEngine.Object)v).name}'";
                Debug.Log($"[GH]        {f.Name} = {desc}");
            }
        }

        // Thử load thẳng 3 shader mà URP 2D dùng
        foreach (var name in new[] {
            "Hidden/Universal/CoreBlit",
            "Hidden/Universal/BlitHDROverlay",
            "Hidden/Universal Render Pipeline/Sampling",
        })
        {
            var sh = Shader.Find(name);
            Debug.Log($"[GH] Shader.Find(\"{name}\") = {(sh == null ? "NULL" : "OK")}");
        }

        EditorApplication.Exit(0);
    }

    static object GetField(Type t, object instance, string name)
    {
        var f = t.GetField(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        return f?.GetValue(instance);
    }
}
