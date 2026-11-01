#!/usr/bin/env bash
#
# Build một project Unity (đã dựng lại từ game đã build) thành bản **WebGL**,
# để chơi được trên iOS qua GameHub.
#
#   ./unity_build_webgl.sh <project-dir> [output-dir]
#
# Luồng đầy đủ cho game Unity Windows:
#   1. tools/unity_extract.sh     → dựng project Unity từ game .exe
#   2. tools/unity_build_webgl.sh → build WebGL
#   3. copy thư mục build vào iPhone (Files → GameHub → Imports)
#
# Yêu cầu:
#   - Unity Editor 6000.0.54f1 tại ~/Unity/Editor/Unity
#   - Module "WebGL Build Support" đã cài
#   - License đã kích hoạt (xem tools/unity_license.sh)
#
set -euo pipefail

# Unity import mở rất nhiều file; soft limit mặc định của phiên desktop (1024)
# làm Mono abort: "Requested file descriptor exceeds maximum number of files".
hard_nofile="$(ulimit -Hn)"
[ "$hard_nofile" = unlimited ] && hard_nofile=65536
ulimit -Sn "$(( hard_nofile < 65536 ? hard_nofile : 65536 ))" 2>/dev/null || true

PROJECT="${1:?Usage: $0 <project-dir> [output-dir]}"
OUT="${2:-}"

UNITY_HOME="${UNITY_HOME:-$HOME/Unity}"
UNITY="$UNITY_HOME/Editor/Unity"
LOG="${UNITY_LOG:-/tmp/unity-build.log}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$UNITY" ]; then
    echo "❌ Không tìm thấy Unity Editor tại $UNITY" >&2
    echo "   Đặt UNITY_HOME=/path/to/unity để chỉ định khác." >&2
    exit 1
fi

PROJECT="$(cd "$PROJECT" && pwd)"

if [ ! -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ]; then
    echo "❌ '$PROJECT' không phải project Unity (thiếu ProjectSettings/ProjectVersion.txt)" >&2
    exit 1
fi

