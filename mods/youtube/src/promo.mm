// Chặn quảng cáo feed (trang chủ/trang xem) và các promo "nâng cấp Premium".
//
// Cách làm (theo hướng YTLite):
//  - Cell quảng cáo/promo trong feed: cho kích thước = 0 → cell vẫn tồn tại
//    nhưng không chiếm chỗ, không hiện nội dung, không bấm được.
//  - Promo/upsell (dialog Premium, mealbar, interstitial…): bỏ thân hàm kích
//    hoạt, hoặc trả NO cho các cổng "có được hiện promo không".
//
// Chỉ hook hàm đã đối chiếu type encoding trong binary 21.44.4.
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// ---------------------------------------------------------------------------
// 1) Cell quảng cáo/promo → kích thước 0
// ---------------------------------------------------------------------------
typedef struct {
    const char *cls;
    IMP origSize;
    IMP origInsets;
} YTMCellSizeHook;

static const char *YTM_CELL_CLASSES[] = {
    "YTMutableAdCellController",
    "YTAdMobCellController",
    "YTBackgroundPromoCellController",
    "YTCompactPromotedItemCellController",
    "YTCompactPromotedVideoCellController",
    "YTGenericPromoCellController",
    "YTPromotedVideoCellController",
    "YTShoppingAdInfoCardContentCellController",
    "YTWatchMetadataAppPromoCellController",
    "YTCompactPromotedVideoCell",
    "YTGridPromotedVideoCell",
    "YTCompactPromotedItemCell",
    "YTPromotedAppInstallCell",
    "YTPromotedTextBannerCell",
};
#define YTM_CELL_COUNT ((int)(sizeof(YTM_CELL_CLASSES) / sizeof(YTM_CELL_CLASSES[0])))

static YTMCellSizeHook g_cells[YTM_CELL_COUNT];
static int g_cellCount = 0;

static IMP ytm_cell_orig_for(Class cls, BOOL insets) {
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        for (int i = 0; i < g_cellCount; i++) {
            if (!g_cells[i].cls) continue;
            if (objc_getClass(g_cells[i].cls) != c) continue;
            IMP o = insets ? g_cells[i].origInsets : g_cells[i].origSize;
            if (o) return o;
        }
    }
    return NULL;
}

static CGSize h_cellSize(id self, SEL _cmd, CGSize size) {
    if (YTAdsOffEnabled()) return CGSizeZero;
    IMP o = ytm_cell_orig_for(object_getClass(self), NO);
    if (!o) return size;
    return ((CGSize (*)(id, SEL, CGSize))o)(self, _cmd, size);
}

static CGSize h_cellSizeInsets(id self, SEL _cmd, CGSize size, UIEdgeInsets insets) {
    if (YTAdsOffEnabled()) return CGSizeZero;
    IMP o = ytm_cell_orig_for(object_getClass(self), YES);
    if (!o) return size;
    return ((CGSize (*)(id, SEL, CGSize, UIEdgeInsets))o)(self, _cmd, size, insets);
}

// Chỉ hook lớp tự định nghĩa method (không lấy method thừa kế từ lớp cha đã
// hook → tránh orig trỏ lại chính hook của mình).
static Method ytm_own_method(Class cls, SEL sel) {
    unsigned int n = 0;
    Method *list = class_copyMethodList(cls, &n);
    Method found = NULL;
    for (unsigned int i = 0; i < n; i++) {
        if (method_getName(list[i]) == sel) { found = list[i]; break; }
    }
    free(list);
    return found;
}

static void ytm_hook_cells(void) {
    for (int i = 0; i < YTM_CELL_COUNT; i++) {
        Class cls = objc_getClass(YTM_CELL_CLASSES[i]);
        if (!cls) continue;
        BOOL already = NO;
        for (int k = 0; k < g_cellCount; k++) {
            if (objc_getClass(g_cells[k].cls) == cls) { already = YES; break; }
        }
        if (already) continue;
        if (g_cellCount >= YTM_CELL_COUNT) break;
        Method m = ytm_own_method(cls, sel_registerName("cellSizeWithSize:"));
        Method mi = ytm_own_method(cls, sel_registerName("cellSizeWithSize:safeAreaInsets:"));
        if (!m && !mi) continue;
        g_cells[g_cellCount].cls = YTM_CELL_CLASSES[i];
        g_cells[g_cellCount].origSize = NULL;
        g_cells[g_cellCount].origInsets = NULL;
        if (m) {
            g_cells[g_cellCount].origSize = method_getImplementation(m);
            class_replaceMethod(cls, method_getName(m), (IMP)h_cellSize, method_getTypeEncoding(m));
        }
        if (mi) {
            g_cells[g_cellCount].origInsets = method_getImplementation(mi);
            class_replaceMethod(cls, method_getName(mi), (IMP)h_cellSizeInsets,
                                method_getTypeEncoding(mi));
        }
        g_cellCount++;
        YTModLog(@"promo: cell %s → 0", YTM_CELL_CLASSES[i]);
    }
}

