// Đăng ký asset `UniversalRenderPipelineGlobalSettings` cho render pipeline.
//
// Vì sao cần:
//    Asset này chứa các tham chiếu shader của URP (CoreBlit, Sampling,
//    BlitHDROverlay, Light2D, Shadow2D…). Nếu KHÔNG được đăng ký trong
//    Graphics Settings thì Unity loại nó khỏi player build → lúc runtime các
//    shader đó là null → Unity log
//        "Cannot create required material because shader is null"
//    rồi crash ngay frame đầu tiên.
//
// Gọi bằng:
//   Unity -batchmode -nographics -quit -projectPath <project> \
//         -executeMethod GameHubRegisterGlobalSettings.Register \
//         -logFile /tmp/gs-register.log
//
using System;
using System.IO;
using UnityEditor;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;

public static class GameHubRegisterGlobalSettings
{
    static readonly string[] Candidates =
    {
        "Assets/MonoBehaviour/UniversalRenderPipelineGlobalSettings.asset",
        "Assets/Settings/UniversalRenderPipelineGlobalSettings.asset",
        "Assets/Resources/UniversalRenderPipelineGlobalSettings.asset",
    };

    public static void Register()
    {
        string found = null;
        foreach (var p in Candidates)
        {
            if (File.Exists(p)) { found = p; break; }
        }

        if (found == null)
        {
            // Tìm bất kỳ asset nào tên UniversalRenderPipelineGlobalSettings
            foreach (var guid in AssetDatabase.FindAssets("UniversalRenderPipelineGlobalSettings t:Object"))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                if (path.EndsWith(".asset", StringComparison.OrdinalIgnoreCase))
                {
                    found = path;
                    break;
                }
            }
        }

        if (found == null)
        {
            Debug.LogWarning("[GameHub] Không tìm thấy UniversalRenderPipelineGlobalSettings.asset — bỏ qua.");
            return;
        }

        var asset = AssetDatabase.LoadAssetAtPath<RenderPipelineGlobalSettings>(found);
        if (asset == null)
        {
            Debug.LogWarning($"[GameHub] Không load được '{found}' — bỏ qua.");
            return;
        }

        // Tìm kiểu render pipeline đang dùng (URP nằm trong DLL riêng).
        Type urpType = null;
        foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
        {
            var t = asm.GetType("UnityEngine.Rendering.Universal.UniversalRenderPipeline");
            if (t != null) { urpType = t; break; }
        }

        if (urpType == null)
        {
            Debug.LogWarning("[GameHub] Không tìm thấy type UniversalRenderPipeline — bỏ qua.");
            return;
        }

        try
        {
            EditorGraphicsSettings.SetRenderPipelineGlobalSettingsAsset(urpType, asset);
            AssetDatabase.SaveAssets();
            Debug.Log($"[GameHub] Đã đăng ký global settings cho {urpType.Name}: {found}");
        }
        catch (Exception e)
        {
            Debug.LogWarning($"[GameHub] Đăng ký global settings thất bại: {e.Message}");
        }
    }
}