if [ -z "$OUT" ]; then
    OUT="$PROJECT/../$(basename "$PROJECT")-webgl"
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# --- Dọn khi kết thúc (thành công, lỗi, crash hay Ctrl+C) ---
# `Library/` là cache import của Unity (tới hàng chục GB với project lớn),
# Unity tự sinh lại khi build lại. Trước đây chỉ dọn khi build thành công nên
# các project build hỏng giữ lại hàng chục GB. Output dở dang (không có
# index.html) cũng bị xoá để không bị tưởng là đã build.
cleanup() {
    if [ "${GAMEHUB_KEEP_LIBRARY:-0}" != "1" ] && [ -d "$PROJECT/Library" ]; then
        local sz
        sz="$(du -sm "$PROJECT/Library" 2>/dev/null | cut -f1)"
        rm -rf "$PROJECT/Library"
        echo "🧹 Đã dọn cache Unity: Library/ (${sz} MB)"
    fi
    if [ ! -f "$OUT/index.html" ] && [ -d "$OUT" ]; then
        rm -rf "$OUT"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

echo "→ Project: $PROJECT"
echo "→ Output : $OUT"
echo "→ Log    : $LOG"
echo

# --- Vá lỗi compile do AssetRipper decompile ---
SCRIPTS_DIR="$PROJECT/Assets/Scripts/Assembly-CSharp"

# 1) `using Spine;` + `using UnityEngine;` → tên `Event`/`Animation` bị ambiguous
#    (Spine.Event vs UnityEngine.Event, Spine.Animation vs UnityEngine.Animation).
#    Đổi tham số về kiểu đầy đủ để không mơ hồ.
if [ -d "$SCRIPTS_DIR" ]; then
    while IFS= read -r f; do
        grep -q "^using Spine;" "$f" || continue
        for T in Event Animation; do
            grep -qE "\b$T\b" "$f" || continue
            sed -i -E "s/(\(|,\s*)$T ([a-zA-Z_][a-zA-Z0-9_]*)\)/\1Spine.$T \2)/g" "$f"
        done
    done < <(find "$SCRIPTS_DIR" -maxdepth 1 -name "*.cs" 2>/dev/null)

    # 2) `using System.Diagnostics;` + `using UnityEngine;` → `Debug` bị ambiguous
    #    (System.Diagnostics.Debug vs UnityEngine.Debug) → error CS0104.
    #    Bỏ dòng using System.Diagnostics (game Unity không cần nó).
    while IFS= read -r f; do
        grep -q "^using System.Diagnostics;" "$f" || continue
        grep -qE "\b(Stopwatch|Process|Trace\.|StackTrace)\b" "$f" || continue
        grep -qE "\bDebug\." "$f" || continue
        # Đổi Debug. → UnityEngine.Debug. thay vì xoá using (giữ an toàn)
        sed -i -E 's/(^|[^A-Za-z0-9_.])Debug\./\1UnityEngine.Debug./g' "$f"
    done < <(find "$SCRIPTS_DIR" -maxdepth 1 -name "*.cs" 2>/dev/null)
fi

# 2) `AsyncUniTaskMethodBuilder` (UniTask) — Unity 6 không hỗ trợ IL2CPP cho
#    async/await của UniTask → CS0656. Game dùng UniTask gần như không build
#    được bằng Unity 6000 (cần editor đúng version của game).
if [ -d "$SCRIPTS_DIR" ] && grep -rq "AsyncUniTaskMethodBuilder" "$SCRIPTS_DIR" 2>/dev/null; then
    echo "⚠️  Game dùng UniTask (async) — có thể không build được bằng Unity 6000"
fi

# Script UI/TMP trong scene/prefab trỏ vào UnityEngine.UI.dll / Unity.TextMeshPro.dll của game;
# DLL bị xoá ngay dưới đây → đổi sang gói com.unity.ugui trước, không thì mất hết UI.
python3 "$SCRIPT_DIR/unity_ugui_script_refs.py" "$PROJECT" "$UNITY_HOME/Editor" 2>&1 | tail -2

# WebGL không phát VideoClip asset (nền/cutscene video đen) → phát theo URL từ StreamingAssets.
python3 "$SCRIPT_DIR/unity_videoclip_to_url.py" "$PROJECT" 2>&1 | tail -2

# UI Match Width tràn trên/dưới trên iPhone ngang (tỉ lệ rộng hơn 16:9) → Expand.
python3 "$SCRIPT_DIR/unity_canvas_expand.py" "$PROJECT" 2>&1 | tail -2

# Shader TMP do AssetRipper xuất là bản dummy (chỉ sample atlas) → chữ TMP thành khối đen; dùng shader thật.
python3 "$SCRIPT_DIR/unity_tmp_shaders.py" "$PROJECT" "$UNITY_HOME/Editor" 2>&1 | tail -2

# Chuẩn hoá project: xoá DLL render pipeline cũ (URP 12…) và source TMP trùng.
# Không làm thì IL2CPP của Unity 6 không resolve được field đã đổi tên.
if [ -f "$SCRIPT_DIR/unity_normalize_project.py" ]; then
    python3 "$SCRIPT_DIR/unity_normalize_project.py" "$PROJECT" --apply 2>&1 | tail -3
fi

# Unity.InputSystem.dll dựng cho Unity cũ → IL2CPP lỗi C++; thay bằng gói đi kèm Unity 6.
python3 "$SCRIPT_DIR/unity_inputsystem_package.py" "$PROJECT" "$UNITY_HOME/Editor" 2>&1 | tail -2

# Code riêng game nhúng trong DLL URP gốc (vd Beautify) mất khi thay bằng package.
python3 "$SCRIPT_DIR/unity_urp_extra_types.py" "$PROJECT" 2>&1 | tail -2

# Xoá file .cs dummy trùng (AssetRipper sinh class placeholder khi có cả DLL
# Mono lẫn metadata IL2CPP) → 2 file chỉ khác hoa/thường làm Unity mất class
# → error CS0246 "type or namespace not found".
if [ -f "$SCRIPT_DIR/unity_fix_duplicate_types.py" ]; then
    python3 "$SCRIPT_DIR/unity_fix_duplicate_types.py" "$PROJECT" --apply 2>&1 | tail -2
fi

# Sửa ép kiểu gây mơ hồ với tham số Naninovel (CS0457).
if [ -f "$SCRIPT_DIR/unity_fix_naninovel_params.py" ]; then
    python3 "$SCRIPT_DIR/unity_fix_naninovel_params.py" "$PROJECT" --apply 2>&1 | tail -2
fi

# Code decompile bởi AssetRipper có thể dùng tính năng C# 10+ (ví dụ
# "parameterless struct constructors") trong khi Unity mặc định biên dịch ở
# C# 9.0 → error CS8773. Nâng ngôn ngữ lên `latest` qua csc.rsp.
if [ ! -f "$PROJECT/Assets/csc.rsp" ]; then
    printf -- "-langversion:latest\n" > "$PROJECT/Assets/csc.rsp"
fi

# Script build nằm trong Assets/Editor/ (Unity chỉ thấy file trong Assets/).
BUILD_SCRIPT="$PROJECT/Assets/Editor/GameHubBuild.cs"
mkdir -p "$PROJECT/Assets/Editor"

cat > "$BUILD_SCRIPT" <<'EOF'
using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

public static class GameHubBuild
{
    static bool ImportsAstc()
    {
        foreach (var guid in AssetDatabase.FindAssets("t:Texture2D", new[] { "Assets" }))
        {
            if (AssetImporter.GetAtPath(AssetDatabase.GUIDToAssetPath(guid)) is TextureImporter ti
                && ti.textureCompression != TextureImporterCompression.Uncompressed)
            {
                var format = ti.GetAutomaticFormat("WebGL");
                Debug.Log($"[GameHub] Định dạng texture WebGL tự động: {format}");
                return format.ToString().StartsWith("ASTC");
            }
        }
        return true;
    }

    public static void PerformBuild()
    {
        ApplyWebGLSettings();

        var scenes = EditorBuildSettings.scenes
            .Where(s => s.enabled)
            .Select(s => s.path)
            .ToArray();

        // AssetRipper đôi khi để m_Scenes rỗng; scene xuất ra tên levelN theo thứ tự build gốc.
        if (scenes.Length == 0 && Directory.Exists("Assets/Scenes"))
        {
            scenes = Directory.GetFiles("Assets/Scenes", "level*.unity")
                .Select(p => p.Replace('\\', '/'))
                .Where(p => int.TryParse(Path.GetFileNameWithoutExtension(p).Substring(5), out _))
                .OrderBy(p => int.Parse(Path.GetFileNameWithoutExtension(p).Substring(5)))
                .ToArray();
        }

        if (scenes.Length == 0)
        {
            Debug.LogError("Không có scene nào được bật trong Build Settings.");
            EditorApplication.Exit(1);
            return;
        }

        var outputDir = Environment.GetEnvironmentVariable("GAMEHUB_OUTPUT");
        if (string.IsNullOrEmpty(outputDir)) outputDir = "Build";

        Debug.Log($"[GameHub] Building {scenes.Length} scene(s) → {outputDir}");

        var options = new BuildPlayerOptions
        {
            scenes = scenes,
            locationPathName = outputDir,
            target = BuildTarget.WebGL,
            targetGroup = BuildTargetGroup.WebGL,
            options = BuildOptions.None
        };

        // ASTC: iPhone (WebGL2) đọc thẳng; mặc định DXT thì iOS phải giải nén ra
        // RGBA lúc chạy — nặng cả dữ liệu tải lẫn RAM.
        // unity_astc_default.py đã đặt ASTC mặc định cho WebGL nên texture import
        // thẳng ra ASTC. Đổi subtarget làm Unity import lại toàn bộ texture
        // (~8 phút/game) — chỉ dùng khi cách kia không ăn.
        if (!ImportsAstc())
        {
            Debug.LogWarning("[GameHub] Texture WebGL chưa ra ASTC — đặt subtarget ASTC (import lại texture)");
            EditorUserBuildSettings.webGLBuildSubtarget = WebGLTextureSubtarget.ASTC;
        }
        // Bản WebGL phải < 2 GB (giới hạn ghi file data của Unity) — game lớn thì
        // unity_build_webgl.sh build lại với GAMEHUB_MAX_TEXTURE nhỏ dần.
        // GAMEHUB_STRIP_LEVEL=Medium|High: cắt mã không dùng mạnh hơn (đặt tự động khi IL2CPP báo
        // "Found a method reference we cannot resolve": DLL ECS/A* cũ gọi API Collections đã đổi,
        // nhưng đó là mã game không bao giờ chạy tới nên bị cắt đi là hết lỗi).
        var stripLevel = Environment.GetEnvironmentVariable("GAMEHUB_STRIP_LEVEL");
        if (!string.IsNullOrEmpty(stripLevel) && Enum.TryParse<ManagedStrippingLevel>(stripLevel, out var level))
        {
            PlayerSettings.SetManagedStrippingLevel(UnityEditor.Build.NamedBuildTarget.WebGL, level);
            Debug.Log($"[GameHub] ManagedStrippingLevel = {level}");
        }
        // GAMEHUB_IL2CPP_SIZE=1: IL2CPP "Faster (smaller) builds" (đặt tự động khi gặp lỗi generic sharing;
        // cũng biên dịch C++ nhanh hơn, đổi lại generics chạy chậm hơn chút). Reflection: API lệch tên chỉ bỏ qua.
        if (Environment.GetEnvironmentVariable("GAMEHUB_IL2CPP_SIZE") == "1")
        {
            var codeGenType = typeof(UnityEditor.Build.NamedBuildTarget).Assembly.GetType("UnityEditor.Build.Il2CppCodeGeneration");
            var setter = codeGenType == null ? null : typeof(PlayerSettings).GetMethod("SetIl2CppCodeGeneration",
                new[] { typeof(UnityEditor.Build.NamedBuildTarget), codeGenType });
            if (setter != null)
            {
                setter.Invoke(null, new object[] { UnityEditor.Build.NamedBuildTarget.WebGL, Enum.Parse(codeGenType, "OptimizeSize") });
                Debug.Log("[GameHub] Il2CppCodeGeneration = OptimizeSize");
            }
            else Debug.LogWarning("[GameHub] Không đặt được Il2CppCodeGeneration");
        }
        // GAMEHUB_CODE_OPT=BuildTimes: biên dịch C++ (-O1) nhanh hơn nhiều so với mặc định
        // RuntimeSpeed (-O3) nhưng game chạy chậm hơn. Dùng reflection: tên kiểu sai chỉ bỏ qua.
        var codeOpt = Environment.GetEnvironmentVariable("GAMEHUB_CODE_OPT");
        if (!string.IsNullOrEmpty(codeOpt))
        {
            var settingsType = Type.GetType("UnityEditor.WebGL.UserBuildSettings, UnityEditor.WebGL.Extensions");
            var property = settingsType?.GetProperty("codeOptimization");
            if (property != null && Enum.IsDefined(property.PropertyType, codeOpt))
            {
                property.SetValue(null, Enum.Parse(property.PropertyType, codeOpt));
                Debug.Log($"[GameHub] codeOptimization = {codeOpt}");
            }
            else Debug.LogWarning($"[GameHub] Không đặt được codeOptimization = {codeOpt}");
        }
        if (int.TryParse(Environment.GetEnvironmentVariable("GAMEHUB_MAX_TEXTURE"), out var maxTexture) && maxTexture > 0)
        {
            EditorUserBuildSettings.overrideMaxTextureSize = maxTexture;
            Debug.Log($"[GameHub] overrideMaxTextureSize = {maxTexture}");
        }
        // GAMEHUB_INITIAL_MEMORY=<MB>: heap wasm khởi điểm đủ lớn để không phải mở rộng khi chạy — mỗi lần
        // mở rộng WebKit cấp buffer mới + chép, đỉnh RAM tạm thời gấp đôi và dễ bị giết trên iPhone.
        if (int.TryParse(Environment.GetEnvironmentVariable("GAMEHUB_INITIAL_MEMORY"), out var initialMemory) && initialMemory > 0)
        {
            PlayerSettings.WebGL.initialMemorySize = initialMemory;
            Debug.Log($"[GameHub] initialMemorySize = {initialMemory}MB");
        }

        var report = BuildPipeline.BuildPlayer(options);
        var summary = report.summary;

        Debug.Log($"[GameHub] Result: {summary.result} | " +
                  $"size={summary.totalSize / (1024 * 1024)}MB | " +
                  $"errors={summary.totalErrors} | warnings={summary.totalWarnings}");

        if (summary.result != BuildResult.Succeeded)
        {
            EditorApplication.Exit(1);
        }
    }

    // Project export từ AssetRipper có nhiều setting WebGL bị để 0 / rỗng.
    // Set lại bằng API để chắc chắn đúng giá trị.
    static void ApplyWebGLSettings()
    {
        // Template rỗng → WebGlBuildPostprocessor gọi template.Split(':')[1]
        // → IndexOutOfRangeException → build fail ở bước post-process.
        if (string.IsNullOrEmpty(PlayerSettings.WebGL.template))
        {
            PlayerSettings.WebGL.template = "APPLICATION:Default";
            Debug.Log("[GameHub] webGLTemplate = APPLICATION:Default");
        }

        // Bộ nhớ = 0 → emcc nhận INITIAL_MEMORY=0 →
        // "emcc: error: INITIAL_MEMORY must be larger than STACK_SIZE".
        // Đơn vị của các API này là **MB** (xem Player Settings → WebGL → Memory).
        if (PlayerSettings.WebGL.initialMemorySize <= 0)
            PlayerSettings.WebGL.initialMemorySize = 32;      // MB
        if (PlayerSettings.WebGL.maximumMemorySize <= 0)
            PlayerSettings.WebGL.maximumMemorySize = 2048;    // MB
        if (PlayerSettings.WebGL.memoryGrowthMode == WebGLMemoryGrowthMode.None)
            PlayerSettings.WebGL.memoryGrowthMode = WebGLMemoryGrowthMode.Linear;
        if (PlayerSettings.WebGL.linearMemoryGrowthStep <= 0)
            PlayerSettings.WebGL.linearMemoryGrowthStep = 16; // MB
        if (PlayerSettings.WebGL.memoryGeometricGrowthCap <= 0)
            PlayerSettings.WebGL.memoryGeometricGrowthCap = 16; // MB

        // Nén: Disabled → file .data phẳng, loader không cần DecompressionStream
        // (Safari 16.4+) và server không cần trả Content-Encoding.
        PlayerSettings.WebGL.compressionFormat = WebGLCompressionFormat.Disabled;
        PlayerSettings.WebGL.decompressionFallback = false;

        // Exception support = None → mọi exception C# (kể cả loại game tự bắt) thành
        // "RuntimeError: unreachable" và player dừng ngay khi vào scene đầu.
        Debug.Log($"[GameHub] WebGL exceptionSupport: {PlayerSettings.WebGL.exceptionSupport} → ExplicitlyThrownExceptionsOnly");
        PlayerSettings.WebGL.exceptionSupport = WebGLExceptionSupport.ExplicitlyThrownExceptionsOnly;

        Debug.Log($"[GameHub] WebGL: mem={PlayerSettings.WebGL.initialMemorySize}/" +
                  $"{PlayerSettings.WebGL.maximumMemorySize} " +
                  $"growth={PlayerSettings.WebGL.memoryGrowthMode} " +
                  $"compression={PlayerSettings.WebGL.compressionFormat} " +
                  $"template={PlayerSettings.WebGL.template}");
    }
}
EOF

# Nén ASTC chất lượng Fast: import texture nhanh hơn nhiều (xem file này).
cp "$SCRIPT_DIR/gamehub_fast_textures.cs" "$PROJECT/Assets/Editor/GameHubFastTextures.cs"

# Nén (Gzip) làm loader cần DecompressionStream — Safari 16.4+ mới có.
# Đặt Disabled cho chắc chắn, đổi lại nếu file quá lớn.
sed -i 's/^  webGLCompressionFormat:.*/  webGLCompressionFormat: 2/' "$PROJECT/ProjectSettings/ProjectSettings.asset" 2>/dev/null || true
sed -i 's/^  webGLDecompressionFallback:.*/  webGLDecompressionFallback: 0/' "$PROJECT/ProjectSettings/ProjectSettings.asset" 2>/dev/null || true

# Template WebGL: BẮT BUỘC phải có. Project export từ AssetRipper để trống
# `webGLTemplate`, khiến WebGlBuildPostprocessor.PostProcess() gọi
# template.Split(':')[1] → IndexOutOfRangeException → build fail ở bước post-process.
sed -i 's|^  webGLTemplate:.*|  webGLTemplate: APPLICATION:Default|' "$PROJECT/ProjectSettings/ProjectSettings.asset" 2>/dev/null || true

# Bộ nhớ WebGL: 0 → emcc fail. Đơn vị là MB. Sửa luôn ở YAML cho chắc
# (API cũng set lại trong GameHubBuild.ApplyWebGLSettings).
# Con trỏ chuột mặc định tuỳ chỉnh: Unity chạy -nographics (không có X display) gọi Xcursor với
# Display NULL → segfault ở BuildPlayer (PlayerSettings::InitDefaultCursors). iPhone không có
# con trỏ nên bỏ đi.
sed -i 's/^  defaultCursor:.*/  defaultCursor: {fileID: 0}/' "$PROJECT/ProjectSettings/ProjectSettings.asset" 2>/dev/null || true
sed -i 's/^  webGLInitialMemorySize:.*/  webGLInitialMemorySize: 32/' "$PROJECT/ProjectSettings/ProjectSettings.asset" 2>/dev/null || true
sed -i 's/^  webGLMaximumMemorySize:.*/  webGLMaximumMemorySize: 2048/' "$PROJECT/ProjectSettings/ProjectSettings.asset" 2>/dev/null || true
sed -i 's/^  webGLMemoryGrowthMode:.*/  webGLMemoryGrowthMode: 1/' "$PROJECT/ProjectSettings/ProjectSettings.asset" 2>/dev/null || true
sed -i 's/^  webGLMemoryLinearGrowthStep:.*/  webGLMemoryLinearGrowthStep: 16/' "$PROJECT/ProjectSettings/ProjectSettings.asset" 2>/dev/null || true
sed -i 's/^  webGLMemoryGeometricGrowthCap:.*/  webGLMemoryGeometricGrowthCap: 16/' "$PROJECT/ProjectSettings/ProjectSettings.asset" 2>/dev/null || true

# ASTC mặc định cho WebGL ngay từ lần import đầu (xem unity_astc_default.py).
python3 "$SCRIPT_DIR/unity_astc_default.py" "$PROJECT" || true

# I2 Localization: asset LocalizeTarget_* làm Unity lặp vô hạn "ReadObjectThreaded" khi import.
python3 "$SCRIPT_DIR/unity_i2_localize_targets.py" "$PROJECT" || true

# Tên file/thư mục chỉ khác hoa/thường (Resources + resources…): Unity trên Linux bỏ qua một trong hai.
python3 "$SCRIPT_DIR/unity_case_collisions.py" "$PROJECT" || true
python3 "$SCRIPT_DIR/unity_webgl_runtime_fixes.py" "$PROJECT" || true

# Bản Unity Trung Quốc ghi "2020.3.45f1c1" → Package Manager của Unity 6 báo
# "not a valid Unity version" và không nạp được gói nào. Bỏ đuôi cN.
sed -i -E 's/^(m_EditorVersion(WithRevision)?: [0-9]+\.[0-9]+\.[0-9]+[abfp][0-9]+)c[0-9]+/\1/' \
    "$PROJECT/ProjectSettings/ProjectVersion.txt" 2>/dev/null || true

# Tên trùng giữa game và gói Unity 6 tự thêm (namespace Editor, AABB của DOTS cũ…).
python3 "$SCRIPT_DIR/unity_package_conflicts.py" "$PROJECT" || true

# Game URP cũ dùng API URP 17 đã cấm (CS0619: RenderTargetHandle,
# cameraColorTarget, ConfigureTarget(RenderTargetIdentifier)…) → nhúng URP đã vá.
python3 "$SCRIPT_DIR/unity_urp_compat.py" "$PROJECT" || true

# Spine runtime 3.x/4.0 gọi Object.Destroy() trong OnDestroy → lỗi
# "Destroy may not be called from edit mode!" khi build. Patch DLL cho an toàn.
if [ -f "$SCRIPT_DIR/patch_spine.sh" ]; then
    "$SCRIPT_DIR/patch_spine.sh" --project "$PROJECT" || true
fi

# DLL plugin biên dịch với TextMeshPro cũ (TMP_Asset.material là field) hoặc URP
# 12 (CameraData.cameraTargetDescriptor là field) → IL2CPP Unity 6 báo
# "Unresolved field reference". Đổi truy cập field sang property.
TMP_DLLS=()
while IFS= read -r dll; do
    grep -qE "TMP_Asset|CameraData|RenderingData|ShadowData|PostProcessingData|Experimental.Rendering.Universal" "$dll" && TMP_DLLS+=("$dll")
done < <(find "$PROJECT/Assets" -name "*.dll" 2>/dev/null)
URP_CORE_CS="$UNITY_HOME/Editor/Data/Resources/PackageManager/BuiltInPackages/com.unity.render-pipelines.universal/Runtime/UniversalRenderPipelineCore.cs"
if [ ${#TMP_DLLS[@]} -gt 0 ]; then
    MONO_BIN="$UNITY_HOME/Editor/Data/MonoBleedingEdge/bin"
    CECIL="$UNITY_HOME/Editor/Data/MonoBleedingEdge/lib/mono/gac/Mono.Cecil/0.11.1.0__0738eb9f132ed756/Mono.Cecil.dll"
    TMP_EXE="/tmp/patch_tmp_fields.exe"
    if [ ! -f "$TMP_EXE" ] || [ "$SCRIPT_DIR/patch_tmp_fields.cs" -nt "$TMP_EXE" ]; then
        "$MONO_BIN/mcs" -target:exe -out:"$TMP_EXE" -r:"$CECIL" "$SCRIPT_DIR/patch_tmp_fields.cs" 2>&1 | grep -v "warning CS" || true
    fi
    "$MONO_BIN/mono" "$TMP_EXE" --urp-source "$URP_CORE_CS" "${TMP_DLLS[@]}" || true
fi

# UniTask 2.5.x dựng cho Unity 2023+ có lớp AsyncInstantiateOperationExtensions; IL2CPP của
# Unity 6 gãy khi sinh mã nó ("Attempting to get a fully shared method…"). Game cũ không dùng → gỡ.
while IFS= read -r dll; do
    grep -qa "AsyncInstantiateOperationExtensions" "$dll" || continue
    MONO_BIN="$UNITY_HOME/Editor/Data/MonoBleedingEdge/bin"
    CECIL="$UNITY_HOME/Editor/Data/MonoBleedingEdge/lib/mono/gac/Mono.Cecil/0.11.1.0__0738eb9f132ed756/Mono.Cecil.dll"
    STRIP_EXE="/tmp/strip_types.exe"
    if [ ! -f "$STRIP_EXE" ] || [ "$SCRIPT_DIR/strip_types.cs" -nt "$STRIP_EXE" ]; then
        "$MONO_BIN/mcs" -target:exe -out:"$STRIP_EXE" -r:"$CECIL" "$SCRIPT_DIR/strip_types.cs" 2>&1 | grep -v "warning CS" || true
    fi
    "$MONO_BIN/mono" "$STRIP_EXE" "$dll" Cysharp.Threading.Tasks.AsyncInstantiateOperationExtensions || true
done < <(find "$PROJECT/Assets" -name "UniTask.dll" 2>/dev/null)

# DLL dựng sẵn (vd A* Pathfinding) gọi API Unity.Collections với chữ ký cũ (GetUnsafePtr trả void*,
# Contains trên NativeList, UnsafeList.CopyFrom…) → IL2CPP "Unresolved method reference". Sửa trong DLL.
while IFS= read -r dll; do
    grep -qaE "NativeReferenceUnsafeUtility|NativeListUnsafeUtility|JobReflectionDataCreationFailed|UnsafeList" "$dll" || continue
    MONO_BIN="$UNITY_HOME/Editor/Data/MonoBleedingEdge/bin"
    CECIL="$UNITY_HOME/Editor/Data/MonoBleedingEdge/lib/mono/gac/Mono.Cecil/0.11.1.0__0738eb9f132ed756/Mono.Cecil.dll"
    FIX_EXE="/tmp/fix_collections_refs.exe"
    if [ ! -f "$FIX_EXE" ] || [ "$SCRIPT_DIR/fix_collections_refs.cs" -nt "$FIX_EXE" ]; then
        "$MONO_BIN/mcs" -target:exe -out:"$FIX_EXE" -r:"$CECIL" "$SCRIPT_DIR/fix_collections_refs.cs" 2>&1 | grep -v "warning CS" || true
    fi
    "$MONO_BIN/mono" "$FIX_EXE" --lib "$UNITY_HOME/Editor/Data/Managed/UnityEngine" "$dll" || true
done < <(find "$PROJECT/Assets" -name "*.dll" -not -path "*/Editor/*" 2>/dev/null)

# Shader chỉ được tham chiếu bởi render pipeline settings (vd Renderer2DResources
# trong UniversalRenderPipelineGlobalSettings) sẽ KHÔNG được Unity đưa vào build
# → runtime: "Cannot create required material because shader is null" rồi crash.
# Thêm chúng vào m_AlwaysIncludedShaders.
if [ -f "$SCRIPT_DIR/fix_always_included_shaders.py" ]; then
    python3 "$SCRIPT_DIR/fix_always_included_shaders.py" "$PROJECT" "$LOG" || true
fi

# Asset `UniversalRenderPipelineGlobalSettings` chứa các tham chiếu shader của
# render pipeline (CoreBlit, Sampling, BlitHDROverlay, Light2D…). Nếu KHÔNG
# đăng ký nó trong Graphics Settings thì asset bị loại khỏi build → runtime
# các shader đó = null → "Cannot create required material because shader is null".
# `EditorGraphicsSettings.SetRenderPipelineGlobalSettingsAsset` làm đúng việc này.
if [ -f "$SCRIPT_DIR/register_global_settings.cs" ]; then
    mkdir -p "$PROJECT/Assets/Editor"
    cp "$SCRIPT_DIR/register_global_settings.cs" "$PROJECT/Assets/Editor/GameHubRegisterGlobalSettings.cs"

    # Chạy 1 lần trước build để ghi map vào ProjectSettings/GraphicsSettings.asset
    # (asset global settings phải được đăng ký thì Unity mới đưa vào player build).
    # -buildTarget WebGL: asset import ở lần mở này được lần build dùng lại
    # (không có thì import cho Standalone rồi lần build import lại từ đầu).
    register_rc=0
    # timeout dài: chạy song song thì import chậm hơn nhiều; chỉ cắt khi Unity treo thật.
    timeout 3600 "$UNITY" -batchmode -nographics -quit -accept-apiupdate \
        -projectPath "$PROJECT" \
        -buildTarget WebGL \
        -executeMethod GameHubRegisterGlobalSettings.Register \
        -logFile "${LOG%.log}-register.log" >/dev/null 2>&1 || register_rc=$?
    grep "\[GameHub\]" "${LOG%.log}-register.log" 2>/dev/null | head -3 || true
    # Unity chết/bị timeout giữa lúc import → Library dở dang; lần build dùng lại
    # sẽ ra bản "thành công" nhưng scene mất liên kết script ("referenced script
    # ... is missing" hàng loạt). Bỏ Library để lần build import lại từ đầu.
    if [ "$register_rc" -ne 0 ]; then
        echo "⚠️  Unity lần đăng ký URP thoát lỗi ($register_rc) — xoá Library để import lại sạch"
        rm -rf "$PROJECT/Library"
    fi
    # Lần mở trên có thể đã tự thêm lại com.unity.multiplayer.center.
    python3 "$SCRIPT_DIR/unity_package_conflicts.py" "$PROJECT" >/dev/null 2>&1 || true
fi

# Build vào thư mục tạm, thành công mới thay bản cũ: kiểm tra "index.html có tồn tại" trên thư mục
# đích sẽ coi bản CŨ là build thành công khi Unity lỗi biên dịch (và bỏ qua vòng sửa lỗi bên dưới).
OUT_FINAL="$OUT"
OUT="$OUT_FINAL.building"
rm -rf "$OUT"
export GAMEHUB_OUTPUT="$OUT"

# -buildTarget WebGL: chuyển target trước khi build (bắt buộc cho batchmode).
# Lỗi biên dịch biết cách sửa (chỉ thấy được sau một lần build) → sửa rồi build
# lại một lần.
# 6 lần: vòng sửa lỗi biên dịch và vòng thu nhỏ texture ("file is too long") dùng chung bộ đếm.
for attempt in 1 2 3 4 5 6; do
    # -accept-apiupdate: batchmode chỉ chạy API Updater (tự đổi API Unity đã đổi
    # tên như PhysicMaterial → PhysicsMaterial, CS0619 "(UnityUpgradable)") khi có cờ này.
    "$UNITY" \
        -batchmode -nographics -quit -accept-apiupdate \
        -projectPath "$PROJECT" \
        -buildTarget WebGL \
        -executeMethod GameHubBuild.PerformBuild \
        -logFile "$LOG" || true   # set -e: Unity lỗi thì vẫn phải tới bước sửa/tóm tắt
    [ -f "$OUT/index.html" ] && break
    [ "$attempt" = 6 ] && break
    # Bản WebGL > 2 GB → thu nhỏ texture rồi build lại (1024, rồi 512).
    if grep -q "The file is too long" "$LOG"; then
        export GAMEHUB_MAX_TEXTURE=$(( ${GAMEHUB_MAX_TEXTURE:-2048} / 2 ))
        cp "$LOG" "${LOG%.log}-attempt$attempt.log"
        echo "↻ Bản build > 2 GB — build lại với texture tối đa ${GAMEHUB_MAX_TEXTURE}px"
        continue
    fi
    # IL2CPP "Faster runtime" không xử lý được vài DLL cũ ("Attempting to get a fully shared
    # method…") → sinh mã kiểu "Faster (smaller) builds".
    if grep -q "Attempting to get a fully shared method" "$LOG" && [ "${GAMEHUB_IL2CPP_SIZE:-0}" != 1 ]; then
        export GAMEHUB_IL2CPP_SIZE=1
        cp "$LOG" "${LOG%.log}-attempt$attempt.log"
        echo "↻ IL2CPP lỗi generic sharing — build lại với code generation 'Faster (smaller) builds'"
        continue
    fi
    # DLL cũ (DOTS/Entities 0.x, A* ECS…) gọi API Collections đã đổi: mã đó không ai chạy tới →
    # tăng mức cắt mã để UnityLinker bỏ nó trước khi IL2CPP xử lý.
    if grep -qE "Found a method reference we cannot resolve to a method definition|Unresolved method reference :" "$LOG" && [ -z "${GAMEHUB_STRIP_LEVEL:-}" ]; then
        export GAMEHUB_STRIP_LEVEL=High
        cp "$LOG" "${LOG%.log}-attempt$attempt.log"
        echo "↻ Method reference của DLL cũ không resolve được — build lại với Managed Stripping = High"
        continue
    fi
    # CS0104/CS0165 của mã dịch ngược, UniTask.dll bị cắt (CS0656)…
    if python3 "$SCRIPT_DIR/unity_fix_compile_errors.py" "$PROJECT" "$LOG"; then
        cp "$LOG" "${LOG%.log}-attempt$attempt.log"
        echo "↻ Build lại (lần $((attempt + 1))) sau khi sửa lỗi biên dịch"
        continue
    fi
    break
done

echo
if [ -f "$OUT/index.html" ]; then
    rm -rf "$OUT_FINAL"
    mv "$OUT" "$OUT_FINAL"
    OUT="$OUT_FINAL"
    echo "✅ Build WebGL thành công!"
    echo "   $OUT/index.html"
    du -sh "$OUT"
    echo
    echo "   Copy thư mục này vào iPhone: Files → On My iPhone → GameHub → Imports"
else
    rm -rf "$OUT"
    echo "❌ Build thất bại — xem $LOG (bản web cũ, nếu có, được giữ nguyên)" >&2
    # Lỗi biên dịch C# (mỗi lỗi một dòng, bỏ trùng) — nguyên nhân phổ biến nhất.
    compile_errors="$(grep -oE "Assets/[^(]+\([0-9]+,[0-9]+\): error CS[0-9]+: .*" "$LOG" | cut -c1-240 | sort -u)"
    if [ -n "$compile_errors" ]; then
        echo "Lỗi biên dịch ($(printf '%s\n' "$compile_errors" | wc -l) dòng, 20 dòng đầu):" >&2
        printf '%s\n' "$compile_errors" | head -20 >&2
    else
        grep -iE "error|exception|Aborting" "$LOG" | tail -25 >&2
    fi
    exit 1
fi

# Dọn Library/ do trap `cleanup` lo khi script kết thúc.
