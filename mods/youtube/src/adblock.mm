// Chặn quảng cáo cho YouTube iOS 21.x (ad-slot + cell quảng cáo trong feed).
//
// Nguyên tắc an toàn (đã trả giá bằng 2 lần crash):
//  - Chỉ chặn bằng hàm `void` của pipeline ad: bỏ thân hàm.
//  - Getter danh sách → trả @[]; getter player-response của ad → nil.
//  - TUYỆT ĐỐI không trả nil từ hàm init/create/slotFrom… có kiểu trả object:
//    caller dùng kết quả ngay → EXC_BAD_ACCESS tại objc_retain
//    (YTSlotFactoryImpl.slotFromAdSlotMetadata:controlFlowLayer:).
//
// Type encoding lấy từ dump binary (đừng đoán):
//   YTAdElementsCellAPIImpl.didLoadRenderer:                     v24@0:8@16
//   YTAdElementsCellExternallyManagedSlotAdapterImpl
//       .didBindSlotData:layoutData:                             v32@0:8@16@24
//   YTBaseOpportunityAdapter.didReceiveAdSlots:adOpportunityContext: v32@0:8@16@24
//   YTCommandDrivenExternallyManagedSlotOpportunityAdapter
//       .didReceiveCommand:fromSender:                           v32@0:8@16@24
//   YTAdsControlFlowManagerImpl.lifecycleDidStartForAdSlots:context: v32@0:8@16@24
//   YTAdsControlFlowOpportunityReceivedCommandHandlerImpl
//       .executeWithCommand:entry:fromView:sender:               v48@0:8@16@24@32@40
//   YTAdBreakResponseReceivedOpportunityAdapterV2
//       .didReceiveAdBreakResponse:fromAdBreakSlot:              v32@0:8@16@24
//   YTAdClientOrganicMetadata.adSlotRenderers                    @16@0:8
//   YTAdBreakResponseReceivedOpportunityAdapterImpl
//       .adArrayFromPlayerBytesAdLayoutRenderer:adBreaks:        @32@0:8@16@24
//   YTPlayerResponse.adPlayerResponse                            @16@0:8
//
// Class ad của YouTube tải lười: cài lại mỗi 2 giây (20 giây đầu) và mỗi lần
// app về foreground.
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

enum { YTMAdSkip = 0, YTMAdEmptyArray, YTMAdNil };

typedef struct {
    const char *cls;
    const char *sel;
    int kind;
    int nargs;
    IMP hook;
    IMP *orig;
    const char *label;
} YTMAdHook;

// Log lần đầu mỗi hook để log trên máy cho biết ads đi qua đường nào.
static const char *YTMAdHookLabel(int idx);

static void ytm_ad_hit(int idx) {
    static int hits[64];
    if (idx < 0 || idx >= 64) return;
    if (hits[idx] < 3) {
        hits[idx]++;
        YTModLog(@"ads: CHẶN %s (lần %d)", YTMAdHookLabel(idx), hits[idx]);
    }
}

// --- Hàm void của pipeline ad: bỏ thân hàm ---------------------------------
static IMP _o_executeCommand;
static void h_executeCommand(id s, SEL c, id a1, id a2, id a3, id a4) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(0); return; }
    ((void (*)(id, SEL, id, id, id, id))_o_executeCommand)(s, c, a1, a2, a3, a4);
}

static IMP _o_receiveCommand;
static void h_receiveCommand(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(1); return; }
    ((void (*)(id, SEL, id, id))_o_receiveCommand)(s, c, a1, a2);
}

static IMP _o_didReceiveAdSlots;
static void h_didReceiveAdSlots(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(2); return; }
    ((void (*)(id, SEL, id, id))_o_didReceiveAdSlots)(s, c, a1, a2);
}

static IMP _o_lifecycleAdSlots;
static void h_lifecycleAdSlots(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(3); return; }
    ((void (*)(id, SEL, id, id))_o_lifecycleAdSlots)(s, c, a1, a2);
}

static IMP _o_v2DidReceive;
static void h_v2DidReceive(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(4); return; }
    ((void (*)(id, SEL, id, id))_o_v2DidReceive)(s, c, a1, a2);
}

// Cell quảng cáo trong feed/trang: không nạp renderer, không bind slot.
static IMP _o_cellDidLoad;
static void h_cellDidLoad(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(5); return; }
    ((void (*)(id, SEL, id))_o_cellDidLoad)(s, c, a1);
}

