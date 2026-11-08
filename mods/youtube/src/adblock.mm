// Chặn quảng cáo ở tầng "ad slot" — nơi iOS 21.x thực sự dựng quảng cáo.
//
// Hook player-response (isMonetized…) chỉ tắt cờ; video quảng cáo vẫn được
// tạo từ AdBreakResponse → AdSlotRenderer → AdSlot rồi chèn vào player. Các
// class dưới đây thuộc module tải lười (lazy), nên phải thử cài lại nhiều lần
// sau khi app chạy chứ không chỉ lúc launch.
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

typedef struct {
    const char *cls;
    const char *sel;
    BOOL returnsObject; // YES: trả nil để chặn; NO: bỏ qua thân hàm (void)
    IMP hook;
    IMP *orig;
    const char *label;
} YTMAdHook;

static IMP _orig_createSlot;
static id ytm_createSlot(id self, SEL _cmd, id renderer) {
    if (YTAdsOffEnabled()) {
        YTModLog(@"ads: bỏ createSlotFromAdSlotRenderer");
        return nil;
    }
    return ((id (*)(id, SEL, id))_orig_createSlot)(self, _cmd, renderer);
}

static IMP _orig_adSlotInit;
static id ytm_adSlotInit(id self, SEL _cmd, id sid, id type, id manager, id meta,
                         id phys, id entry, id fulfill, id expir, id logging) {
    if (YTAdsOffEnabled()) {
        YTModLog(@"ads: bỏ dựng YTAdSlot");
        return nil;
    }
    return ((id (*)(id, SEL, id, id, id, id, id, id, id, id, id))_orig_adSlotInit)(
        self, _cmd, sid, type, manager, meta, phys, entry, fulfill, expir, logging);
}

static IMP _orig_rendererAdapterInit;
static id ytm_rendererAdapterInit(id self, SEL _cmd, id renderer) {
    if (YTAdsOffEnabled()) return nil;
    return ((id (*)(id, SEL, id))_orig_rendererAdapterInit)(self, _cmd, renderer);
}

static IMP _orig_breakAdapterInit;
static id ytm_breakAdapterInit(id self, SEL _cmd, id renderer) {
    if (YTAdsOffEnabled()) return nil;
    return ((id (*)(id, SEL, id))_orig_breakAdapterInit)(self, _cmd, renderer);
}

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

static IMP _orig_adPlayerResponse;
static id ytm_adPlayerResponse(id self, SEL _cmd) {
    if (YTAdsOffEnabled()) return nil;
    return ((id (*)(id, SEL))_orig_adPlayerResponse)(self, _cmd);
}

static IMP _orig_controlFlowStart;
static void ytm_controlFlowStart(id self, SEL _cmd, id slots, id ctx) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id))_orig_controlFlowStart)(self, _cmd, slots, ctx);
}

static IMP _orig_v2DidReceive;
static void ytm_v2DidReceive(id self, SEL _cmd, id resp, id slot) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id))_orig_v2DidReceive)(self, _cmd, resp, slot);
}

static const YTMAdHook YTM_AD_HOOKS[] = {
    {"YTBaseOpportunityAdapter", "createSlotFromAdSlotRenderer:", YES,
     (IMP)ytm_createSlot, &_orig_createSlot, "ads: createSlot"},
    {"YTAdSlot", "initWithSlotID:slotType:managerLayer:metadata:slotPhysicalPosition:"
                 "slotEntryTriggers:slotFulfillmentTriggers:slotExpirationTriggers:adSlotLoggingData:", YES,
     (IMP)ytm_adSlotInit, &_orig_adSlotInit, "ads: YTAdSlot init"},
    {"YTAdSlotRendererAdapter", "initWithAdSlotRenderer:", YES,
     (IMP)ytm_rendererAdapterInit, &_orig_rendererAdapterInit, "ads: renderer adapter"},
    {"YTAdSlotRendererAdapter", "initWithPrerollAdSlotRendererLegacy:", YES,
     (IMP)ytm_rendererAdapterInit, &_orig_rendererAdapterInit, "ads: preroll adapter"},
    {"YTAdBreakRendererAdapter", "initWithAdBreakRenderer:", YES,
     (IMP)ytm_breakAdapterInit, &_orig_breakAdapterInit, "ads: break adapter"},
    {"YTAdClientOrganicMetadata", "adSlotRenderers", YES,
     (IMP)ytm_adSlotRenderers, &_orig_adSlotRenderers, "ads: adSlotRenderers=[]"},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl",
     "adArrayFromPlayerBytesAdLayoutRenderer:adBreaks:", YES,
     (IMP)ytm_adArrayFromLayout, &_orig_adArrayFromLayout, "ads: adArray=[]"},
    {"YTPlayerResponse", "adPlayerResponse", YES,
     (IMP)ytm_adPlayerResponse, &_orig_adPlayerResponse, "ads: adPlayerResponse=nil"},
    {"YTAdsControlFlowManagerImpl", "lifecycleDidStartForAdSlots:context:", NO,
     (IMP)ytm_controlFlowStart, &_orig_controlFlowStart, "ads: bỏ control flow"},
    {"YTAdBreakResponseReceivedOpportunityAdapterV2",
     "didReceiveAdBreakResponse:fromAdBreakSlot:", NO,
     (IMP)ytm_v2DidReceive, &_orig_v2DidReceive, "ads: bỏ adBreak V2"},
};

#define YTM_AD_HOOK_COUNT ((int)(sizeof(YTM_AD_HOOKS) / sizeof(YTM_AD_HOOKS[0])))

static BOOL g_adDone[sizeof(YTM_AD_HOOKS) / sizeof(YTM_AD_HOOKS[0])];

static int ytm_ad_install_pass(BOOL verbose) {
    int done = 0, total = 0;
    for (int i = 0; i < YTM_AD_HOOK_COUNT; i++) {
        if (g_adDone[i]) { done++; total++; continue; }
        const YTMAdHook *h = &YTM_AD_HOOKS[i];
        total++;
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
