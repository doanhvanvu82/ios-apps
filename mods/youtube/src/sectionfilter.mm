// Lọc bỏ entry quảng cáo/promo khỏi model trước khi dựng cell (feed trang chủ,
// trang xem). An toàn vì chỉ trả mảng đã lọc, không đổi kiểu trả về.
//
// Quảng cáo feed của 21.44.4 là element mang `ad_logging_data` /
// `ad_slot_logging_data` (xem log), không phải các cell promo cũ — nên ngoài
// tên lớp và các getter `has…Renderer` còn phải nhận diện qua mô tả protobuf.
//
// Log 2.0/2.1: ad dùng `use_video_cell_controller_on_ios` → render qua cell
// controller video thường, không có tên class "Promoted*" để chặn. Vì vậy phải
// chặn ở tầng chung: YTSectionController tra kích thước từng entry qua
// `sizeForCellController:withSize:` — entry quảng cáo bị trả CGSizeZero nên
// không chiếm chỗ, không hiện, không bấm được (cell vẫn tồn tại nhưng vô hình).
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

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
    "hasShoppingCompanionAdRenderer",
};
#define YTM_MARKER_COUNT ((int)(sizeof(YTM_MARKER_SELS) / sizeof(YTM_MARKER_SELS[0])))

// Tên lớp chứa các từ khoá này → entry quảng cáo/promo (không phụ thuộc getter).
static const char *YTM_NAME_MARKERS[] = {
    "promoted", "ypcpromotion", "mastheadad", "movieupsell",
    "subscriptionproductupsell", "interstitialpromo", "infead", "displayad",
    "organicmediaplayerad", "mealbarpromo", "shoppingad", "shoppingcompanionad",
    "adloggingdata", "adslot", "adlayout", "elementsad", "adelement",
};
#define YTM_NAME_COUNT ((int)(sizeof(YTM_NAME_MARKERS) / sizeof(YTM_NAME_MARKERS[0])))

// Tên field protobuf (dạng snake_case trong -description) của khối quảng cáo.
// Đây là dấu hiệu chắc chắn nhất: renderer video bình thường không có chúng.
static const char *YTM_DESC_MARKERS[] = {
    "ad_logging_data", "ad_slot_logging_data", "ad_layout_logging_data",
    "promoted_video_renderer", "compact_promoted_video_renderer",
    "promoted_video_inline_muted_renderer", "grid_promoted_video_renderer",
    "compact_promoted_banner_renderer", "compact_promoted_item_renderer",
    "ypc_promotion_renderer", "mealbar_promo_renderer", "promo_renderer",
    "video_masthead_ad_renderer", "in_feed_ad_layout_renderer",
    "display_ads", "brand_promo", "sponsored", "shopping_companion_ad_renderer",
    "slot_type_in_feed",
};
#define YTM_DESC_COUNT ((int)(sizeof(YTM_DESC_MARKERS) / sizeof(YTM_DESC_MARKERS[0])))

static BOOL ytm_desc_is_ad(NSString *desc) {
    if (!desc.length) return NO;
    for (int k = 0; k < YTM_DESC_COUNT; k++) {
        if ([desc rangeOfString:[NSString stringWithUTF8String:YTM_DESC_MARKERS[k]]].location != NSNotFound)
            return YES;
    }
    return NO;
}

// Kết quả nhận diện lưu theo object để không phải dựng -description nhiều lần.
static char kYTMIsAdKey;