static IMP _o_cellBindSlot;
static void h_cellBindSlot(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(6); return; }
    ((void (*)(id, SEL, id, id))_o_cellBindSlot)(s, c, a1, a2);
}

// --- Getter danh sách ad → rỗng --------------------------------------------
static IMP _o_adSlotRenderers;
static id h_adSlotRenderers(id s, SEL c) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(7); return @[]; }
    return ((id (*)(id, SEL))_o_adSlotRenderers)(s, c);
}

static IMP _o_adArrayFromLayout;
static id h_adArrayFromLayout(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(8); return @[]; }
    return ((id (*)(id, SEL, id, id))_o_adArrayFromLayout)(s, c, a1, a2);
}

// --- Getter player response của ad → nil -----------------------------------
static IMP _o_adPlayerResponse;
static id h_adPlayerResponse(id s, SEL c) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(9); return nil; }
    return ((id (*)(id, SEL))_o_adPlayerResponse)(s, c);
}

#define ADHOOK(CLS, SEL, KIND, NARGS, FN, ORIG, LABEL) \
    { CLS, SEL, KIND, NARGS, (IMP)FN, &ORIG, LABEL }

static const YTMAdHook YTM_AD_HOOKS[] = {
    ADHOOK("YTAdsControlFlowOpportunityReceivedCommandHandlerImpl",
           "executeWithCommand:entry:fromView:sender:", YTMAdSkip, 4,
           h_executeCommand, _o_executeCommand, "executeWithCommand"),
    ADHOOK("YTCommandDrivenExternallyManagedSlotOpportunityAdapter",
           "didReceiveCommand:fromSender:", YTMAdSkip, 2,
           h_receiveCommand, _o_receiveCommand, "didReceiveCommand"),
    ADHOOK("YTBaseOpportunityAdapter", "didReceiveAdSlots:adOpportunityContext:",
           YTMAdSkip, 2, h_didReceiveAdSlots, _o_didReceiveAdSlots, "didReceiveAdSlots"),
    ADHOOK("YTAdsControlFlowManagerImpl", "lifecycleDidStartForAdSlots:context:",
           YTMAdSkip, 2, h_lifecycleAdSlots, _o_lifecycleAdSlots, "lifecycleDidStartForAdSlots"),
    ADHOOK("YTAdBreakResponseReceivedOpportunityAdapterV2",
           "didReceiveAdBreakResponse:fromAdBreakSlot:", YTMAdSkip, 2,
           h_v2DidReceive, _o_v2DidReceive, "didReceiveAdBreakResponse V2"),
    ADHOOK("YTAdElementsCellAPIImpl", "didLoadRenderer:", YTMAdSkip, 1,
           h_cellDidLoad, _o_cellDidLoad, "ad cell didLoadRenderer"),
    ADHOOK("YTAdElementsCellExternallyManagedSlotAdapterImpl",
           "didBindSlotData:layoutData:", YTMAdSkip, 2,
           h_cellBindSlot, _o_cellBindSlot, "ad cell didBindSlotData"),
    ADHOOK("YTAdClientOrganicMetadata", "adSlotRenderers", YTMAdEmptyArray, 0,
           h_adSlotRenderers, _o_adSlotRenderers, "adSlotRenderers=[]"),
    ADHOOK("YTAdBreakResponseReceivedOpportunityAdapterImpl",
           "adArrayFromPlayerBytesAdLayoutRenderer:adBreaks:", YTMAdEmptyArray, 2,
           h_adArrayFromLayout, _o_adArrayFromLayout, "adArray=[]"),
    ADHOOK("YTPlayerResponse", "adPlayerResponse", YTMAdNil, 0,
           h_adPlayerResponse, _o_adPlayerResponse, "adPlayerResponse=nil"),
};

#define YTM_AD_HOOK_COUNT ((int)(sizeof(YTM_AD_HOOKS) / sizeof(YTM_AD_HOOKS[0])))

static const char *YTMAdHookLabel(int idx) {
    if (idx < 0 || idx >= YTM_AD_HOOK_COUNT) return "?";
    return YTM_AD_HOOKS[idx].label;
}

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
        // Module ad của YouTube tải lười sau khi có player/feed → thử lại vài mốc.
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
