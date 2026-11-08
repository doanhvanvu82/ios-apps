// Chặn quảng cáo cho YouTube iOS 21.44.4.
//
// CÁCH CHÍNH (học từ YTLite, tweak còn bảo trì cho bản YouTube hiện tại):
// không decorate context quảng cáo khi gửi InnerTube — server coi phiên là
// "không monetize" nên không trả ad slot/preroll. Hook:
//   YTAdsInnerTubeContextDecoratorImpl
//   YTAccountScopedAdsInnerTubeContextDecorator
// (decorateContext:serviceType:, decorateContextWithAdShieldSignals:,
//  decorateContextWithIDFA:) — thêm hai hàm sau chặn tín hiệu IDFA/ad-shield
// và tracking "allow ads" để server không gắn ads vào phiên.
//
// Chặn bổ sung ở client cho ad slot/cell đã lỡ nhận:
//  - hàm `void` của pipeline ad: bỏ thân hàm;
//  - getter danh sách ad → @[]; getter player-response của ad → nil.
//
// Nguyên tắc an toàn (đã trả giá bằng 2 lần crash):
//  - TUYỆT ĐỐI không trả nil từ hàm init/create/slotFrom… trả object: caller
//    dùng kết quả ngay → EXC_BAD_ACCESS tại objc_retain
//    (YTSlotFactoryImpl.slotFromAdSlotMetadata:controlFlowLayer:).
//  - Chỉ hook hàm có type encoding đã đối chiếu từ binary; hàm void-ify phải
//    thật là `v…`, nếu là `@…` thì phải gọi lại gốc và trả giá trị.
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
    IMP hook;
    IMP *orig;
    const char *label;
} YTMAdHook;

static int g_hitCount[32];

static void ytm_ad_hit(int idx, const char *label) {
    if (idx < 0 || idx >= 32) return;
    if (g_hitCount[idx] < 3) {
        g_hitCount[idx]++;
        YTModLog(@"ads: CHẶN %s (lần %d)", label, g_hitCount[idx]);
    }
}

// --- TẦNG GỐC: ads context decorator ---------------------------------------
// decorateContext:serviceType: có tham số 2 là int64 (q) — truyền bằng thanh
// ghi 64-bit như id nên khai báo int64_t cho đúng nghĩa.
static IMP _o_decorateContext;
static void h_decorateContext(id s, SEL c, id ctx, int64_t serviceType) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(0, "ads ctx decorate"); return; }
    ((void (*)(id, SEL, id, int64_t))_o_decorateContext)(s, c, ctx, serviceType);
}

static IMP _o_decorateShield;
static void h_decorateShield(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(1, "ads ctx shield"); return; }
    ((void (*)(id, SEL, id))_o_decorateShield)(s, c, a1);
}

static IMP _o_decorateIDFA;
static void h_decorateIDFA(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(2, "ads ctx idfa"); return; }
    ((void (*)(id, SEL, id))_o_decorateIDFA)(s, c, a1);
}

// --- Hàm void của pipeline ad: bỏ thân hàm ---------------------------------
static IMP _o_executeCommand;
static void h_executeCommand(id s, SEL c, id a1, id a2, id a3, id a4) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(3, "executeWithCommand"); return; }
    ((void (*)(id, SEL, id, id, id, id))_o_executeCommand)(s, c, a1, a2, a3, a4);
}

static IMP _o_receiveCommand;
static void h_receiveCommand(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(4, "didReceiveCommand"); return; }
    ((void (*)(id, SEL, id, id))_o_receiveCommand)(s, c, a1, a2);
}

static IMP _o_didReceiveAdSlots;
static void h_didReceiveAdSlots(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(5, "didReceiveAdSlots"); return; }
    ((void (*)(id, SEL, id, id))_o_didReceiveAdSlots)(s, c, a1, a2);
}

static IMP _o_lifecycleAdSlots;
static void h_lifecycleAdSlots(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(6, "lifecycleDidStartForAdSlots"); return; }
    ((void (*)(id, SEL, id, id))_o_lifecycleAdSlots)(s, c, a1, a2);
}

static IMP _o_v2DidReceive;
static void h_v2DidReceive(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(7, "didReceiveAdBreakResponse V2"); return; }
    ((void (*)(id, SEL, id, id))_o_v2DidReceive)(s, c, a1, a2);
}

// Cell quảng cáo trong feed/trang: không nạp renderer, không bind slot.
static IMP _o_cellDidLoad;
static void h_cellDidLoad(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(8, "ad cell didLoadRenderer"); return; }
    ((void (*)(id, SEL, id))_o_cellDidLoad)(s, c, a1);
}

static IMP _o_cellBindSlot;
static void h_cellBindSlot(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(9, "ad cell didBindSlotData"); return; }
    ((void (*)(id, SEL, id, id))_o_cellBindSlot)(s, c, a1, a2);
}

// --- Getter danh sách ad → rỗng --------------------------------------------
static IMP _o_adSlotRenderers;
static id h_adSlotRenderers(id s, SEL c) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(10, "adSlotRenderers=[]"); return @[]; }
    return ((id (*)(id, SEL))_o_adSlotRenderers)(s, c);
}

static IMP _o_adArrayFromLayout;
static id h_adArrayFromLayout(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(11, "adArray=[]"); return @[]; }
    return ((id (*)(id, SEL, id, id))_o_adArrayFromLayout)(s, c, a1, a2);
}

// --- Getter player response của ad → nil -----------------------------------
static IMP _o_adPlayerResponse;
static id h_adPlayerResponse(id s, SEL c) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(12, "adPlayerResponse=nil"); return nil; }
    return ((id (*)(id, SEL))_o_adPlayerResponse)(s, c);
}

