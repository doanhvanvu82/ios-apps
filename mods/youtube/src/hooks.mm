#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

NSString *const YTKeyAdsOff = @"ads_off";
NSString *const YTKeyBackground = @"background";
NSString *const YTKeyPiP = @"pip";
NSString *const YTKeyMenu = @"menu_visible";

#ifndef YT_VERSION_TAG
#define YT_VERSION_TAG "unknown"
#endif

// Trạng thái đọc một lần lúc cài; menu đổi thì ghi NSUserDefaults rồi gọi
// YTHooksApplyConfig() để cập nhật biến.
static volatile BOOL g_adsOff = YES;
static volatile BOOL g_background = YES;
static volatile BOOL g_pip = YES;

static int g_installed = 0;
static int g_failed = 0;

static BOOL ytm_swizzle(const YTMHook *h) {
    Class cls = objc_getClass(h->cls);
    if (!cls) {
        YTModLog(@"thiếu class %s", h->cls);
        return NO;
    }
    SEL sel = sel_registerName(h->sel);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        YTModLog(@"thiếu method -[%s %s]", h->cls, h->sel);
        return NO;
    }
    IMP current = method_getImplementation(m);
    *h->orig = current;
    const char *types = method_getTypeEncoding(m);
    if (h->types && types && strcmp(h->types, types) != 0) {
        // Không chặn: chỉ cảnh báo để phát hiện lệch ABI nếu IPA khác bản dump.
        YTModLog(@"⚠️ type encoding khác dump %s %s: %s (dump: %s)",
                 h->cls, h->sel, types, h->types);
    }
    // class_replaceMethod trả về IMP cũ (có thể khác current nếu method do class
    // này thêm) — dùng current làm orig là đúng cho inherited method.
    class_replaceMethod(cls, sel, h->hook, types);
    IMP now = method_getImplementation(class_getInstanceMethod(cls, sel));
    if (now != h->hook) {
        YTModLog(@"⚠️ replace thất bại %s %s", h->cls, h->sel);
        *h->orig = current;
        return NO;
    }
    // Nếu method gốc nằm ở class cha, replace lên class con tạo bản mới; vẫn đúng
    // vì mọi instance của class con đi qua bản mới. Nhưng bản gốc trên class cha
    // vẫn *không* bị đổi (nếu có class khác dùng trực tiếp) — chấp nhận được cho
    // các class trên (không có subclass dùng chung trong YouTube).
    return YES;
}

int YTHooksInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_adsOff = YTModBool(YTKeyAdsOff, YES);
        g_background = YTModBool(YTKeyBackground, YES);
        g_pip = YTModBool(YTKeyPiP, YES);

        for (int i = 0; i < YTM_HOOK_COUNT; i++) {
            if (ytm_swizzle(&YTM_HOOKS[i])) {
                g_installed++;
                YTModLog(@"hook OK  %s", YTM_HOOKS[i].label);
            } else {
                g_failed++;
                YTModLog(@"hook MISS %s", YTM_HOOKS[i].label);
            }
        }
        YTModLog(@"hook: %d cài được, %d thiếu (mod %s)", g_installed, g_failed, YT_VERSION_TAG);
    });
    return g_installed;
}

int YTHooksAvailable(void) { return g_installed; }
int YTHooksFailed(void) { return g_failed; }

BOOL YTAdsOffEnabled(void) { return g_adsOff; }
BOOL YTBackgroundEnabled(void) { return g_background; }
BOOL YTPiPEnabled(void) { return g_pip; }

void YTHooksApplyConfig(void) {
    g_adsOff = YTModBool(YTKeyAdsOff, YES);
    g_background = YTModBool(YTKeyBackground, YES);
    g_pip = YTModBool(YTKeyPiP, YES);
    YTModLog(@"config: ads_off=%d background=%d pip=%d", g_adsOff, g_background, g_pip);
}
