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

// --- TẦNG 1: xóa sạch dữ liệu element quảng cáo ngay khi render xin ----------
// Log 2.3: 2.2/2.3 đã hook đúng 2 lớp sizeForCellController (cả lớp cha lẫn
// YTFeedSectionController) nhưng 0 lượt gọi — element không qua đường đó.
// Cùng lúc probe (hook YTIElementRenderer.elementData) BẮT ĐƯỢC element quảng
// cáo đầy đủ → đây là cổng duy nhất chắc chắn đi qua. Trả một elementData rỗng
// (YTIElementRenderer fresh, không có renderer nào bên trong): builder không có
// gì để dựng cell, element bị bỏ qua hoàn toàn (đây là cách chặn gốc của
// YTLite/Spoof các bản mới).
static IMP _o_elData;
static id h_elData(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_elData)(s, c);
    if (!YTAdsOffEnabled()) return v;
    @try {
        // Dấu hiệu quảng cáo nằm ở MÔ TẢ CỦA CHÍNH ELEMENT RENDERER (`s`).
        NSString *desc = [s respondsToSelector:@selector(description)]
                             ? [s description] : @"";
        if (ytm_desc_is_ad(desc ?: @"")) {
            static int logged = 0;
            if (logged < 200) {
                logged++;
                YTModLog(@"eldata: XÓA dữ liệu element quảng cáo %@", s);
            }
            // 2.5 crash: trả YTIElementRenderer (sai class, khác kiểu với data)
            // → caller gọi selector của data lên nó → doesNotRecognizeSelector.
            // Cách đúng: tạo YTIElementRenderer RỖNG rồi gọi IMP GỐC elementData
            // trên nó (không qua dispatch nên hook không tự đệ quy) — kết quả là
            // data RỖNG CÙNG KIỂU với data thật, an toàn cho mọi selector mà
            // caller gọi (đúng như element không có data: hasElementData=NO).
            Class cls = object_getClass(s);
            id blank = [[cls alloc] init];
            id empty = blank
                ? ((id (*)(id, SEL))_o_elData)(blank, c)
                : nil;
            return empty ?: v;
        }
    } @catch (__unused NSException *e) {}
    return v;
}

// --- TẦNG ĐÚNG (log 3.0): không tạo controller cho element quảng cáo ---------
// Chuỗi sự kiện 18:44:14: ads didLoadRenderer bị SKIP (hook void chạy) → 47ms
// sau eldata XÓA element ad → nhưng pagead/adview + simgad VẪN tải → cell ad
// được dựng qua đường ELM, KHÔNG qua cellSizeWithSize (probe CELL chỉ thấy
// GhostCard) và không qua createCellControllerForEntry (2.7 gây trống feed).
// Cổng còn lại duy nhất: ELMControllerFactory.controllerWithElement:context:
// treeLocalContext: (@40@0:8@16@24@32) — nơi mỗi element được chuyển thành
// controller để render. Element quảng cáo → trả nil (ELM bỏ qua element này,
// như element bị xoá; caller kiểm nil chuẩn vì element có thể thiếu controller).
static IMP _o_elmCtl;
static id h_elmCtl(id s, SEL c, id element, id ctx, id treeCtx) {
    id v = ((id (*)(id, SEL, id, id, id))_o_elmCtl)(s, c, element, ctx, treeCtx);
    if (!YTAdsOffEnabled() || !element) return v;
    @try {
        NSString *desc = [element respondsToSelector:@selector(description)]
                             ? [element description] : @"";
        if (ytm_desc_is_ad(desc ?: @"")) {
            static int logged = 0;
            if (logged < 200) {
                logged++;
                YTModLog(@"elmctl: TỪ CHỐI tạo controller cho element quảng cáo %@",
                         NSStringFromClass(object_getClass(element)));
            }
            return nil;
        }
    } @catch (__unused NSException *e) {}
    return v;
}

