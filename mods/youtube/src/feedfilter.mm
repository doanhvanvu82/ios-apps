// Lọc quảng cáo feed (trang chủ, trang xem, kết quả tìm kiếm) ở tầng model.
//
// Thay cho sectionfilter/promo/uisweep (3.x): các bản đó chặn ở tầng cell —
// cell quảng cáo vẫn được dựng rồi mới ẩn/nén nên để lại khoảng trống, và
// hook tầng ELM/promo làm trống trang cá nhân. Ở đây bỏ section quảng cáo khỏi
// mảng section của YTInnerTubeCollectionViewController TRƯỚC khi nó tạo section
// controller: không có cell, không có khoảng trống (cách của YouTube-X/YTLite).
//
// Nhận diện quảng cáo: element có compatibility_options.ad_logging_data (log
// 3.x: mọi element quảng cáo feed đều có), hoặc mô tả protobuf chứa layout chỉ
// dùng cho quảng cáo.
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSArray<NSString *> *ytm_ad_layouts(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[@"brand_promo", @"feed_ad_metadata", @"text_search_ad", @"statement_banner",
                 @"product_carousel", @"product_engagement_panel", @"product_item",
                 @"shopping_carousel", @"shopping_item_card_list", @"square_image_layout",
                 @"text_image_button_layout", @"landscape_image_wide_button_layout",
                 @"full_width_square_image_layout", @"full_width_portrait_image_layout",
                 @"video_display_full_layout", @"video_display_full_buttoned_layout",
                 @"carousel_footered_layout", @"carousel_headered_layout"];
    });
    return list;
}

static id ytm_get(id obj, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!obj || ![obj respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, s);
}

static BOOL ytm_has(id obj, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!obj || ![obj respondsToSelector:s]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(obj, s);
}

static BOOL ytm_element_is_ad(id element) {
    if (!element) return NO;
    if (ytm_has(element, "hasCompatibilityOptions")
        && ytm_has(ytm_get(element, "compatibilityOptions"), "hasAdLoggingData")) {
        return YES;
    }
    NSString *desc = [element description];
    for (NSString *marker in ytm_ad_layouts()) {
        if ([desc containsString:marker]) return YES;
    }
    return NO;
}

// Một mục trong section (YTIItemSectionSupportedRenderers) có phải quảng cáo.
static BOOL ytm_item_is_ad(id item) {
    if (ytm_has(item, "hasPromotedVideoRenderer") || ytm_has(item, "hasCompactPromotedVideoRenderer")
        || ytm_has(item, "hasPromotedVideoInlineMutedRenderer")) {
        return YES;
    }
    return ytm_has(item, "hasElementRenderer") && ytm_element_is_ad(ytm_get(item, "elementRenderer"));
}

// Section quảng cáo → YES (bỏ cả section). Section lẫn nội dung thường → lọc
// mục quảng cáo bên trong, giữ section.
static BOOL ytm_section_is_ad(id section) {
    static Class itemSection;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ itemSection = objc_getClass("YTIItemSectionRenderer"); });
    if (!itemSection || ![section isKindOfClass:itemSection]) return NO;
    NSMutableArray *items = ytm_get(section, "contentsArray");
    if (![items isKindOfClass:[NSMutableArray class]] || !items.count) return NO;
    if (items.count > 1) {
        NSIndexSet *ads = [items indexesOfObjectsPassingTest:^BOOL(id item, __unused NSUInteger i, __unused BOOL *stop) {
            return ytm_item_is_ad(item);
        }];
        if (ads.count && ads.count < items.count) {
            [items removeObjectsAtIndexes:ads];
            return NO;
        }
    }
    return ytm_item_is_ad(items.firstObject);
}

static NSIndexSet *ytm_ad_sections(NSArray *sections) {
    @try {
        return [sections indexesOfObjectsPassingTest:^BOOL(id s, __unused NSUInteger i, __unused BOOL *stop) {
            return ytm_section_is_ad(s);
        }];
    } @catch (NSException *e) {
        YTModLog(@"feed: lỗi khi lọc %@", e.reason);
        return [NSIndexSet indexSet];
    }
}

static Ivar g_sectionsIvar;

// Tải lại toàn bộ (lượt đầu, kéo làm mới): lọc mảng _sectionRenderers tại chỗ.
static IMP _o_displaySections;
static void h_displaySections(id s, SEL c, id renderer) {
    if (YTAdsOffEnabled() && g_sectionsIvar) {
        id sections = object_getIvar(s, g_sectionsIvar);
        if ([sections isKindOfClass:[NSMutableArray class]]) {
            [(NSMutableArray *)sections removeObjectsAtIndexes:ytm_ad_sections(sections)];
        }
    }
    ((void (*)(id, SEL, id))_o_displaySections)(s, c, renderer);
}

// Cuộn tải thêm (continuation).
static IMP _o_addSections;
static void h_addSections(id s, SEL c, NSArray *array) {
    if (YTAdsOffEnabled() && [array isKindOfClass:[NSArray class]]) {
        NSIndexSet *ads = ytm_ad_sections(array);
        if (ads.count) {
            NSMutableArray *clean = [array mutableCopy];
            [clean removeObjectsAtIndexes:ads];
            array = clean;
        }
    }
    ((void (*)(id, SEL, NSArray *))_o_addSections)(s, c, array);
}

static BOOL ytm_feed_hook(Class cls, const char *sel, IMP hook, IMP *orig) {
    Method m = class_getInstanceMethod(cls, sel_registerName(sel));
    if (!m) {
        YTModLog(@"feed MISS %s", sel);
        return NO;
    }
    // Hai hook đều là void(id) — khác encoding nghĩa là đổi ABI, không cài.
    const char *types = method_getTypeEncoding(m);
    if (!types || types[0] != 'v') {
        YTModLog(@"feed MISS %s (encoding %s)", sel, types ?: "?");
        return NO;
    }
    *orig = method_getImplementation(m);
    class_replaceMethod(cls, sel_registerName(sel), hook, types);
    return YES;
}

void YTFeedFilterInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = objc_getClass("YTInnerTubeCollectionViewController");
        if (!cls) {
            YTModLog(@"feed MISS class YTInnerTubeCollectionViewController");
            return;
        }
        g_sectionsIvar = class_getInstanceVariable(cls, "_sectionRenderers");
        if (!g_sectionsIvar) YTModLog(@"feed MISS ivar _sectionRenderers");
        ytm_feed_hook(cls, "displaySectionsWithReloadingSectionControllerByRenderer:",
                      (IMP)h_displaySections, &_o_displaySections);
        ytm_feed_hook(cls, "addSectionsFromArray:", (IMP)h_addSections, &_o_addSections);
    });
}
