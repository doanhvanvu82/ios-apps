// Chặn quảng cáo ở tầng "ad slot" — nơi iOS 21.x thực sự dựng quảng cáo.
//
// Chỉ hook các điểm AN TOÀN:
//  - hàm void của pipeline ads: bỏ thân hàm (không dựng/không xử lý ad);
//  - getter trả danh sách ad: trả rỗng;
//  - getter trả player response của ad: trả nil.
// KHÔNG trả nil từ hàm init/create (vd initWithSlotID… của YTAdSlot): caller gốc
// dùng kết quả ngay → crash EXC_BAD_ACCESS (SIGSEGV) tại objc_retain.
//
// Các class ad của YouTube thuộc module tải lười nên phải thử cài lại nhiều lần
// sau khi app chạy chứ không chỉ lúc launch.
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

typedef struct {
    const char *cls;
    const char *sel;
    IMP hook;
    IMP *orig;
    const char *label;
} YTMAdHook;

// --- Bỏ thân hàm void -------------------------------------------------------
static IMP _orig_controlFlowStart;static void ytm_controlFlowStart(id self, SEL _cmd, id slots, id ctx) {
    if (YTAdsOffEnabled()) {
        YTModLog(@"ads: bỏ lifecycle ad slots");
        return;
    }
    ((void (*)(id, SEL, id, id))_orig_controlFlowStart)(self, _cmd, slots, ctx);
}

static IMP _orig_v2DidReceive;
static void ytm_v2DidReceive(id self, SEL _cmd, id resp, id slot) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id))_orig_v2DidReceive)(self, _cmd, resp, slot);
}

static IMP _orig_didReceiveCommand;
static void ytm_didReceiveCommand(id self, SEL _cmd, id cmd, id sender) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id))_orig_didReceiveCommand)(self, _cmd, cmd, sender);
}

static IMP _orig_executeCommand;
static void ytm_executeCommand(id self, SEL _cmd, id cmd, id entry, id view, id sender) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id, id, id))_orig_executeCommand)(self, _cmd, cmd, entry, view, sender);
}

static IMP _orig_didReceiveAdSlots;
static void ytm_didReceiveAdSlots(id self, SEL _cmd, id slots, id ctx) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id))_orig_didReceiveAdSlots)(self, _cmd, slots, ctx);
}

// --- Getter danh sách ad → rỗng --------------------------------------------
static IMP _orig_adSlotRenderers;
static id ytm_adSlotRenderers(id self, SEL _cmd) {
    if (YTAdsOffEnabled()) return @[];
    return ((id (*)(id, SEL))_orig_adSlotRenderers)(self, _cmd);
}

static IMP _orig_adArrayFromLayout;
static id ytm_adArrayFromLayout(id self, SEL _cmd, id layout, id breaks) {
    if (YTAdsOffEnabled()) return @[];
    return ((id (*)(id, SEL, id, id))_orig_adArrayFromLayout)(self, _cmd, layout, breaks);
}

// --- Getter player response của ad → nil -----------------------------------
static IMP _orig_adPlayerResponse;
static id ytm_adPlayerResponse(id self, SEL _cmd) {
    if (YTAdsOffEnabled()) return nil;
    return ((id (*)(id, SEL))_orig_adPlayerResponse)(self, _cmd);
}

static const YTMAdHook YTM_AD_HOOKS[] = {
    {"YTAdsControlFlowOpportunityReceivedCommandHandlerImpl",
     "executeWithCommand:entry:fromView:sender:",
     (IMP)ytm_executeCommand, &_orig_executeCommand, "ads: bỏ execute command"},
    {"YTCommandDrivenExternallyManagedSlotOpportunityAdapter",
     "didReceiveCommand:fromSender:",
     (IMP)ytm_didReceiveCommand, &_orig_didReceiveCommand, "ads: bỏ receive command"},
    {"YTBaseOpportunityAdapter", "didReceiveAdSlots:adOpportunityContext:",
     (IMP)ytm_didReceiveAdSlots, &_orig_didReceiveAdSlots, "ads: bỏ didReceiveAdSlots"},
    {"YTAdsControlFlowManagerImpl", "lifecycleDidStartForAdSlots:context:",
     (IMP)ytm_controlFlowStart, &_orig_controlFlowStart, "ads: bỏ control flow"},
    {"YTAdBreakResponseReceivedOpportunityAdapterV2",
     "didReceiveAdBreakResponse:fromAdBreakSlot:",
     (IMP)ytm_v2DidReceive, &_orig_v2DidReceive, "ads: bỏ adBreak V2"},
    {"YTAdClientOrganicMetadata", "adSlotRenderers",
     (IMP)ytm_adSlotRenderers, &_orig_adSlotRenderers, "ads: adSlotRenderers=[]"},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl",
     "adArrayFromPlayerBytesAdLayoutRenderer:adBreaks:",
     (IMP)ytm_adArrayFromLayout, &_orig_adArrayFromLayout, "ads: adArray=[]"},
    {"YTPlayerResponse", "adPlayerResponse",
     (IMP)ytm_adPlayerResponse, &_orig_adPlayerResponse, "ads: adPlayerResponse=nil"},
};

#define YTM_AD_HOOK_COUNT ((int)(sizeof(YTM_AD_HOOKS) / sizeof(YTM_AD_HOOKS[0])))

static BOOL g_adDone[YTM_AD_HOOK_COUNT];

static int ytm_ad_install_pass(BOOL verbose) {
    int done = 0;
    for (int i = 0; i < YTM_AD_HOOK_COUNT; i++) {
        if (g_adDone[i]) { done++; continue; }
        const YTMAdHook *h = &YTM_AD_HOOKS[i];
        Class cls = objc_getClass(h->cls);
        if (!cls) continue;
        Method m = class_getInstanceMethod(cls, sel_registerName(h->sel));
        if (!m) {
            if (verbose) YTModLog(@"ads MISS %s %s", h->cls, h->sel);
            continue;
        }
        *h->orig = method_getImplementation(m);
        class_replaceMethod(cls, sel_registerName(h->sel), h->hook, method_getTypeEncoding(m));
        g_adDone[i] = YES;
        done++;
        if (verbose) YTModLog(@"ads OK  %s", h->label);
    }
    return done;
}

void YTAdBlockInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        YTAdsOffEnabled(); // nạp công tắc
        int n = ytm_ad_install_pass(YES);
        YTModLog(@"ads: %d/%d hook ngay (module còn lại cài sau)", n, YTM_AD_HOOK_COUNT);
        // Module ad của YouTube tải lười sau khi có player → thử lại vài mốc.
        for (double t = 2.0; t <= 20.0; t += 2.0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                int c = 0;
                for (int i = 0; i < YTM_AD_HOOK_COUNT; i++) c += g_adDone[i];
                if (c >= YTM_AD_HOOK_COUNT) return;
                int now = ytm_ad_install_pass(NO);
                if (now != c) YTModLog(@"ads: %d/%d hook sau %.0fs", now, YTM_AD_HOOK_COUNT, t);
            });
        }
    });
}
