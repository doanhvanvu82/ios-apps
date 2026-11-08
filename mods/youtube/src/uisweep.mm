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
    // DFS tìm UILabel disclaimer.
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v.hidden) continue;
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
