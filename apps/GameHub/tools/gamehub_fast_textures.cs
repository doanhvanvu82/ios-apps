// Nén texture nhanh khi build WebGL.
//
// Texture chiếm ~94% thời gian import (hàng nghìn texture/game, nén ASTC). Chất
// lượng nén "Fast" encode nhanh hơn nhiều so với Normal/Best mà trên màn hình
// điện thoại không phân biệt được. Postprocessor chỉ đổi kết quả import, không
// ghi lại file .meta của game.
using UnityEditor;

public class GameHubFastTextures : AssetPostprocessor
{
    void OnPreprocessTexture()
    {
        var importer = (TextureImporter)assetImporter;
        importer.compressionQuality = 0;

        var webgl = importer.GetPlatformTextureSettings("WebGL");
        if (webgl.overridden)
        {
            webgl.compressionQuality = 0;
            importer.SetPlatformTextureSettings(webgl);
        }
    }
}
