// Quét UI: ẩn cell quảng cáo theo dấu hiệu HIỂN THỊ cuối cùng (mod 3.4).
//
// Mọi tầng model (elementData, node, cell controller, bytes) đều không phải
// cổng duy nhất cell ad đi qua — log 2.4→3.3 chứng minh. Ý tưởng đúng của user:
// "thu DOM tìm nút Xem/Tải xuống" — YouTube iOS là native nên không có DOM,
// nhưng tương đương: quét view hierarchy tìm nhãn "Được tài trợ"/"Sponsored"
// rồi ẩn cả cell chứa nó. Đây là cổng UI cuối cùng — không cell nào hiển thị
// được mà không có view trong hierarchy.
//
// Cách làm: timer 0.5s quét các window, DFS qua view tree:
//  - UILabel text == "Được tài trợ"/"Sponsored"/"Quảng cáo"/"Ad" → là nhãn
//    disclaimer của cell quảng cáo (cell video thường không có nhãn này).
//  - Tìm ancestor của nhãn là UICollectionViewCell → ẩn (alpha 0 + clamp size
//    về 0 qua hidden + remove khỏi superview là không an toàn với diffable;
//    dùng hidden + frame zero là đủ — cell không còn chiếm chỗ nhìn thấy).
// Đếm và log số cell ẩn mỗi lần quét (chỉ khi >0).
#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static int g_sweepHitTotal = 0;
static NSTimer *g_sweepTimer = nil;

static int g_labelProbe = 0;

static BOOL ytm_label_is_ad_disclaimer(UILabel *label) {
    NSString *t = label.text ?: @"";
    if (!t.length || t.length > 60) return NO;
    NSString *low = [t.lowercaseString stringByReplacingOccurrencesOfString:@"\u00a0" withString:@" "];
    BOOL hit = ([low containsString:@"tài trợ"] ||
                [low containsString:@"sponsored"] ||
                [low containsString:@"quảng cáo"] ||
                [low isEqualToString:@"ad"] ||
                [low hasPrefix:@"ad ·"] ||
                [low hasPrefix:@"ad•"]);
    // Probe: log nhãn nào đó SUSP (chưa match) để biết text thật trên máy.
    if (!hit && g_labelProbe < 60 && t.length >= 2 && t.length <= 40 &&
        ([low containsString:@" trợ"] || [low containsString:@"sponsor"] ||
         [low containsString:@"quảng"] || [low isEqualToString:@"ad"] ||
         [low hasPrefix:@"ad "] || [low hasPrefix:@"ad·"])) {
        g_labelProbe++;
        YTModLog(@"uisweep-probe: nhãn chưa khớp: \"%@\" (class %@)", t,
                 NSStringFromClass(object_getClass(label)));
    }
    return hit;
}