static BOOL ytm_is_ad_entry(id obj, BOOL allowDesc) {
    if (!obj) return NO;
    NSNumber *cached = objc_getAssociatedObject(obj, &kYTMIsAdKey);
    if (cached) return cached.boolValue;
    BOOL ad = NO;
    const char *name = class_getName(object_getClass(obj));
    if (name) {
        char lower[128];
        int i = 0;
        for (; name[i] && i < 127; i++) {
            char c = name[i];
            lower[i] = (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c;
        }
        lower[i] = 0;
        for (int k = 0; k < YTM_NAME_COUNT && !ad; k++) {
            if (strstr(lower, YTM_NAME_MARKERS[k])) ad = YES;
        }
    }
    for (int k = 0; k < YTM_MARKER_COUNT && !ad; k++) {
        SEL sel = sel_registerName(YTM_MARKER_SELS[k]);
        if (![obj respondsToSelector:sel]) continue;
        if (((BOOL (*)(id, SEL))objc_msgSend)(obj, sel)) ad = YES;
    }
    // hasAdLoggingData: có mặt trên nhiều model generated (getter has-field của
    // protobuf) — chính là dấu hiệu `ad_logging_data` trong log.
    if (!ad) {
        SEL hasLogging = sel_registerName("hasAdLoggingData");
        if ([obj respondsToSelector:hasLogging]) {
            @try {
                if (((BOOL (*)(id, SEL))objc_msgSend)(obj, hasLogging)) ad = YES;
            } @catch (__unused NSException *e) {}
        }
    }
    // Chỉ dùng mô tả protobuf ở tầng element: mô tả của section lồng cả nội dung
    // bên trong, lọc theo nó sẽ xoá oan cả section chứa video thường.
    if (!ad && allowDesc && [obj respondsToSelector:@selector(description)]) {
        @try {
            ad = ytm_desc_is_ad([obj description]);
        } @catch (__unused NSException *e) {}
    }
    objc_setAssociatedObject(obj, &kYTMIsAdKey, @(ad), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return ad;
}

static NSArray *ytm_filter(id obj) {
    if (![obj isKindOfClass:[NSArray class]]) return obj;
    NSArray *arr = (NSArray *)obj;
    static Class kElement;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ kElement = NSClassFromString(@"YTIElementRenderer"); });
    BOOL elementLevel = kElement && arr.count && [arr[0] isKindOfClass:kElement];
    NSMutableArray *out = nil;
    NSUInteger n = arr.count;
    for (NSUInteger i = 0; i < n; i++) {
        id e = arr[i];
        if (!ytm_is_ad_entry(e, elementLevel)) continue;
        if (!out) out = [NSMutableArray arrayWithArray:arr];
        [out removeObjectAtIndex:i];
        n--;
        i--;
        static int logged = 0;
        if (logged < 25) {
            logged++;
            NSString *desc = [e description];
            YTModLog(@"section: BỎ %@@%p %@", NSStringFromClass(object_getClass(e)), e,
                     desc.length > 220 ? [desc substringToIndex:220] : desc);
        }
    }
    return out ? [out copy] : arr;
}

static int g_hookLog = 0;
static void ytm_log_array(const char *where, id v) {
    if (g_hookLog >= 30) return;
    if (![v isKindOfClass:[NSArray class]]) return;
    NSArray *a = (NSArray *)v;
    if (!a.count) return;
    g_hookLog++;
    NSMutableString *names = [NSMutableString string];
    NSUInteger lim = a.count > 4 ? 4 : a.count;
    for (NSUInteger i = 0; i < lim; i++)
        [names appendFormat:@" %@@%p", NSStringFromClass(object_getClass(a[i])), a[i]];
    YTModLog(@"section: %s count=%lu first:%@", where, (unsigned long)a.count, names);
}

static IMP _o_sectionRenderers;
static id h_sectionRenderers(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_sectionRenderers)(s, c);
    if (!YTAdsOffEnabled()) return v;
    ytm_log_array("feed", v);
    return ytm_filter(v);
}

static IMP _o_wnSectionRenderers;
static id h_wnSectionRenderers(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_wnSectionRenderers)(s, c);
    if (!YTAdsOffEnabled()) return v;
    ytm_log_array("watch", v);
    return ytm_filter(v);
}

static IMP _o_feedContents;
static id h_feedContents(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_feedContents)(s, c);
    if (!YTAdsOffEnabled()) return v;
    ytm_log_array("elm", v);
    return ytm_filter(v);
}

static IMP _o_tabContents;
static id h_tabContents(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_tabContents)(s, c);
    if (!YTAdsOffEnabled()) return v;
    ytm_log_array("tab", v);
    return ytm_filter(v);
}