// ---------------------------------------------------------------------------
// 2) Promo/upsell trigger → bỏ thân hàm
// ---------------------------------------------------------------------------
enum { YTMPromoSkip = 0, YTMPromoNo, YTMPromoYes };

typedef struct {
    const char *cls;
    const char *sel;
    int kind;
    IMP hook;
    IMP *orig;
    const char *label;
} YTMPromoHook;

static int g_promoHits[32];
static void ytm_promo_hit(int idx, const char *label) {
    if (idx < 0 || idx >= 32) return;
    if (g_promoHits[idx] < 3) {
        g_promoHits[idx]++;
        YTModLog(@"promo: CHẶN %s (lần %d)", label, g_promoHits[idx]);
    }
}

static IMP _o_promoTriggerMatched;
static void h_promoTriggerMatched(id s, SEL c) {
    if (YTAdsOffEnabled()) { ytm_promo_hit(0, "playback upsell trigger"); return; }
    ((void (*)(id, SEL))_o_promoTriggerMatched)(s, c);
}

static IMP _o_wnTriggerPromo;
static void h_wnTriggerPromo(id s, SEL c, id a1, int a2) {
    if (YTAdsOffEnabled()) { ytm_promo_hit(1, "watchnext promo trigger"); return; }
    ((void (*)(id, SEL, id, int))_o_wnTriggerPromo)(s, c, a1, a2);
}

static IMP _o_wnDidReceivePromo;
static void h_wnDidReceivePromo(id s, SEL c, id a1, BOOL a2) {
    if (YTAdsOffEnabled()) { ytm_promo_hit(2, "watchnext received promo"); return; }
    ((void (*)(id, SEL, id, BOOL))_o_wnDidReceivePromo)(s, c, a1, a2);
}

static IMP _o_showUpsell;
static void h_showUpsell(id s, SEL c, id a1, id a2, id a3, int64_t a4, id a5, id a6) {
    if (YTAdsOffEnabled()) { ytm_promo_hit(3, "upsell alert show"); return; }
    ((void (*)(id, SEL, id, id, id, int64_t, id, id))_o_showUpsell)(s, c, a1, a2, a3, a4, a5, a6);
}

static IMP _o_mealbarStart;
static void h_mealbarStart(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) { ytm_promo_hit(4, "mealbar promo start"); return; }
    ((void (*)(id, SEL, id))_o_mealbarStart)(s, c, a1);
}

static IMP _o_surveyShow;
static void h_surveyShow(id s, SEL c, id a1, id a2) {
    if (YTAdsOffEnabled()) { ytm_promo_hit(5, "survey show"); return; }
    ((void (*)(id, SEL, id, id))_o_surveyShow)(s, c, a1, a2);
}

static IMP _o_addEventHandlers;
static void h_addEventHandlers(id s, SEL c) {
    if (YTAdsOffEnabled()) { ytm_promo_hit(6, "promo event handlers"); return; }
    ((void (*)(id, SEL))_o_addEventHandlers)(s, c);
}

// Cổng "có được hiện promo": trả NO để chặn.
static IMP _o_canShowPromo;
static BOOL h_canShowPromo(id s, SEL c) {
    if (YTAdsOffEnabled()) { ytm_promo_hit(7, "throttle canShow"); return NO; }
    return ((BOOL (*)(id, SEL))_o_canShowPromo)(s, c);
}

static IMP _o_canShowPromoCaps;
static BOOL h_canShowPromoCaps(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) return NO;
    return ((BOOL (*)(id, SEL, id))_o_canShowPromoCaps)(s, c, a1);
}

static IMP _o_canShowPromoCap;
static BOOL h_canShowPromoCap(id s, SEL c, id a1) {
    if (YTAdsOffEnabled()) return NO;
    return ((BOOL (*)(id, SEL, id))_o_canShowPromoCap)(s, c, a1);
}

static IMP _o_shouldThrottleInterstitial;
static BOOL h_shouldThrottleInterstitial(id s, SEL c) {
    if (YTAdsOffEnabled()) return YES;
    return ((BOOL (*)(id, SEL))_o_shouldThrottleInterstitial)(s, c);
}

static IMP _o_shouldShowPromotedItems;
static BOOL h_shouldShowPromotedItems(id s, SEL c) {
    if (YTAdsOffEnabled()) { ytm_promo_hit(8, "promoted items hidden"); return NO; }
    return ((BOOL (*)(id, SEL))_o_shouldShowPromotedItems)(s, c);
}

#define PROMOHOOK(CLS, SEL, KIND, FN, ORIG, LABEL) \
    { CLS, SEL, KIND, (IMP)FN, &ORIG, LABEL }