static IMP _o_decorateContextAcct;
static void h_decorateContextAcct(id s, SEL c, id ctx, int64_t serviceType) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(13, "account ads ctx decorate"); return; }
    ((void (*)(id, SEL, id, int64_t))_o_decorateContextAcct)(s, c, ctx, serviceType);
}

static IMP _o_decorateShieldAcct;
static void h_decorateShieldAcct(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(14, "account ads ctx shield"); return; }
    ((void (*)(id, SEL, id))_o_decorateShieldAcct)(s, c, a1);
}

static IMP _o_decorateIDFAAcct;
static void h_decorateIDFAAcct(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) { ytm_ad_hit(15, "account ads ctx idfa"); return; }
    ((void (*)(id, SEL, id))_o_decorateIDFAAcct)(s, c, a1);
}

#define ADHOOK(CLS, SEL, KIND, FN, ORIG, LABEL) \
    { CLS, SEL, KIND, (IMP)FN, &ORIG, LABEL }

// Hook theo tên class cố định. Decorator được hook động (xem dưới) vì 21.44.4
// có nhiều lớp generated impl kế thừa.
static const YTMAdHook YTM_AD_HOOKS[] = {
    ADHOOK("YTAdsInnerTubeContextDecoratorImpl", "decorateContext:serviceType:",
           YTMAdSkip, h_decorateContext, _o_decorateContext, "ads ctx decorate"),
    ADHOOK("YTAdsInnerTubeContextDecoratorImpl", "decorateContextWithAdShieldSignals:",
           YTMAdSkip, h_decorateShield, _o_decorateShield, "ads ctx shield"),
    ADHOOK("YTAdsInnerTubeContextDecoratorImpl", "decorateContextWithIDFA:",
           YTMAdSkip, h_decorateIDFA, _o_decorateIDFA, "ads ctx idfa"),
    ADHOOK("YTAccountScopedAdsInnerTubeContextDecorator", "decorateContext:serviceType:",
           YTMAdSkip, h_decorateContextAcct, _o_decorateContextAcct, "account ads ctx decorate"),
    ADHOOK("YTAccountScopedAdsInnerTubeContextDecorator", "decorateContextWithAdShieldSignals:",
           YTMAdSkip, h_decorateShieldAcct, _o_decorateShieldAcct, "account ads ctx shield"),
    ADHOOK("YTAccountScopedAdsInnerTubeContextDecorator", "decorateContextWithIDFA:",
           YTMAdSkip, h_decorateIDFAAcct, _o_decorateIDFAAcct, "account ads ctx idfa"),
    ADHOOK("YTAdsControlFlowOpportunityReceivedCommandHandlerImpl",
           "executeWithCommand:entry:fromView:sender:", YTMAdSkip,
           h_executeCommand, _o_executeCommand, "executeWithCommand"),
    ADHOOK("YTCommandDrivenExternallyManagedSlotOpportunityAdapter",
           "didReceiveCommand:fromSender:", YTMAdSkip,
           h_receiveCommand, _o_receiveCommand, "didReceiveCommand"),
    ADHOOK("YTBaseOpportunityAdapter", "didReceiveAdSlots:adOpportunityContext:",
           YTMAdSkip, h_didReceiveAdSlots, _o_didReceiveAdSlots, "didReceiveAdSlots"),
    ADHOOK("YTAdsControlFlowManagerImpl", "lifecycleDidStartForAdSlots:context:",
           YTMAdSkip, h_lifecycleAdSlots, _o_lifecycleAdSlots, "lifecycleDidStartForAdSlots"),
    ADHOOK("YTAdBreakResponseReceivedOpportunityAdapterV2",
           "didReceiveAdBreakResponse:fromAdBreakSlot:", YTMAdSkip,
           h_v2DidReceive, _o_v2DidReceive, "didReceiveAdBreakResponse V2"),
    ADHOOK("YTAdElementsCellAPIImpl", "didLoadRenderer:", YTMAdSkip,
           h_cellDidLoad, _o_cellDidLoad, "ad cell didLoadRenderer"),
    ADHOOK("YTAdElementsCellExternallyManagedSlotAdapterImpl",
           "didBindSlotData:layoutData:", YTMAdSkip,
           h_cellBindSlot, _o_cellBindSlot, "ad cell didBindSlotData"),
    ADHOOK("YTAdClientOrganicMetadata", "adSlotRenderers", YTMAdEmptyArray,
           h_adSlotRenderers, _o_adSlotRenderers, "adSlotRenderers=[]"),
    ADHOOK("YTAdBreakResponseReceivedOpportunityAdapterImpl",
           "adArrayFromPlayerBytesAdLayoutRenderer:adBreaks:", YTMAdEmptyArray,
           h_adArrayFromLayout, _o_adArrayFromLayout, "adArray=[]"),
    ADHOOK("YTPlayerResponse", "adPlayerResponse", YTMAdNil,
           h_adPlayerResponse, _o_adPlayerResponse, "adPlayerResponse=nil"),
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
    done += 0;
    return done;
}

void YTAdBlockInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        YTAdsOffEnabled(); // nạp công tắc
        int n = ytm_ad_install_pass(YES);
        YTModLog(@"ads: %d hook ngay (module còn lại cài sau)", n);
        // Module ad của YouTube tải lười sau khi có player/feed → thử lại vài mốc.
        for (double t = 2.0; t <= 20.0; t += 2.0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ytm_ad_install_pass(NO);
            });
        }
    });
}
