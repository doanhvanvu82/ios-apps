#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>

// Menu nổi: một nút tròn nhỏ ở góc phải, chạm để mở panel 2 công tắc. Không
// dùng window riêng (YouTube có nhiều scene) — gắn thẳng vào window của scene
// đầu tiên, trên cùng.
static UIWindow *g_hostWindow = nil;
static UIButton *g_floatingButton = nil;
static UIView *g_panel = nil;

static UIColor *YTAccent(void) {
    return [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0];
}

static UILabel *YTLabel(NSString *text, UIFont *font, UIColor *color) {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = font;
    l.textColor = color;
    return l;
}

static UISwitch *YTMakeSwitch(BOOL on, id target, SEL action) {
    UISwitch *s = [UISwitch new];
    s.on = on;
    s.onTintColor = YTAccent();
    [s addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

@interface YTMenuController : NSObject
@property (nonatomic, strong) UIView *panel;
@end

@implementation YTMenuController

+ (instancetype)shared {
    static YTMenuController *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [YTMenuController new]; });
    return c;
}

- (void)togglePanel {
    if (!self.panel) [self buildPanel];
    BOOL show = self.panel.hidden;
    self.panel.hidden = !show;
    if (show) [self.panel.superview bringSubviewToFront:self.panel];
}

- (void)buildPanel {
    CGFloat w = 250;
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 226)];
    p.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.97];
    p.layer.cornerRadius = 14;
    p.layer.masksToBounds = YES;
    p.hidden = YES;

    UILabel *title = YTLabel(@"YouTube Mod", [UIFont boldSystemFontOfSize:16], UIColor.whiteColor);
    title.frame = CGRectMake(16, 12, w - 32, 22);
    [p addSubview:title];

    NSString *appVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    UILabel *ver = YTLabel([NSString stringWithFormat:@"YT %@ · mod %s", appVer, YT_VERSION_TAG],
                           [UIFont systemFontOfSize:11], [UIColor colorWithWhite:1 alpha:0.75]);
    ver.frame = CGRectMake(16, 34, w - 32, 16);
    [p addSubview:ver];

    UILabel *sub = YTLabel([NSString stringWithFormat:@"build %s · %d/%d hook", YT_BUILD_LABEL,
                            YTHooksAvailable(), YTHooksAvailable() + YTHooksFailed()],
                           [UIFont systemFontOfSize:11], [UIColor colorWithWhite:1 alpha:0.55]);
    sub.frame = CGRectMake(16, 50, w - 32, 16);
    [p addSubview:sub];

    UILabel *ads = YTLabel(@"Chặn quảng cáo", [UIFont systemFontOfSize:14], UIColor.whiteColor);
    ads.frame = CGRectMake(16, 80, 150, 20);
    [p addSubview:ads];
    UISwitch *adsSwitch = YTMakeSwitch(YTModBool(YTKeyAdsOff, YES), self, @selector(adsChanged:));
    adsSwitch.frame = CGRectMake(w - 16 - 51, 76, 51, 31);
    [p addSubview:adsSwitch];

    UILabel *bg = YTLabel(@"Phát nền", [UIFont systemFontOfSize:14], UIColor.whiteColor);
    bg.frame = CGRectMake(16, 120, 150, 20);
    [p addSubview:bg];
    UISwitch *bgSwitch = YTMakeSwitch(YTModBool(YTKeyBackground, YES), self, @selector(bgChanged:));
    bgSwitch.frame = CGRectMake(w - 16 - 51, 116, 51, 31);
    [p addSubview:bgSwitch];

    UILabel *pip = YTLabel(@"PiP khi thoát app", [UIFont systemFontOfSize:14], UIColor.whiteColor);
    pip.frame = CGRectMake(16, 160, 160, 20);
    [p addSubview:pip];
    UISwitch *pipSwitch = YTMakeSwitch(YTModBool(YTKeyPiP, YES), self, @selector(pipChanged:));
    pipSwitch.frame = CGRectMake(w - 16 - 51, 156, 51, 31);
    [p addSubview:pipSwitch];

    UILabel *note = YTLabel(@"Lưu ngay lập tức · áp dụng không cần khởi động lại",
                            [UIFont systemFontOfSize:10], [UIColor colorWithWhite:1 alpha:0.45]);
    note.frame = CGRectMake(16, 200, w - 32, 14);
    [p addSubview:note];

    self.panel = p;
    g_panel = p;
}

- (void)adsChanged:(UISwitch *)s {
    YTModSetBool(YTKeyAdsOff, s.on);
    YTModFlush();
    YTHooksApplyConfig();
}

- (void)bgChanged:(UISwitch *)s {
    YTModSetBool(YTKeyBackground, s.on);
    YTModFlush();
    YTHooksApplyConfig();
}

- (void)pipChanged:(UISwitch *)s {
    YTModSetBool(YTKeyPiP, s.on);
    YTModFlush();
    YTHooksApplyConfig();
}

- (void)positionInWindow:(UIWindow *)window {
    CGSize size = window.bounds.size;
    if (!self.panel) [self buildPanel];
    self.panel.frame = CGRectMake(size.width - 250 - 12, 60, 250, 226);
    [window addSubview:self.panel];

    if (!g_floatingButton) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(size.width - 46, size.height - 140, 36, 36);
        b.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.75];
        b.layer.cornerRadius = 18;
        [b setTitle:@"YT" forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [b addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
        g_floatingButton = b;
        [window addSubview:b];
    }
    [window bringSubviewToFront:g_floatingButton];
}

@end

static void ytm_try_attach(void) {
    if (g_hostWindow) return;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        UIWindow *w = ws.windows.firstObject;
        if (!w || w.bounds.size.width <= 0) continue;
        g_hostWindow = w;
        [[YTMenuController shared] positionInWindow:w];
        return;
    }
}

// Chờ scene/window sẵn sàng: poll nhẹ trong 30 giây đầu, sau đó chỉ gắn khi
// app quay lại foreground (scene mới sau khi iOS hủy scene).
static void ytm_schedule_attach(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!YTModBool(YTKeyMenu, YES)) return;
        ytm_try_attach();
        if (!g_hostWindow) ytm_schedule_attach(); // thử lại
    });
}

void YTMenuInstall(void) {
    ytm_schedule_attach();
}