static const YTMPromoHook YTM_PROMO_HOOKS[] = {
    PROMOHOOK("YTPlaybackUpsellControllerImpl", "triggerMatched", YTMPromoSkip,
              h_promoTriggerMatched, _o_promoTriggerMatched, "playback upsell trigger"),
    PROMOHOOK("YTWatchNextUpsellControllerImpl",
              "triggerPromoFromCommandWrapperRenderer:triggerType:", YTMPromoSkip,
              h_wnTriggerPromo, _o_wnTriggerPromo, "watchnext promo trigger"),
    PROMOHOOK("YTWatchNextUpsellControllerImpl",
              "didReceiveCommandWrapperPromoRenderer:isPlayingAd:", YTMPromoSkip,
              h_wnDidReceivePromo, _o_wnDidReceivePromo, "watchnext received promo"),
    PROMOHOOK("YTUpsellAlertControllerImpl",
              "showUpsell:videoID:playlistID:toastType:cancelBlock:upsellParentResponder:", YTMPromoSkip,
              h_showUpsell, _o_showUpsell, "upsell alert show"),
    PROMOHOOK("YTAppMealbarPromoControllerImpl", "startWithFirstResponder:", YTMPromoSkip,
              h_mealbarStart, _o_mealbarStart, "mealbar promo start"),
    PROMOHOOK("YTSurveyController", "showSurveyWithRenderer:surveyParentResponder:", YTMPromoSkip,
              h_surveyShow, _o_surveyShow, "survey show"),
    PROMOHOOK("YTCommerceEventGroupHandler", "addEventHandlers", YTMPromoSkip,
              h_addEventHandlers, _o_addEventHandlers, "commerce event handlers"),
    PROMOHOOK("YTInterstitialPromoEventGroupHandler", "addEventHandlers", YTMPromoSkip,
              h_addEventHandlers, _o_addEventHandlers, "interstitial promo handlers"),
    PROMOHOOK("YTPromosheetEventGroupHandler", "addEventHandlers", YTMPromoSkip,
              h_addEventHandlers, _o_addEventHandlers, "promosheet handlers"),
    PROMOHOOK("YTPromoThrottleControllerImpl", "canShowThrottledPromo", YTMPromoNo,
              h_canShowPromo, _o_canShowPromo, "throttle canShow"),
    PROMOHOOK("YTPromoThrottleControllerImpl", "canShowThrottledPromoWithFrequencyCaps:", YTMPromoNo,
              h_canShowPromoCaps, _o_canShowPromoCaps, "throttle caps"),
    PROMOHOOK("YTPromoThrottleControllerImpl", "canShowThrottledPromoWithFrequencyCap:", YTMPromoNo,
              h_canShowPromoCap, _o_canShowPromoCap, "throttle cap"),
    PROMOHOOK("YTIShowFullscreenInterstitialCommand", "shouldThrottleInterstitial", YTMPromoYes,
              h_shouldThrottleInterstitial, _o_shouldThrottleInterstitial, "interstitial throttled"),
    PROMOHOOK("YTPromotedVideoCellController", "shouldShowPromotedItems", YTMPromoNo,
              h_shouldShowPromotedItems, _o_shouldShowPromotedItems, "promoted items hidden"),
};

#define YTM_PROMO_COUNT ((int)(sizeof(YTM_PROMO_HOOKS) / sizeof(YTM_PROMO_HOOKS[0])))
static BOOL g_promoDone[YTM_PROMO_COUNT];

static int ytm_promo_install_pass(BOOL verbose) {
    int done = 0;
    for (int i = 0; i < YTM_PROMO_COUNT && YTModGroupOn(@"promo-trigger"); i++) {
        if (g_promoDone[i]) { done++; continue; }
        const YTMPromoHook *h = &YTM_PROMO_HOOKS[i];
        Class cls = objc_getClass(h->cls);
        if (!cls) continue;
        Method m = class_getInstanceMethod(cls, sel_registerName(h->sel));
        if (!m) {
            if (verbose) YTModLog(@"promo MISS %s %s", h->cls, h->sel);
            continue;
        }
        *h->orig = method_getImplementation(m);
        class_replaceMethod(cls, sel_registerName(h->sel), h->hook, method_getTypeEncoding(m));
        g_promoDone[i] = YES;
        done++;
        if (verbose) YTModLog(@"promo OK  %s", h->label);
    }
    if (YTModGroupOn(@"promo-cell")) ytm_hook_cells();
    return done;
}

void YTPromoBlockInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        int n = ytm_promo_install_pass(YES);
        YTModLog(@"promo: %d/%d hook ngay, %d cell", n, YTM_PROMO_COUNT, g_cellCount);
        for (double t = 2.0; t <= 20.0; t += 2.0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ytm_promo_install_pass(NO);
            });
        }
    });
}
