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

typedef struct {
    const char *cls;
    const char *sel;
    IMP hook;
    IMP *orig;
} YTMAdHook;

// --- TẦNG GỐC: ads context decorator ---------------------------------------
// decorateContext:serviceType: có tham số 2 là int64 (q) — truyền bằng thanh
// ghi 64-bit như id nên khai báo int64_t cho đúng nghĩa.
static IMP _o_decorateContext;
static void h_decorateContext(id s, SEL c, id ctx, int64_t serviceType) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, int64_t))_o_decorateContext)(s, c, ctx, serviceType);
}

static IMP _o_decorateShield;
static void h_decorateShield(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id))_o_decorateShield)(s, c, a1);
}

static IMP _o_decorateIDFA;
static void h_decorateIDFA(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id))_o_decorateIDFA)(s, c, a1);
}

// --- Hàm void của pipeline ad ---------------------------------------------
// KHÔNG chặn các callback của máy trạng thái ad break (didReceiveAdBreakResponse,
// executeWithCommand, didReceiveAdSlots, lifecycleDidStart…): chặn chúng làm
// player treo "Đã xảy ra lỗi" giữa video khi ad break mid-roll được kích hoạt.
// Việc chặn preroll đã nằm ở tầng context decorator phía trên.
static IMP _o_cellDidLoad;
static void h_cellDidLoad(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id))_o_cellDidLoad)(s, c, a1);
}

static IMP _o_cellBindSlot;
static void h_cellBindSlot(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id))_o_cellBindSlot)(s, c, a1, a2);
}

// --- Getter danh sách ad → rỗng --------------------------------------------
static IMP _o_adSlotRenderers;
static id h_adSlotRenderers(id s, SEL c) {
    if (YTAdsOffEnabled()) return @[];
    return ((id (*)(id, SEL))_o_adSlotRenderers)(s, c);
}

static IMP _o_decorateContextAcct;
static void h_decorateContextAcct(id s, SEL c, id ctx, int64_t serviceType) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, int64_t))_o_decorateContextAcct)(s, c, ctx, serviceType);
}

static IMP _o_decorateShieldAcct;
static void h_decorateShieldAcct(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id))_o_decorateShieldAcct)(s, c, a1);
}

static IMP _o_decorateIDFAAcct;
static void h_decorateIDFAAcct(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id))_o_decorateIDFAAcct)(s, c, a1);
}

#define ADHOOK(CLS, SEL, FN, ORIG) { CLS, SEL, (IMP)FN, &ORIG }

// Hook theo tên class cố định. Decorator được hook động (xem dưới) vì 21.44.4
// có nhiều lớp generated impl kế thừa.
static const YTMAdHook YTM_AD_HOOKS[] = {
    ADHOOK("YTAdsInnerTubeContextDecoratorImpl", "decorateContext:serviceType:", h_decorateContext, _o_decorateContext),
    ADHOOK("YTAdsInnerTubeContextDecoratorImpl", "decorateContextWithAdShieldSignals:", h_decorateShield, _o_decorateShield),
    ADHOOK("YTAdsInnerTubeContextDecoratorImpl", "decorateContextWithIDFA:", h_decorateIDFA, _o_decorateIDFA),
    ADHOOK("YTAccountScopedAdsInnerTubeContextDecorator", "decorateContext:serviceType:", h_decorateContextAcct, _o_decorateContextAcct),
    ADHOOK("YTAccountScopedAdsInnerTubeContextDecorator", "decorateContextWithAdShieldSignals:", h_decorateShieldAcct, _o_decorateShieldAcct),
    ADHOOK("YTAccountScopedAdsInnerTubeContextDecorator", "decorateContextWithIDFA:", h_decorateIDFAAcct, _o_decorateIDFAAcct),
    ADHOOK("YTAdElementsCellAPIImpl", "didLoadRenderer:", h_cellDidLoad, _o_cellDidLoad),
    ADHOOK("YTAdElementsCellExternallyManagedSlotAdapterImpl", "didBindSlotData:layoutData:", h_cellBindSlot, _o_cellBindSlot),
    ADHOOK("YTAdClientOrganicMetadata", "adSlotRenderers", h_adSlotRenderers, _o_adSlotRenderers),
};

#define YTM_AD_HOOK_COUNT ((int)(sizeof(YTM_AD_HOOKS) / sizeof(YTM_AD_HOOKS[0])))

static BOOL g_adDone[YTM_AD_HOOK_COUNT];

static int ytm_ad_install_pass(void) {
    int done = 0;
    for (int i = 0; i < YTM_AD_HOOK_COUNT; i++) {
        if (g_adDone[i]) { done++; continue; }
        const YTMAdHook *h = &YTM_AD_HOOKS[i];
        Class cls = objc_getClass(h->cls);
        if (!cls) continue;
        Method m = class_getInstanceMethod(cls, sel_registerName(h->sel));
        if (!m) continue;
        *h->orig = method_getImplementation(m);
        class_replaceMethod(cls, sel_registerName(h->sel), h->hook, method_getTypeEncoding(m));
        g_adDone[i] = YES;
        done++;
    }
    return done;
}

void YTAdBlockInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        YTAdsOffEnabled(); // nạp công tắc
        ytm_ad_install_pass();
        // Module ad của YouTube tải lười sau khi có player/feed → thử lại vài mốc.
        for (double t = 2.0; t <= 20.0; t += 2.0) {
            BOOL last = t >= 20.0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                int n = ytm_ad_install_pass();
                if (last && n < YTM_AD_HOOK_COUNT) YTModLog(@"ads: chỉ cài %d/%d hook", n, YTM_AD_HOOK_COUNT);
            });
        }
    });
}