// --- TẦNG NGUỒN (log 3.1 + phân tích binary): chặn trước khi vào ELM runtime --
// Flow feed trang chủ: browse response → YTIElementRenderer[] →
// YTBrowseContinuationSourceBlock.createElementBytesArrayFromElementRenderers:
// (@24@0:8@16) → bytes → ELM C++ runtime (youtube::elements::protos::Element) →
// cell. elementData XÓA vô hiệu vì runtime đọc BYTES (serialized từ renderer gốc,
// không qua elementData). Cổng đúng: lọc renderer quảng cáo khỏi mảng đầu vào —
// element ad sẽ KHÔNG TỒN TẠI trong runtime, không cell, không adview.
static IMP _o_bytesFromRenderers;
static id h_bytesFromRenderers(id s, SEL c, id renderers) {
    if (!YTAdsOffEnabled() || ![renderers isKindOfClass:[NSArray class]])
        return ((id (*)(id, SEL, id))_o_bytesFromRenderers)(s, c, renderers);
    NSArray *arr = (NSArray *)renderers;
    NSMutableArray *clean = nil;
    NSUInteger removed = 0;
    for (NSUInteger i = 0; i < arr.count; i++) {
        id e = arr[i];
        @try {
            NSString *desc = [e respondsToSelector:@selector(description)]
                                 ? [e description] : @"";
            if (ytm_desc_is_ad(desc ?: @"")) {
                removed++;
                if (!clean) clean = [NSMutableArray arrayWithArray:arr];
                [clean removeObject:e];
                static int logged = 0;
                if (logged < 200) {
                    logged++;
                    YTModLog(@"bytes: LỌC renderer quảng cáo %@ khỏi feed",
                             NSStringFromClass(object_getClass(e)));
                }
            }
        } @catch (__unused NSException *ex) {}
    }
    if (!removed) return ((id (*)(id, SEL, id))_o_bytesFromRenderers)(s, c, renderers);
    YTModLog(@"bytes: loại %lu renderer quảng cáo trước khi vào ELM runtime",
             (unsigned long)removed);
    return ((id (*)(id, SEL, id))_o_bytesFromRenderers)(s, c, clean ?: renderers);
}

// --- TẦNG NODE (log 3.2): cell ELM tạo node tại ELMNodeFactory ---------------
// bytes hook cài OK nhưng 0 lượt — feed home không đi qua
// YTBrowseContinuationSourceBlock. ELM dựng cell qua ELMNodeFactory
// .nodeWithElement:materializationContext: (@32@0:8@16r^v24) — cổng tạo node
// cho MỌI element. Element quảng cáo → nil: element không có node, không render
// (caller xử nil: canCreateNodeForElement: là bước kiểm tra trước đó).
static IMP _o_nodeWithElement;
static id h_nodeWithElement(id s, SEL c, id element, void *matCtx) {
    if (YTAdsOffEnabled() && element) {
        @try {
            NSString *desc = [element respondsToSelector:@selector(description)]
                                 ? [element description] : @"";
            if (ytm_desc_is_ad(desc ?: @"")) {
                static int logged = 0;
                if (logged < 200) {
                    logged++;
                    YTModLog(@"node: TỪ CHỐI tạo node cho element quảng cáo %@",
                             NSStringFromClass(object_getClass(element)));
                }
                return nil;
            }
        } @catch (__unused NSException *e) {}
    }
    return ((id (*)(id, SEL, id, void *))_o_nodeWithElement)(s, c, element, matCtx);
}