static void ytm_hide_ad_cell_from(UIView *root) {
    // DFS tìm UILabel disclaimer + probe class cell.
    static NSMutableSet *cellClassesSeen;
    static dispatch_once_t onceCls;
    dispatch_once(&onceCls, ^{ cellClassesSeen = [NSMutableSet new]; });
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v.hidden) continue;
        // Probe: class của MỌI UICollectionViewCell — biết class cell quảng cáo
        // khác class cell video thế nào.
        if ([v isKindOfClass:[UICollectionViewCell class]]) {
            NSString *ccn = NSStringFromClass(object_getClass(v));
            if (![cellClassesSeen containsObject:ccn]) {
                [cellClassesSeen addObject:ccn];
                YTModLog(@"uisweep-probe: cell class %@ (%.0fx%.0f)",
                         ccn, v.frame.size.width, v.frame.size.height);
            }
            // _ASCollectionViewCell: node ELM nằm trong content view. Log class
            // node (ASDisplayNode qua KVC 'node') + đếm subview để phân biệt.
            static NSMutableSet *nodeSeen;
            static dispatch_once_t onceNode;
            dispatch_once(&onceNode, ^{ nodeSeen = [NSMutableSet new]; });
            UIView *cv = nil;
            if ([v isKindOfClass:[UICollectionViewCell class]]) {
                cv = ((UICollectionViewCell *)v).contentView;
            }
            for (UIView *sub in cv.subviews) {
                NSString *scn = NSStringFromClass(object_getClass(sub));
                id node = nil;
                @try {
                    node = [sub valueForKey:@"node"];
                } @catch (__unused NSException *e) {
                    node = nil;
                }
                if (!node) {
                    SEL anSel = sel_registerName("asyncdisplaykit_node");
                    if ([sub respondsToSelector:anSel]) {
                        node = ((id (*)(id, SEL))objc_msgSend)(sub, anSel);
                    }
                }
                NSString *ncn = node ? NSStringFromClass(object_getClass(node)) : @"(không có node)";
                NSString *key = [ccn stringByAppendingFormat:@"|%@|%@", scn, ncn];
                if (![nodeSeen containsObject:key]) {
                    [nodeSeen addObject:key];
                    YTModLog(@"uisweep-probe: %@ › %@ node=%@ subviews=%lu (%.0fx%.0f)",
                             ccn, scn, ncn,
                             (unsigned long)cv.subviews.count,
                             sub.frame.size.width, sub.frame.size.height);
                }
                // Đi sâu 1 tầng qua node.subnodes: nếu cell chứa node quảng cáo
                // (YTActiveViewDisplayContainerNode — ActiveView ad tracking của
                // Google; log 3.11 chứng minh cell ad duy nhất có node này) → ẨN cell.
                if (node) {
                    @try {
                        id subs = [node valueForKey:@"subnodes"];
                        if ([subs isKindOfClass:[NSArray class]]) {
                            BOOL isAd = NO;
                            for (id sn in subs) {
                                NSString *snName = NSStringFromClass(object_getClass(sn));
                                if ([snName containsString:@"ActiveView"]) { isAd = YES; break; }
                            }
                            if (isAd && !v.hidden) {
                                v.hidden = YES;
                                g_sweepHitTotal++;
                                YTModLog(@"uisweep: ẨN cell quảng cáo (node %@ con ActiveView, tổng %d)",
                                         ncn, g_sweepHitTotal);
                            }
                        }
                    } @catch (__unused NSException *e) {}
                }
            }
        }
        NSString *clsName = NSStringFromClass(object_getClass(v));
        if ([clsName containsString:@"TextNode"]) {
            // ASTextNode: text nằm ở attributedString/string của node.
            NSString *txt = nil;
            @try {
                id s1 = [v valueForKey:@"attributedString"];
                if ([s1 isKindOfClass:[NSAttributedString class]]) txt = [(NSAttributedString *)s1 string];
                if (!txt) {
                    id s2 = [v valueForKey:@"string"];
                    if ([s2 isKindOfClass:[NSString class]]) txt = s2;
                }
            } @catch (__unused NSException *e) {}
            if (txt.length && txt.length <= 60) {
                static int tnProbe = 0;
                if (tnProbe < 40) {
                    tnProbe++;
                    YTModLog(@"uisweep-probe: TextNode \"%@\" (%@)", txt, clsName);
                }
                NSString *low = [txt.lowercaseString stringByReplacingOccurrencesOfString:@"\u00a0" withString:@" "];
                if ([low containsString:@"tài trợ"] || [low containsString:@"sponsored"] ||
                    [low containsString:@"quảng cáo"]) {
                    UIView *cell = v;
                    while (cell && ![cell isKindOfClass:[UICollectionViewCell class]]) {
                        cell = cell.superview;
                    }
                    if (cell && !cell.hidden) {
                        cell.hidden = YES;
                        g_sweepHitTotal++;
                        YTModLog(@"uisweep: ẨN cell quảng cáo (TextNode \"%@\", tổng %d)", txt, g_sweepHitTotal);
                    }
                }
            }
            continue;
        }
        if ([v isKindOfClass:[UILabel class]] &&
            ytm_label_is_ad_disclaimer((UILabel *)v)) {
            // Tìm ancestor UICollectionViewCell/UITableViewCell.
            UIView *cell = v;
            while (cell && ![cell isKindOfClass:[UICollectionViewCell class]] &&
                   ![cell isKindOfClass:[UITableViewCell class]]) {
                cell = cell.superview;
            }
            if (cell && !cell.hidden) {
                cell.hidden = YES;
                g_sweepHitTotal++;
                YTModLog(@"uisweep: ẨN cell quảng cáo (nhãn \"%@\", ẩn tổng %d)",
                         [(UILabel *)v text], g_sweepHitTotal);
            }
            continue;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

static void ytm_sweep_once(void) {
    if (!YTAdsOffEnabled()) return;
    @try {
        static int tick = 0;
        tick++;
        int labels = 0, cells = 0;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.hidden) continue;
                // Đếm nhanh tổng UILabel trong mỗi window để chứng minh quét chạy.
                NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:w];
                while (stack.count) {
                    UIView *v = stack.lastObject;
                    [stack removeLastObject];
                    if ([v isKindOfClass:[UILabel class]]) labels++;
                    // Texture (ASDK): text node của ELM cell không phải UILabel.
                    // Đếm class có tên chứa 'TextNode'/'TextNode' để biết.
                    NSString *cn = NSStringFromClass(object_getClass(v));
                    if ([cn containsString:@"TextNode"]) labels++;
                    for (UIView *sub in v.subviews) [stack addObject:sub];
                }
                ytm_hide_ad_cell_from(w);
            }
        }
        if (tick % 10 == 1 && labels) {
            YTModLog(@"uisweep: tick %d — thấy %d UILabel (đã ẩn tổng %d cell ad)",
                     tick, labels, g_sweepHitTotal);
        }
        (void)cells;
    } @catch (__unused NSException *e) {}
}

void YTUISweepInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Quét sớm ngay khi cài (cell ad đầu app có thể đã dựng xong), rồi lặp.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ytm_sweep_once();
        });
        __block id timer = nil;
        timer = [NSTimer timerWithTimeInterval:0.5
                                       repeats:YES
                                         block:^(NSTimer *t) {
                                             ytm_sweep_once();
                                             if (!YTAdsOffEnabled() && t.valid) [t invalidate];
                                         }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        CFRelease((__bridge CFTypeRef)timer);  // runloop giữ rồi
        YTModLog(@"uisweep: cài xong");
    });
}
