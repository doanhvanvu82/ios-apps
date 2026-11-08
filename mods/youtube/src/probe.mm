// Chẩn đoán (mod 1.6): ghi log loại element/cell mà trang chủ dùng cho quảng
// cáo để lọc chính xác. Không chặn gì ở đây — chỉ quan sát.
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <objc/message.h>

static int g_descCount = 0;
static NSMutableSet *g_descSeen = nil;
static int g_cellCount = 0;
static NSMutableSet *g_cellSeen = nil;

// Mô tả element: YTLite so khớp [renderer description] với "brand_promo",
// "feed_ad_metadata"… nên ghi mô tả thật của bản 21.44.4 về log.
static IMP _o_elementData;
static id h_elementData(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_elementData)(s, c);
    @try {
        NSString *desc = [s description];
        if (desc.length && g_descCount < 400) {
            if (!g_descSeen) g_descSeen = [NSMutableSet new];
            NSString *key = [NSString stringWithFormat:@"%@", desc];
            if (![g_descSeen containsObject:key]) {
                [g_descSeen addObject:key];
                g_descCount++;
                YTModLog(@"probe: ELEM %@", key.length > 200 ? [key substringToIndex:200] : key);
            }
        }
    } @catch (__unused NSException *e) {}
    return v;
}

// Mảng section của feed/watch: log class của từng phần tử + các getter quảng cáo
// nào chúng trả lời (để lọc theo đúng selector).
static IMP _o_secSec;
static id h_secSec(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_secSec)(s, c);
    if (g_cellCount < 60 && [v isKindOfClass:[NSArray class]]) {
        if (!g_cellSeen) g_cellSeen = [NSMutableSet new];
        for (id e in (NSArray *)v) {
            NSString *cn = NSStringFromClass(object_getClass(e));
            if (!cn || [g_cellSeen containsObject:cn]) continue;
            [g_cellSeen addObject:cn];
            g_cellCount++;
            NSMutableString *hits = [NSMutableString string];
            static const char *probes[] = {
                "promotedVideoRenderer", "compactPromotedVideoRenderer",
                "promotedVideoInlineMutedRenderer", "gridPromotedVideoRenderer",
                "compactPromotedBannerRenderer", "compactPromotedItemRenderer",
                "ypcPromotionRenderer", "mealbarPromoRenderer", "promoRenderer",
                "videoMastheadAdRenderer", "compactMovieUpsellRenderer",
                "subscriptionProductUpsellOfferRenderer",
                "adLoggingData", "compatibilityOptions", "itemSectionRenderer",
                "sectionListRenderer", "elementRenderer", "contents",
            };
            for (size_t i = 0; i < sizeof(probes) / sizeof(probes[0]); i++) {
                SEL sel = sel_registerName(probes[i]);
                if (![e respondsToSelector:sel]) continue;
                @try {
                    id r = ((id (*)(id, SEL))objc_msgSend)(e, sel);
                    if (r) [hits appendFormat:@" %s=%@", probes[i], r];
                } @catch (__unused NSException *ex) {}
            }
            YTModLog(@"probe: SEC %@%@", cn, hits);
        }
    }
    return v;
}

// Cell base: log class thật của cell đang được tính kích thước.
static int g_szCount = 0;
static IMP _o_cellSize;
static CGSize h_cellSize(id s, SEL c, CGSize size) {
    CGSize r = ((CGSize (*)(id, SEL, CGSize))_o_cellSize)(s, c, size);
    if (g_szCount < 80) {
        NSString *cn = NSStringFromClass(object_getClass(s));
        NSString *low = [cn lowercaseString];
        if (([low containsString:@"promot"] || [low containsString:@"promo"] ||
             [low containsString:@"adcell"] || [low containsString:@"advideo"] ||
             [low containsString:@"activeview"]) && r.height > 1) {
            g_szCount++;
            YTModLog(@"probe: CELL %@ size=%.0fx%.0f", cn, r.width, r.height);
        }
    }
    return r;
}

void YTProbeInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = objc_getClass("YTIElementRenderer");
        Method m = cls ? class_getInstanceMethod(cls, sel_registerName("elementData")) : NULL;
        if (m) {
            _o_elementData = method_getImplementation(m);
            class_replaceMethod(cls, sel_registerName("elementData"), (IMP)h_elementData,
                                method_getTypeEncoding(m));
            YTModLog(@"probe: elementData OK");
        }
        cls = objc_getClass("YTISectionListRenderer");
        m = cls ? class_getInstanceMethod(cls, sel_registerName("sectionRenderers")) : NULL;
        if (m) {
            _o_secSec = method_getImplementation(m);
            class_replaceMethod(cls, sel_registerName("sectionRenderers"), (IMP)h_secSec,
                                method_getTypeEncoding(m));
            YTModLog(@"probe: sectionRenderers OK");
        }
        static const char *bases[] = {
            "YTActiveViewCellController", "YTElementsCellController",
            "YTVideoElementCellController",
        };
        for (size_t i = 0; i < sizeof(bases) / sizeof(bases[0]); i++) {
            Class b = objc_getClass(bases[i]);
            if (!b) continue;
            Method bm = class_getInstanceMethod(b, sel_registerName("cellSizeWithSize:"));
            if (!bm) continue;
            static IMP origs[3];
            origs[i] = method_getImplementation(bm);
            class_replaceMethod(b, sel_registerName("cellSizeWithSize:"), (IMP)h_cellSize,
                                method_getTypeEncoding(bm));
            YTModLog(@"probe: size base %s OK", bases[i]);
        }
    });
}
