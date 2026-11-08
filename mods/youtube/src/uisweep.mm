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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ytm_sweep_once();
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            g_sweepTimer = [NSTimer timerWithTimeInterval:0.5
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
