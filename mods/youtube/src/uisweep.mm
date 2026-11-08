// Quét UI: ẩn cell quảng cáo theo node ActiveView + giữ frame 0 (mod 3.14).
//
// Chuỗi chặn hiệu quả (log 3.12/3.13): cell quảng cáo là _ASCollectionViewCell
// chứa node ELMCellNode với node con "ActiveView"
// (YTActiveViewDisplayContainerNode — ad tracking độc quyền của Google Ads).
//
// Vấn đề 3.13: cell.hidden chỉ ẩn nội dung, cell VẪN chiếm chỗ trong layout —
// khi scroll/reload, UICollectionView đặt lại frame cell theo layoutAttributes
// → khoảng trống quay lại. Giải pháp: sweep tick 0.5s đặt LẠI frame 0 cho mọi
// cell đã ẩn còn sống (weak list). Người dùng vẫn thấy lỗ chớp ~0.5s trong lúc
// scroll, nhưng nhanh chóng được lấp lại.
#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static int g_sweepHitTotal = 0;
static NSTimer *g_sweepTimer = nil;
// Cell quảng cáo đã ẩn (weak wrapper, tự dọn khi cell dealloc).
static NSMutableArray *g_hiddenCells = nil;
// [UICollectionView, NSIndexPath] của cell ad đã ẩn — hook layout đọc để ép size 0.
static NSMutableArray *g_hiddenIndexPaths = nil;

@interface YTMWeakWrapper : NSObject
@property (nonatomic, weak) id object;
+ (instancetype)wrapperWithObject:(id)obj;
@end

@implementation YTMWeakWrapper
+ (instancetype)wrapperWithObject:(id)obj {
    YTMWeakWrapper *w = [YTMWeakWrapper new];
    w.object = obj;
    return w;
}
@end

// Đặt lại frame 0 cho mọi cell đã ẩn mà layout đã ghi đè frame.
static void ytm_rezero_hidden_cells(void) {
    if (!g_hiddenCells.count) return;
    NSMutableArray *dead = nil;
    for (YTMWeakWrapper *wrapper in g_hiddenCells) {
        UIView *cell = wrapper.object;
        if (!cell) {
            if (!dead) dead = [NSMutableArray new];
            [dead addObject:wrapper];
            continue;
        }
        CGRect f = cell.frame;
        if (cell.hidden && (f.size.width > 1 || f.size.height > 1)) {
            cell.frame = CGRectMake(f.origin.x, f.origin.y, 0, 0);
        }
    }
    if (dead) [g_hiddenCells removeObjectsInArray:dead];
}

// --- LAYOUT: ép layoutAttributes size 0 cho indexPath cell ad đã ẩn ----------
// cell.hidden + frame 0 bị layoutAttributes ghi đè khi scroll (nguyên nhân
// khoảng trống). Hook cấp UICollectionViewLayout bắt mọi subclass (feed dùng
// ASDK layout). Sửa attribute.size = 0 → layout không cấp chỗ cho cell ad.
static IMP _o_layoutAttrsInRect;
static NSArray *h_layoutAttrsInRect(id s, SEL c, CGRect rect) {
    NSArray *attrs = ((NSArray *(*)(id, SEL, CGRect))_o_layoutAttrsInRect)(s, c, rect);
    if (!YTAdsOffEnabled() || !g_hiddenIndexPaths.count || !attrs.count) return attrs;
    @try {
        NSMutableArray *modified = nil;
        for (UICollectionViewLayoutAttributes *attr in attrs) {
            NSIndexPath *ip = attr.indexPath;
            BOOL hit = NO;
            for (NSArray *pair in g_hiddenIndexPaths) {
                if (pair[0] == s && [pair[1] isEqual:ip]) { hit = YES; break; }
            }
            if (hit && !CGSizeEqualToSize(attr.size, CGSizeZero)) {
                if (!modified) modified = [attrs mutableCopy];
                UICollectionViewLayoutAttributes *a = [attr copy];
                a.frame = CGRectMake(attr.frame.origin.x, attr.frame.origin.y, 0, 0);
                [modified replaceObjectAtIndex:[attrs indexOfObject:attr] withObject:a];
                static int logged = 0;
                if (logged < 40) {
                    logged++;
                    YTModLog(@"layout: ép size 0 cho indexPath %ld-%ld (khoảng trống biến mất)",
                             (long)ip.section, (long)ip.row);
                }
            }
        }
        return modified ?: attrs;
    } @catch (__unused NSException *e) {
        return attrs;
    }
}