// --- TẦNG CUỐI: nén cell quảng cáo ở section controller ---------------------
// Log 2.1: ad trang chủ là element thường có `ad_logging_data` → không có class
// "Promoted*" riêng để chặn tên. Mọi entry của section đều đi qua
// YTSectionController.sizeForCellController:withSize: để lấy kích thước cell —
// entry quảng cáo được trả CGSizeZero: không chiếm chỗ, không hiện, không bấm.
// (`use_video_cell_controller_on_ios` chỉ nghĩa là cell đó dựng bằng cell
// controller video, kích thước vẫn đi qua hàm này.)
static int g_sizeLog = 0;

static IMP _o_sizeForCell;
static CGSize h_sizeForCell(id s, SEL c, id cc, CGSize size) {
    CGSize r = ((CGSize (*)(id, SEL, id, CGSize))_o_sizeForCell)(s, c, cc, size);
    if (!YTAdsOffEnabled()) return r;
    @try {
        // cell controller có property `entry` (YTCellController) — model gốc.
        id entry = [cc respondsToSelector:@selector(entry)]
                       ? ((id (*)(id, SEL))objc_msgSend)(cc, @selector(entry))
                       : nil;
        if (!entry && [cc respondsToSelector:@selector(elementEntry)])
            entry = ((id (*)(id, SEL))objc_msgSend)(cc, @selector(elementEntry));
        if (!entry) return r;
        // Mô tả entry là nơi `ad_logging_data` xuất hiện (element renderer).
        NSString *desc = [entry description] ?: @"";
        if (!ytm_desc_is_ad(desc)) return r;
        static int logged = 0;
        if (logged < 25) {
            logged++;
            YTModLog(@"size: NÉN cell quảng cáo %@ (%.0fx%.0f → 0)",
                     NSStringFromClass(object_getClass(cc)), r.width, r.height);
        }
        return CGSizeZero;
    } @catch (__unused NSException *e) {
        return r;
    }
}

// Section-level list: chặn cả section mang renderer quảng cáo/promo đã lỡ qua
// các tầng trên.
static int g_sectionDone = 0;

static BOOL ytm_install_one(const char *clsName, const char *selName, IMP hook, IMP *orig,
                            const char *label) {
    Class cls = objc_getClass(clsName);
    if (!cls) { YTModLog(@"section MISS %s", clsName); return NO; }
    Method m = class_getInstanceMethod(cls, sel_registerName(selName));
    if (!m) return NO;
    *orig = method_getImplementation(m);
    class_replaceMethod(cls, sel_registerName(selName), hook, method_getTypeEncoding(m));
    YTModLog(@"section OK  %s.%s (%s)", clsName, selName, label);
    return YES;
}

void YTSectionFilterInstall(void) {
    // Chỉ cài mỗi hook 1 lần: cài đè lên chính mình sẽ khiến *orig trỏ vào hook
    // của mình → đệ quy vô hạn.
    static BOOL done[5];
    int n = 0;
    struct { const char *cls; const char *sel; IMP hook; IMP *orig; const char *label; } all[5] = {
        {"YTISectionListRenderer", "sectionRenderers", (IMP)h_sectionRenderers, &_o_sectionRenderers, "feed"},
        {"YTIWatchNextResponse", "sectionRenderers", (IMP)h_wnSectionRenderers, &_o_wnSectionRenderers, "watch"},
        {"ELMPBFeedData", "contents", (IMP)h_feedContents, &_o_feedContents, "elm"},
        {"YTIElementTabRenderer", "contentsArray", (IMP)h_tabContents, &_o_tabContents, "tab"},
        {"YTSectionController", "sizeForCellController:withSize:", (IMP)h_sizeForCell, &_o_sizeForCell, "size"},
    };
    for (int i = 0; i < 5; i++) {
        if (done[i]) { n++; continue; }
        if (ytm_install_one(all[i].cls, all[i].sel, all[i].hook, all[i].orig, all[i].label)) {
            done[i] = YES;
            n++;
        }
    }
    g_sectionDone = n;
}
