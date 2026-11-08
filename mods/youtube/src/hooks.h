// Hook + menu cho dylib mod YouTube.
//
// Dùng method swizzling của ObjC runtime (class_replaceMethod) — các class cần
// sửa của YouTube đều là ObjC (kể cả Swift chỉ cần @objc), nên không phải vá
// trang __TEXT như mod Unity IL2CPP. Dylib chỉ được thêm LC_LOAD_DYLIB vào
// binary chính lúc build.
#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Khóa NSUserDefaults (suite vn.vudv.youtube.mod).
extern NSString *const YTKeyAdsOff;     // chặn quảng cáo
extern NSString *const YTKeyBackground; // phát nền (khoá máy vẫn nghe)
extern NSString *const YTKeyPiP;        // tự bật PiP khi về màn hình chính
extern NSString *const YTKeyMenu;       // hiện nút menu nổi

// Cài hook. An toàn khi gọi nhiều lần (chỉ cài lần đầu).
// Trả về số hook đã cài được.
int YTHooksInstall(void);
int YTHooksAvailable(void);
int YTHooksFailed(void);

// Đọc lại công tắc từ NSUserDefaults (gọi từ menu sau khi người dùng đổi).
void YTHooksApplyConfig(void);

// Một mục hook: class + selector + type encoding (để kiểm tra ABI) + IMP thay thế
// + nơi lưu IMP gốc.
typedef struct {
    const char *cls;
    const char *sel;
    const char *types;
    IMP hook;
    IMP *orig;
    const char *label;
} YTMHook;

// Trạng thái công tắc hiện tại (dùng trong thân hook).
BOOL YTAdsOffEnabled(void);
BOOL YTBackgroundEnabled(void);
BOOL YTPiPEnabled(void);

// Bảng hook do hook_impls.mm định nghĩa.
extern const YTMHook YTM_HOOKS[];
extern const int YTM_HOOK_COUNT;

// Menu nổi (gọi trên main thread, sau khi có window).
void YTMenuInstall(void);

// Ghi request/response mạng ra log (chẩn đoán lỗi tải dữ liệu).
void YTDiagInstall(void);

// Chặn quảng cáo ở tầng ad-slot (thử cài lại khi module lazy xuất hiện).
void YTAdBlockInstall(void);

// Chặn cell quảng cáo feed + promo/upsell Premium.
void YTPromoBlockInstall(void);

// Lọc entry quảng cáo/promo khỏi section renderers.
void YTSectionFilterInstall(void);

// Chẩn đoán element/cell quảng cáo của feed (mod 1.6).
void YTProbeInstall(void);

// Tự bật PiP khi app rời foreground (chỉ khi bật công tắc PiP).
void YTAutoPiPInstall(void);

// Quét UI ẩn cell quảng cáo theo nhãn "Được tài trợ" (cổng UI cuối cùng).
void YTUISweepInstall(void);

// Quét UI ẩn cell quảng cáo theo nhãn "Được tài trợ" (cổng UI cuối cùng).
void YTUISweepInstall(void);

#ifdef __cplusplus
}
#endif