// --- Tầng cell controller (createCellControllerForEntry:) -------------------
// 2.7 BỎ: entry của hàm này là SECTION/entry lớn chứa element con — mô tả của
// nó có thể chứa ad_logging_data của element con → trả nil làm TRỐNG CẢ FEED
// (bản 2.7 gây skeleton mãi). Chỉ giữ ở tầng elementData (eldata) + size.
static IMP _o_cccBase, _o_cccFeed, _o_cccSec;
static BOOL ytm_entry_desc_is_ad(id entry) {
    if (!entry) return NO;
    @try {
        NSString *desc = [entry respondsToSelector:@selector(description)]
                             ? [entry description] : @"";
        return ytm_desc_is_ad(desc ?: @"");
    } @catch (__unused NSException *e) {
        return NO;
    }
}
static id h_cccBase(id s, SEL c, id entry) {
    return ((id (*)(id, SEL, id))_o_cccBase)(s, c, entry);
}
static id h_cccFeed(id s, SEL c, id entry) {
    return ((id (*)(id, SEL, id))_o_cccFeed)(s, c, entry);
}
static id h_cccSec(id s, SEL c, id entry) {
    return ((id (*)(id, SEL, id))_o_cccSec)(s, c, entry);
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
    if (!YTAdsOffEnabled() || CGSizeEqualToSize(r, CGSizeZero)) return r;
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

// Lớp con feed trang chủ tự định nghĩa sizeForCellController:withSize: — cài
// riêng, nếu không caller đi thẳng IMP con và bỏ qua hook của lớp cha.
static IMP _o_sizeForFeed;
static CGSize h_sizeForFeed(id s, SEL c, id cc, CGSize size) {
    CGSize r = ((CGSize (*)(id, SEL, id, CGSize))_o_sizeForFeed)(s, c, cc, size);
    if (!YTAdsOffEnabled() || CGSizeEqualToSize(r, CGSizeZero)) return r;
    @try {
        id entry = [cc respondsToSelector:@selector(entry)]
                       ? ((id (*)(id, SEL))objc_msgSend)(cc, @selector(entry))
                       : nil;
        if (!entry) return r;
        NSString *desc = [entry description] ?: @"";
        if (!ytm_desc_is_ad(desc)) return r;
        static int logged = 0;
        if (logged < 25) {
            logged++;
            YTModLog(@"feedsize: NÉN cell quảng cáo %@ (%.0fx%.0f → 0)",
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
    static BOOL done[13];
    int n = 0;
    struct { const char *cls; const char *sel; IMP hook; IMP *orig; const char *label; } all[13] = {
        {"YTISectionListRenderer", "sectionRenderers", (IMP)h_sectionRenderers, &_o_sectionRenderers, "feed"},
        {"YTIWatchNextResponse", "sectionRenderers", (IMP)h_wnSectionRenderers, &_o_wnSectionRenderers, "watch"},
        {"ELMPBFeedData", "contents", (IMP)h_feedContents, &_o_feedContents, "elm"},
        {"YTIElementTabRenderer", "contentsArray", (IMP)h_tabContents, &_o_tabContents, "tab"},
        {"YTIElementRenderer", "elementData", (IMP)h_elData, &_o_elData, "eldata"},
        {"YTSectionController", "sizeForCellController:withSize:", (IMP)h_sizeForCell, &_o_sizeForCell, "size"},
        {"YTFeedSectionController", "sizeForCellController:withSize:", (IMP)h_sizeForFeed, &_o_sizeForFeed, "feedsize"},
        {"YTBaseFeedController", "createCellControllerForEntry:", (IMP)h_cccBase, &_o_cccBase, "cell-base"},
        {"YTFeedSectionController", "createCellControllerForEntry:", (IMP)h_cccFeed, &_o_cccFeed, "cell-feed"},
        {"YTSectionController", "createCellControllerForEntry:", (IMP)h_cccSec, &_o_cccSec, "cell-sec"},
        {"ELMControllerFactory", "controllerWithElement:context:treeLocalContext:", (IMP)h_elmCtl, &_o_elmCtl, "elmctl"},
        {"YTBrowseContinuationSourceBlock", "createElementBytesArrayFromElementRenderers:", (IMP)h_bytesFromRenderers, &_o_bytesFromRenderers, "bytes"},
        {"ELMNodeFactory", "nodeWithElement:materializationContext:", (IMP)h_nodeWithElement, &_o_nodeWithElement, "node"},
    };
    for (int i = 0; i < 13; i++) {
        if (done[i]) { n++; continue; }
        if (ytm_install_one(all[i].cls, all[i].sel, all[i].hook, all[i].orig, all[i].label)) {
            done[i] = YES;
            n++;
        }
    }
    g_sectionDone = n;
}
