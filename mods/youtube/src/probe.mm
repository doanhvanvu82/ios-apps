// Chẩn đoán (mod 1.8): ghi log loại element/cell mà trang chủ dùng cho quảng
// cáo để lọc chính xác. Không chặn gì ở đây — chỉ quan sát.
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSMutableSet *g_elemSeen = nil;
static int g_elemCount = 0;
static NSMutableSet *g_cellSeen = nil;
static int g_cellCount = 0;
static NSMutableSet *g_secSeen = nil;
static int g_secCount = 0;

static BOOL ytm_interesting(NSString *s) {
    if (!s.length) return NO;
    NSString *low = [s lowercaseString];
    return [low containsString:@"ad_logging"] || [low containsString:@"ad_slot"] ||
           [low containsString:@"ad_event"] || [low containsString:@"promoted"] ||
           [low containsString:@"promo"] || [low containsString:@"sponsored"];
}

// Element: chỉ khi mô tả nhắc tới ad/promo mới in đầy đủ (cắt bớt) — để thấy
// chính xác loại renderer mà feed dùng cho quảng cáo.
static IMP _o_elementData;
static id h_elementData(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_elementData)(s, c);
    @try {
        if (g_elemCount < 200) {
            NSString *desc = [s description];
            if (!g_elemSeen) g_elemSeen = [NSMutableSet new];
            if (ytm_interesting(desc)) {
                NSString *key = desc.length > 400 ? [desc substringToIndex:400] : desc;
                if (![g_elemSeen containsObject:key]) {
                    [g_elemSeen addObject:key];
                    g_elemCount++;
                    YTModLog(@"probe: ELEM-AD %@", key);
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return v;
}

// Section: log class từng phần tử + getter quảng cáo nào nó trả lời.
static IMP _o_secSec;
static id h_secSec(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_secSec)(s, c);
    if (g_secCount < 80 && [v isKindOfClass:[NSArray class]]) {
        if (!g_secSeen) g_secSeen = [NSMutableSet new];
        for (id e in (NSArray *)v) {
            NSString *cn = NSStringFromClass(object_getClass(e));
            if (!cn || [g_secSeen containsObject:cn]) continue;
            [g_secSeen addObject:cn];
            g_secCount++;
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

// Cell base: ghi class cell thật + entry/element của nó khi cell thuộc diện
// ad/promo (theo tên class HOẶC theo mô tả entry).
static int g_cellProbe = 0;
static IMP _o_cellSize;
static CGSize h_cellSize(id s, SEL c, CGSize size) {
    CGSize r = ((CGSize (*)(id, SEL, CGSize))_o_cellSize)(s, c, size);
    if (g_cellProbe < 200) {
        @try {
            NSString *cn = NSStringFromClass(object_getClass(s));
            id entry = nil;
            if ([s respondsToSelector:sel_registerName("elementEntry")])
                entry = ((id (*)(id, SEL))objc_msgSend)(s, sel_registerName("elementEntry"));
            else if ([s respondsToSelector:sel_registerName("entry")])
                entry = ((id (*)(id, SEL))objc_msgSend)(s, sel_registerName("entry"));
            NSString *ecn = entry ? NSStringFromClass(object_getClass(entry)) : nil;
            NSString *desc = [entry respondsToSelector:sel_registerName("description")]
                                 ? [entry description] : nil;
            // Log MỌI cell (không chỉ ad): cần biết chính xác controller nào dựng
            // cell cho element quảng cáo và entry của nó là gì.
            if (!g_cellSeen) g_cellSeen = [NSMutableSet new];
            NSString *keyAll = [NSString stringWithFormat:@"%@|%@|%.0f", cn, ecn, r.height];
            if (![g_cellSeen containsObject:keyAll]) {
                [g_cellSeen addObject:keyAll];
                g_cellProbe++;
                NSString *d300 = desc.length > 300 ? [desc substringToIndex:300] : desc;
                YTModLog(@"probe: CELL %@ entry=%@ size=%.0fx%.0f\n%@",
                         cn, ecn, r.width, r.height, d300);
            }
        } @catch (__unused NSException *e) {}
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
        // CHỈ hook nơi cellSizeWithSize: được ĐỊNH NGHĨA TRỰC TIẾP — không dùng
        // class_getInstanceMethod vì nó tìm theo chuỗi kế thừa: cài hook trên
        // lớp con trước rồi cài trên lớp cha sẽ khiến method_getImplementation
        // trả về HOOK vừa cài → _o_cellSize = h_cellSize → đệ quy (crash 2.9,
        // YouTube-182956: h_cellSize → bl _objc_retain → brk). YTIElementRenderer
        // dump: chỉ YTCellController định nghĩa trực tiếp cellSizeWithSize:.
        Class b = objc_getClass("YTCellController");
        Method bm = b ? class_getInstanceMethod(b, sel_registerName("cellSizeWithSize:")) : NULL;
        if (bm) {
            _o_cellSize = method_getImplementation(bm);
            class_replaceMethod(b, sel_registerName("cellSizeWithSize:"), (IMP)h_cellSize,
                                method_getTypeEncoding(bm));
            YTModLog(@"probe: size base YTCellController OK");
        }
    });
}