static void ytm_hide_ad_cell_from(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v.hidden) continue;
        NSString *clsName = NSStringFromClass(object_getClass(v));
        if ([clsName containsString:@"TextNode"]) {
            continue;  // nhánh cũ — nhãn ad không phải TextNode (log 3.7)
        }
        if ([v isKindOfClass:[UICollectionViewCell class]]) {
            UIView *cv = ((UICollectionViewCell *)v).contentView;
            for (UIView *sub in cv.subviews) {
                id node = nil;
                SEL anSel = sel_registerName("asyncdisplaykit_node");
                if ([sub respondsToSelector:anSel]) {
                    node = ((id (*)(id, SEL))objc_msgSend)(sub, anSel);
                }
                if (!node) continue;
                @try {
                    id subs = [node valueForKey:@"subnodes"];
                    if (![subs isKindOfClass:[NSArray class]]) continue;
                    BOOL isAd = NO;
                    for (id sn in (NSArray *)subs) {
                        NSString *snName = NSStringFromClass(object_getClass(sn));
                        if ([snName containsString:@"ActiveView"]) { isAd = YES; break; }
                    }
                    if (isAd && !v.hidden) {
                        v.hidden = YES;
                        v.frame = CGRectMake(v.frame.origin.x, v.frame.origin.y, 0, 0);
                        if (!g_hiddenCells) g_hiddenCells = [NSMutableArray new];
                        [g_hiddenCells addObject:[YTMWeakWrapper wrapperWithObject:v]];
                        g_sweepHitTotal++;
                        YTModLog(@"uisweep: ẨN cell quảng cáo (node %@ con ActiveView, tổng %d)",
                                 NSStringFromClass(object_getClass(node)), g_sweepHitTotal);
                    }
                } @catch (__unused NSException *e) {}
            }
            continue;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

// TẦNG TRƯỚC HIỆN RA: cell ad được nhận diện ngay khi ELMCellNode dựng node con
// — không chờ sweep. Hook YTActiveViewDisplayContainerNode.initWithElement:
// context: (@32@0:8@16@24): sau khi node được tạo (trong cell), tìm ancestor
// UICollectionViewCell và ẩn ngay — cell chưa từng hiển thị nội dung quảng cáo.
static IMP _o_avdInit;
static id h_avdInit(id s, SEL c, id element, id context) {
    id node = ((id (*)(id, SEL, id, id))_o_avdInit)(s, c, element, context);
    if (YTAdsOffEnabled()) {
        // Node quảng cáo VỪA ĐƯỢC DỰNG — đây là khoảnh khắc sớm nhất biết chắc
        // cell sắp hiển thị quảng cáo. Node sẽ được gắn vào cell ngay sau đó;
        // cài node.hidden ngay từ đầu (ASDisplayNode ẩn = view ẩn khi materialize)
        // + đánh dấu để sweep ưu tiên xử lý cell chứa nó.
        @try {
            id h = [node valueForKey:@"hidden"];
            if (!h) {
                SEL setH = sel_registerName("setHidden:");
                if ([node respondsToSelector:setH]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(node, setH, YES);
                }
            }
        } @catch (__unused NSException *e) {}
    }
    return node;
}

// Node quảng cáo vào trạng thái hiển thị — chặn NGAY LÚC ĐÓ (mỗi lần cell
// lướt vào viewport). didEnterVisibleState: v16@0:8.
static IMP _o_avdEnter;
static void h_avdEnter(id s, SEL c) {
    // Ẩn node + thu view chứa nó về 0 trước khiorig chạy.
    @try {
        SEL setH = sel_registerName("setHidden:");
        if ([s respondsToSelector:setH]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(s, setH, YES);
        }
        UIView *view = nil;
        SEL vSel = sel_registerName("view");
        if ([s respondsToSelector:vSel]) {
            view = ((id (*)(id, SEL))objc_msgSend)(s, vSel);
        }
        if (view) {
            UIView *cell = view;
            while (cell && ![cell isKindOfClass:[UICollectionViewCell class]]) {
                cell = cell.superview;
            }
            if (cell && !cell.hidden) {
                cell.hidden = YES;
                CGRect f = cell.frame;
                cell.frame = CGRectMake(f.origin.x, f.origin.y, 0, 0);
                if (!g_hiddenCells) g_hiddenCells = [NSMutableArray new];
                [g_hiddenCells addObject:[YTMWeakWrapper wrapperWithObject:cell]];
                // Lưu indexPath để hook layoutAttributes ép size 0 (layout vẫn
                // giữ size gốc — nguyên nhân khoảng trống).
                UIView *cvView = cell.superview;
                while (cvView && ![cvView isKindOfClass:[UICollectionView class]]) {
                    cvView = cvView.superview;
                }
                if ([cvView isKindOfClass:[UICollectionView class]]) {
                    UICollectionView *colView = (UICollectionView *)cvView;
                    NSIndexPath *ip = [colView indexPathForCell:(UICollectionViewCell *)cell];
                    if (ip) {
                        [g_hiddenIndexPaths addObject:@[cvView, ip]];
                        YTModLog(@"nodehide: cell ad indexPath section %ld row %ld",
                                 (long)ip.section, (long)ip.row);
                    }
                }
                g_sweepHitTotal++;
                YTModLog(@"nodehide: cell quảng cáo bị ẨN ngay khi vào viewport (tổng %d)",
                         g_sweepHitTotal);
            }
        }
    } @catch (__unused NSException *e) {}
}

static void ytm_sweep_once(void) {
    if (!YTAdsOffEnabled()) return;
    @try {
        ytm_rezero_hidden_cells();
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.hidden) continue;
                ytm_hide_ad_cell_from(w);
            }
        }
    } @catch (__unused NSException *e) {}
}

void YTUISweepInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Hook sớm: node quảng cáo bị ẨN NGAY khi được dựng, trước khi cell kịp
        // lên màn hình (không phải chờ sweep).
        Class avdCls = objc_getClass("YTActiveViewDisplayContainerNode");
        Method avdM = avdCls ? class_getInstanceMethod(avdCls, sel_registerName("initWithElement:context:")) : NULL;
        if (avdM) {
            _o_avdInit = method_getImplementation(avdM);
            class_replaceMethod(avdCls, sel_registerName("initWithElement:context:"), (IMP)h_avdInit,
                                method_getTypeEncoding(avdM));
            YTModLog(@"uisweep: hook init ActiveView node OK");
        }
        Method avdE = avdCls ? class_getInstanceMethod(avdCls, sel_registerName("didEnterVisibleState")) : NULL;
        if (avdE) {
            _o_avdEnter = method_getImplementation(avdE);
            class_replaceMethod(avdCls, sel_registerName("didEnterVisibleState"), (IMP)h_avdEnter,
                                method_getTypeEncoding(avdE));
            YTModLog(@"uisweep: hook didEnterVisibleState OK");
        }
        g_hiddenCells = [NSMutableArray new];
        g_hiddenIndexPaths = [NSMutableArray new];
        // Hook layout CON thật: ASCollectionLayout (layout của ASCollectionView
        // ASDK — feed dùng nó). Hook trên UICollectionViewLayout lớp cha KHÔNG bị
        // gọi vì subclass tự implement (log 3.20: hook OK nhưng 0 lượt ép).
        Class layoutCls = objc_getClass("ASCollectionLayout");
        if (!layoutCls) layoutCls = objc_getClass("UICollectionViewLayout");
        Method lm = class_getInstanceMethod(layoutCls, sel_registerName("layoutAttributesForElementsInRect:"));
        if (lm) {
            _o_layoutAttrsInRect = method_getImplementation(lm);
            class_replaceMethod(layoutCls, sel_registerName("layoutAttributesForElementsInRect:"),
                                (IMP)h_layoutAttrsInRect, method_getTypeEncoding(lm));
            YTModLog(@"uisweep: hook layoutAttributes OK (%s)",
                     class_getName(layoutCls));
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ytm_sweep_once();
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            g_sweepTimer = [NSTimer timerWithTimeInterval:0.15
                                                  repeats:YES
                                                    block:^(NSTimer *t) {
                                                        ytm_sweep_once();
                                                        if (!YTAdsOffEnabled() && t.valid) [t invalidate];
                                                    }];
            [[NSRunLoop mainRunLoop] addTimer:g_sweepTimer forMode:NSRunLoopCommonModes];
        });
        YTModLog(@"uisweep: cài xong");
    });
}
