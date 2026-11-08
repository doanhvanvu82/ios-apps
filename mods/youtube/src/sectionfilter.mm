// Lọc bỏ entry quảng cáo/promo khỏi model trước khi dựng cell (feed trang chủ,
// trang xem). An toàn vì chỉ trả mảng đã lọc, không đổi kiểu trả về.
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Selector "có renderer quảng cáo/promo" xuất hiện trong binary 21.44.4.
// Một số object chỉ trả lời một phần trong danh sách nên kiểm tra từng cái.
static const char *YTM_MARKER_SELS[] = {
    "hasPromotedVideoRenderer",
    "hasCompactPromotedVideoRenderer",
    "hasPromotedVideoInlineMutedRenderer",
    "hasGridPromotedVideoRenderer",
    "hasCompactPromotedBannerRenderer",
    "hasCompactPromotedItemRenderer",
    "hasYpcPromotionRenderer",
    "hasMealbarPromoRenderer",
    "hasPromoRenderer",
    "hasVideoMastheadAdRenderer",
    "hasCompactMovieUpsellRenderer",
    "hasSubscriptionProductUpsellOfferRenderer",
};
#define YTM_MARKER_COUNT ((int)(sizeof(YTM_MARKER_SELS) / sizeof(YTM_MARKER_SELS[0])))

// Tên lớp chứa các từ khoá này → entry quảng cáo/promo (không phụ thuộc getter).
static const char *YTM_NAME_MARKERS[] = {
    "promoted", "ypcpromotion", "mastheadad", "movieupsell",
    "subscriptionproductupsell", "interstitialpromo", "infead", "displayad",
    "organicmediaplayerad", "mealbarpromo",
};
#define YTM_NAME_COUNT ((int)(sizeof(YTM_NAME_MARKERS) / sizeof(YTM_NAME_MARKERS[0])))

static BOOL ytm_is_ad_entry(id obj) {
    if (!obj) return NO;
    const char *name = class_getName(object_getClass(obj));
    if (name) {
        char lower[128];
        int i = 0;
        for (; name[i] && i < 127; i++) {
            char c = name[i];
            lower[i] = (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c;
        }
        lower[i] = 0;
        for (int k = 0; k < YTM_NAME_COUNT; k++) {
            if (strstr(lower, YTM_NAME_MARKERS[k])) return YES;
        }
    }
    for (int k = 0; k < YTM_MARKER_COUNT; k++) {
        SEL sel = sel_registerName(YTM_MARKER_SELS[k]);
        if (![obj respondsToSelector:sel]) continue;
        if (((BOOL (*)(id, SEL))objc_msgSend)(obj, sel)) return YES;
    }
    return NO;
}

static NSArray *ytm_filter(id obj) {
    if (![obj isKindOfClass:[NSArray class]]) return obj;
    NSArray *arr = (NSArray *)obj;
    NSMutableArray *out = nil;
    NSUInteger n = arr.count;
    for (NSUInteger i = 0; i < n; i++) {
        id e = arr[i];
        if (ytm_is_ad_entry(e)) {
            if (!out) out = [NSMutableArray arrayWithArray:arr];
            [out removeObjectAtIndex:i];
            n--;
            i--;
        }
    }
    return out ? [out copy] : arr;
}

static IMP _o_sectionRenderers;
static id h_sectionRenderers(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_sectionRenderers)(s, c);
    if (!YTAdsOffEnabled()) return v;
    return ytm_filter(v);
}

static IMP _o_wnSectionRenderers;
static id h_wnSectionRenderers(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_wnSectionRenderers)(s, c);
    if (!YTAdsOffEnabled()) return v;
    return ytm_filter(v);
}

static BOOL g_sectionDone = NO;

static BOOL ytm_install_one(const char *clsName, const char *selName, IMP hook, IMP *orig, BOOL verbose) {
    Class cls = objc_getClass(clsName);
    if (!cls) { if (verbose) YTModLog(@"section MISS %s", clsName); return NO; }
    Method m = class_getInstanceMethod(cls, sel_registerName(selName));
    if (!m) return NO;
    *orig = method_getImplementation(m);
    class_replaceMethod(cls, sel_registerName(selName), hook, method_getTypeEncoding(m));
    if (verbose) YTModLog(@"section OK  %s.%s", clsName, selName);
    return YES;
}

void YTSectionFilterInstall(void) {
    if (g_sectionDone) return;
    BOOL a = ytm_install_one("YTISectionListRenderer", "sectionRenderers",
                             (IMP)h_sectionRenderers, &_o_sectionRenderers, YES);
    BOOL b = ytm_install_one("YTIWatchNextResponse", "sectionRenderers",
                             (IMP)h_wnSectionRenderers, &_o_wnSectionRenderers, YES);
    g_sectionDone = (a && b);
}
