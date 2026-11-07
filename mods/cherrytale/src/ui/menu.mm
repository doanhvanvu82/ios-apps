// Menu nổi bằng UIKit thuần (không Swift, không xib/storyboard).
// - Nút nhỏ, kéo được, bám mép, chạm để mở/đóng panel.
// - Panel chỉ chiếm chỗ khi mở; khi đóng root view trả trong suốt cho Unity.
#import "../common.h"
#include <zlib.h>
#include <unistd.h>
#include <math.h>

#ifndef CT_RECON_PHASE
#define CT_RECON_PHASE 0
#endif
#ifndef CT_SAFE_BUILD
#define CT_SAFE_BUILD 0
#endif

static NSString *phaseLabel(void) {
    if (CT_RECON_PHASE) return @"recon";
    if (CT_SAFE_BUILD) return @"safe";
    return @"full";
}

static UIViewController *g_vc = nil;
static BOOL g_started = NO;

static const CGFloat kBtnSize = 54.0;

// ---------------------------------------------------------------------------
// View xuyên thấu: chỉ nhận chạm trong vùng điều khiển
// ---------------------------------------------------------------------------
@interface CTPassThroughView : UIView
@property (nonatomic, weak) UIView *interactiveView;
@property (nonatomic, weak) UIView *secondaryView;
@property (nonatomic, copy) void (^onLayout)(void);
@end

@implementation CTPassThroughView
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.onLayout) self.onLayout();
    if (self.superview) [self.superview bringSubviewToFront:self];
}

- (BOOL)hitView:(UIView *)v at:(CGPoint)point event:(UIEvent *)event {
    if (!v || v.hidden || v.alpha < 0.05) return NO;
    CGPoint p = [v convertPoint:point fromView:self];
    return [v pointInside:p withEvent:event];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [self hitView:self.interactiveView at:point event:event] ||
           [self hitView:self.secondaryView at:point event:event];
}
@end

// ---------------------------------------------------------------------------
// Overlay hiển thị log / danh sách
// ---------------------------------------------------------------------------
@interface CTOverlayView : UIView
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy) void (^onClose)(void);
- (void)setText:(NSString *)text;
@end

@implementation CTOverlayView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.97];
        self.layer.cornerRadius = 12;
        self.layer.masksToBounds = YES;
        _textView = [[UITextView alloc] initWithFrame:CGRectZero];
        _textView.backgroundColor = [UIColor clearColor];
        _textView.textColor = [UIColor colorWithRed:0.85 green:0.95 blue:0.85 alpha:1];
        _textView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
        _textView.editable = NO;
        [self addSubview:_textView];
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        [close setTitle:@"Đóng" forState:UIControlStateNormal];
        close.tag = 999;
        [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:close];
        close.frame = CGRectMake(frame.size.width - 70, 6, 60, 30);
        _textView.frame = CGRectMake(8, 36, frame.size.width - 16, frame.size.height - 44);
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.textView.frame = CGRectMake(8, 36, self.bounds.size.width - 16, self.bounds.size.height - 44);
    UIView *close = [self viewWithTag:999];
    close.frame = CGRectMake(self.bounds.size.width - 70, 4, 60, 30);
}
- (void)setText:(NSString *)text { self.textView.text = text ?: @""; }
- (void)closeTapped {
    [self removeFromSuperview];
    if (self.onClose) self.onClose();
}
@end

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------
@interface CTMenuViewController : UIViewController
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) BOOL panelOpen;
@property (nonatomic, assign) NSInteger tab;
@property (nonatomic, assign) CGPoint buttonCenter;
@property (nonatomic, assign) CGSize lastSize;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *collapseBtn;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) NSArray<UIButton *> *presetButtons;
@property (nonatomic, strong) NSTimer *acTimer;
- (void)updateStatus;
- (void)rebuildRows;
- (void)buildAutoClickRows;
- (void)acRefreshStatus;
- (void)startACTimerIfNeeded;
- (void)acTick;
- (CGFloat)acDelayRowAt:(CGFloat)y title:(NSString *)title kind:(NSInteger)kind
                  value:(double)value min:(double)minV max:(double)maxV;
- (void)acSyncDelayRow:(NSInteger)kind;
- (void)layoutPanelContent;
- (void)layoutTick;
- (NSString *)resolvedText;
- (void)showOverlay:(NSString *)text;
@end

@implementation CTMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    CTPassThroughView *root = [[CTPassThroughView alloc] initWithFrame:self.view.bounds];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.backgroundColor = [UIColor clearColor];
    self.view = root;

    [self buildButton];
    [self buildPanel];
    root.interactiveView = self.button;
    __weak CTMenuViewController *weakSelf = self;
    root.onLayout = ^{ [weakSelf layoutTick]; };
    [self updateStatus];
}

// Gọi từ layoutSubviews của root view: bắt chắc chắn mọi lần đổi kích thước/xoay.
- (void)layoutTick {
    CGSize sz = self.view.bounds.size;
    if (sz.width < 100 || sz.height < 100) return;
    if (!CGSizeEqualToSize(sz, self.lastSize)) {
        self.lastSize = sz;
        [self restoreButtonPosition];
        [self layoutPanel];
        if (self.panelOpen) [self rebuildRows];
        CTLog(@"ui: layout %.0fx%.0f", sz.width, sz.height);
    }
    [self clampButton];
}

// ---- nút nổi ----
- (void)buildButton {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, kBtnSize, kBtnSize);
    b.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
    b.layer.cornerRadius = kBtnSize / 2.0;
    b.layer.borderWidth = 1.5;
    b.layer.borderColor = [UIColor colorWithRed:0.95 green:0.55 blue:0.65 alpha:0.9].CGColor;
    b.layer.shadowColor = [UIColor blackColor].CGColor;
    b.layer.shadowOpacity = 0.5;
    b.layer.shadowRadius = 4;
    [b setTitle:@"CT" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    [b addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [b addGestureRecognizer:pan];

    [self.view addSubview:b];
    self.button = b;
}

- (void)dragButton:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.view];
    CGPoint c = CGPointMake(self.button.center.x + t.x, self.button.center.y + t.y);
    self.button.center = c;
    [g setTranslation:CGPointZero inView:self.view];

    if (g.state == UIGestureRecognizerStateEnded) {
        [self snapButton];
    }
}

- (void)snapButton {
    CGSize s = self.view.bounds.size;
    CGFloat margin = 12;
    CGFloat x = self.button.center.x < s.width / 2 ? margin + kBtnSize / 2 : s.width - margin - kBtnSize / 2;
    CGFloat y = self.button.center.y;
    y = MAX(margin + kBtnSize / 2, MIN(s.height - margin - kBtnSize / 2, y));
    [UIView animateWithDuration:0.2 animations:^{
        self.button.center = CGPointMake(x, y);
    }];
    [[NSUserDefaults standardUserDefaults] setDouble:x / MAX(1, s.width) forKey:@"ct_btn_xp"];
    [[NSUserDefaults standardUserDefaults] setDouble:y / MAX(1, s.height) forKey:@"ct_btn_yp"];
    [self layoutPanel];
}

- (void)clampButton {
    if (self.button.superview != self.view) return;
    CGSize s = self.view.bounds.size;
    CGPoint c = self.button.center;
    CGFloat m = 12 + kBtnSize / 2;
    c.x = MAX(m, MIN(s.width - m, c.x));
    c.y = MAX(m, MIN(s.height - m, c.y));
    self.button.center = c;
    [self layoutPanel];
}

- (void)restoreButtonPosition {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    CGSize s = self.view.bounds.size;
    double xp = [d objectForKey:@"ct_btn_xp"] ? [d doubleForKey:@"ct_btn_xp"] : 0.95;
    double yp = [d objectForKey:@"ct_btn_yp"] ? [d doubleForKey:@"ct_btn_yp"] : 0.5;
    self.button.center = CGPointMake(MIN(MAX(xp, 0.05), 0.95) * s.width, MIN(MAX(yp, 0.1), 0.9) * s.height);
}

// ---- panel ----
- (void)buildPanel {
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 470)];
    p.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.96];
    p.layer.cornerRadius = 14;
    p.layer.masksToBounds = YES;
    p.hidden = YES;
    [self.view addSubview:p];
    self.panel = p;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"Cherry Tale Mod";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:15];
    [p addSubview:title];
    self.titleLabel = title;

    UIButton *collapse = [UIButton buttonWithType:UIButtonTypeSystem];
    [collapse setTitle:@"▾" forState:UIControlStateNormal];
    [collapse addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:collapse];
    self.collapseBtn = collapse;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:close];
    self.closeBtn = close;

    NSArray *presets = @[@"An toàn", @"Farm", @"Max"];
    NSMutableArray *btns = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:presets[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        b.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        b.layer.cornerRadius = 7;
        b.tag = 100 + i;
        [b addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [p addSubview:b];
        [btns addObject:b];
    }
    self.presetButtons = btns;

    self.seg = [[UISegmentedControl alloc] initWithItems:@[@"Chiến đấu", @"Gallery", @"QoL", @"AutoClick", @"Debug"]];
    self.seg.selectedSegmentIndex = 0;
    [self.seg addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    [p addSubview:self.seg];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    self.statusLabel.font = [UIFont systemFontOfSize:10];
    [p addSubview:self.statusLabel];

    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scroll.alwaysBounceVertical = YES;
    [p addSubview:self.scroll];

    [self layoutPanelContent];
}

- (void)layoutPanelContent {
    CGFloat w = self.panel.bounds.size.width;
    CGFloat h = self.panel.bounds.size.height;
    if (w < 100 || h < 100) return;
    self.titleLabel.frame = CGRectMake(14, 8, w - 90, 24);
    self.collapseBtn.frame = CGRectMake(w - 76, 6, 32, 28);
    self.closeBtn.frame = CGRectMake(w - 40, 6, 32, 28);

    CGFloat pw = (w - 28 - 16) / 3.0;
    for (int i = 0; i < (int)self.presetButtons.count; i++) {
        self.presetButtons[i].frame = CGRectMake(14 + i * (pw + 8), 36, pw, 30);
    }
    self.seg.frame = CGRectMake(14, 74, w - 28, 30);
    self.statusLabel.frame = CGRectMake(14, 110, w - 28, 16);
    self.scroll.frame = CGRectMake(0, 130, w, h - 134);
}

- (void)layoutPanel {
    CGSize s = self.view.bounds.size;
    if (s.width < 100 || s.height < 100) return;
    CGFloat w = MIN(330, s.width - 24);
    CGFloat h = MIN(470, s.height - 24);
    CGFloat x = self.button.center.x < s.width / 2 ? s.width - w - 10 : 10;
    self.panel.frame = CGRectMake(x, (s.height - h) / 2, w, h);
    [self layoutPanelContent];
}

- (void)togglePanel {
    self.panelOpen = !self.panelOpen;
    self.panel.hidden = !self.panelOpen;
    CTPassThroughView *root = (CTPassThroughView *)self.view;
    root.interactiveView = self.panelOpen ? self.panel : self.button;
    root.secondaryView = self.panelOpen ? self.button : nil;
    if (self.panelOpen) {
        [self layoutPanel];
        [self rebuildRows];
        [self.view bringSubviewToFront:self.panel];
        [self.view bringSubviewToFront:self.button]; // luôn bấm lại được để đóng
    }
    [self startACTimerIfNeeded];
}

- (void)closePanel {
    if (self.panelOpen) [self togglePanel];
}

- (void)tabChanged {
    self.tab = self.seg.selectedSegmentIndex;
    [self rebuildRows];
    [self startACTimerIfNeeded];
}

- (void)presetTapped:(UIButton *)b {
    CTApplyPreset(b.tag - 100);
    [self rebuildRows];
    [self flash:@"Đã áp dụng preset"];
}

- (void)flash:(NSString *)msg {
    self.statusLabel.text = msg;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateStatus];
    });
}

- (void)updateStatus {
    NSString *phase = phaseLabel();
    if (!CTIL2CPPReady()) {
        self.statusLabel.text = [NSString stringWithFormat:@"%@ · il2cpp: đang chờ…", phase];
        return;
    }
    self.statusLabel.text = [NSString stringWithFormat:@"%@ · il2cpp: OK", phase];
}

// ---- rows ----
- (void)rebuildRows {
    for (UIView *v in self.scroll.subviews) [v removeFromSuperview];

    static NSArray *tabs = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tabs = @[@"Chiến đấu", @"Gallery", @"QoL", @"AutoClick", @"Debug"]; });
    NSString *tabName = tabs[self.tab];

    if ([tabName isEqualToString:@"AutoClick"]) {
        [self buildAutoClickRows];
        return;
    }

    size_t n = 0;
    const CTFeatureDef *fs = ct_features(&n);

    CGFloat w = self.scroll.bounds.size.width;
    CGFloat y = 6;

    for (size_t i = 0; i < n; i++) {
        NSString *tab = @(fs[i].tab);
        if (![tab isEqualToString:tabName]) continue;

        BOOL avail = CTFeatureAvailable(i);
        CGFloat rowH = (fs[i].control == CTControlSlider) ? 76 : 56;
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, y, w - 16, rowH - 6)];
        row.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        row.layer.cornerRadius = 8;
        row.alpha = avail ? 1.0 : 0.45;

        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, row.frame.size.width - 110, 20)];
        lab.text = @(fs[i].title);
        lab.textColor = [UIColor whiteColor];
        lab.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [row addSubview:lab];

        // nhãn rủi ro
        NSString *riskText = fs[i].risk == CTRiskHigh ? @"CAO" : (fs[i].risk == CTRiskMedium ? @"vừa" : @"an toàn");
        UIColor *riskColor = fs[i].risk == CTRiskHigh ? [UIColor systemRedColor]
                            : (fs[i].risk == CTRiskMedium ? [UIColor systemOrangeColor] : [UIColor systemGreenColor]);
        UILabel *risk = [[UILabel alloc] initWithFrame:CGRectMake(row.frame.size.width - 60, 7, 52, 14)];
        risk.text = riskText;
        risk.textColor = riskColor;
        risk.font = [UIFont systemFontOfSize:9];
        risk.textAlignment = NSTextAlignmentRight;
        [row addSubview:risk];

        if (!avail) {
            UILabel *why = [[UILabel alloc] initWithFrame:CGRectMake(10, 28, row.frame.size.width - 20, 16)];
            why.text = @(CTFeatureReason(i));
            why.textColor = [UIColor systemYellowColor];
            why.font = [UIFont systemFontOfSize:9];
            why.numberOfLines = 1;
            [row addSubview:why];
        } else if (fs[i].control == CTControlSwitch) {
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(row.frame.size.width - 62, 12, 51, 31)];
            sw.transform = CGAffineTransformMakeScale(0.8, 0.8);
            sw.on = CTHooksGetFlag(@(fs[i].fid));
            sw.tag = (NSInteger)i;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            [row addSubview:sw];
        } else if (fs[i].control == CTControlSlider) {
            UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(row.frame.size.width - 60, 7, 50, 16)];
            val.textColor = [UIColor colorWithWhite:0.8 alpha:1];
            val.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
            val.textAlignment = NSTextAlignmentRight;
            val.tag = 500 + (NSInteger)i;
            val.text = [NSString stringWithFormat:@"%.2f", CTHooksGetNumber(@(fs[i].fid))];
            [row addSubview:val];

            UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(10, 34, row.frame.size.width - 20, 30)];
            sl.minimumValue = (float)fs[i].minValue;
            sl.maximumValue = (float)fs[i].maxValue;
            sl.value = (float)CTHooksGetNumber(@(fs[i].fid));
            sl.tag = (NSInteger)i;
            [sl addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [row addSubview:sl];
        } else {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
            btn.frame = CGRectMake(row.frame.size.width - 96, 12, 88, 30);
            [btn setTitle:@"Chạy" forState:UIControlStateNormal];
            btn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
            btn.layer.cornerRadius = 7;
            btn.titleLabel.font = [UIFont systemFontOfSize:12];
            btn.tag = (NSInteger)i;
            [btn addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
            [row addSubview:btn];
        }

        [self.scroll addSubview:row];
        y += rowH;
    }

    self.scroll.contentSize = CGSizeMake(w, y + 8);
}

- (void)buildAutoClickRows {
    CGFloat w = self.scroll.bounds.size.width;
    CGFloat y = 6;

    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(12, y, w - 24, 20)];
    status.tag = 900;
    status.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    status.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    [self.scroll addSubview:status];
    y += 26;

    CGFloat bw = (w - 16 - 16) / 3.0;
    NSArray *titles = @[@"● Ghi", @"▶ Phát", @"Xoá hết"];
    NSArray *sels = @[@"acRecordTapped:", @"acPlayTapped:", @"acClearTapped:"];
    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(8 + i * (bw + 8), y, bw, 34);
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        b.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        b.layer.cornerRadius = 8;
        b.tag = 901 + i;
        [b addTarget:self action:NSSelectorFromString(sels[i]) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:b];
    }
    y += 42;

    UIView *ovRow = [[UIView alloc] initWithFrame:CGRectMake(8, y, w - 16, 34)];
    ovRow.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    ovRow.layer.cornerRadius = 8;
    UILabel *ovLab = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, ovRow.frame.size.width - 80, 22)];
    ovLab.text = @"Hiện chấm số trên màn hình";
    ovLab.textColor = [UIColor whiteColor];
    ovLab.font = [UIFont systemFontOfSize:12];
    [ovRow addSubview:ovLab];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(ovRow.frame.size.width - 62, 2, 51, 31)];
    sw.transform = CGAffineTransformMakeScale(0.8, 0.8);
    sw.on = CTConfigGetBool(@"ac_overlay", YES);
    [sw addTarget:self action:@selector(acOverlayChanged:) forControlEvents:UIControlEventValueChanged];
    [ovRow addSubview:sw];
    [self.scroll addSubview:ovRow];
    y += 40;

    y = [self acDelayRowAt:y title:@"Cách nhau giữa các click" kind:0 value:CTAutoClickStepDelay() min:0.05 max:5.0];
    y = [self acDelayRowAt:y title:@"Nghỉ giữa 2 vòng" kind:1 value:CTAutoClickLoopDelay() min:0.05 max:30.0];

    UILabel *listTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, y, w - 24, 18)];
    listTitle.text = @"Thứ tự thao tác";
    listTitle.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    listTitle.font = [UIFont systemFontOfSize:10];
    [self.scroll addSubview:listTitle];
    y += 20;

    NSInteger n = CTAutoClickStepCount();
    if (n == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(12, y, w - 24, 40)];
        empty.text = @"Chưa có bước nào.\nBật \"Ghi\" rồi bấm các nút trong game.";
        empty.numberOfLines = 2;
        empty.textColor = [UIColor colorWithWhite:0.55 alpha:1];
        empty.font = [UIFont systemFontOfSize:11];
        [self.scroll addSubview:empty];
        y += 44;
    }
    for (NSInteger i = 0; i < n; i++) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, y, w - 16, 32)];
        row.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        row.layer.cornerRadius = 7;
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, row.frame.size.width - 56, 24)];
        lab.text = CTAutoClickStepLabel(i);
        lab.textColor = [UIColor whiteColor];
        lab.font = [UIFont systemFontOfSize:11];
        lab.lineBreakMode = NSLineBreakByTruncatingTail;
        [row addSubview:lab];
        UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
        del.frame = CGRectMake(row.frame.size.width - 46, 1, 40, 30);
        [del setTitle:@"✕" forState:UIControlStateNormal];
        [del setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        del.tag = i;
        [del addTarget:self action:@selector(acDeleteTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:del];
        [self.scroll addSubview:row];
        y += 36;
    }

    self.scroll.contentSize = CGSizeMake(w, y + 8);
    [self acRefreshStatus];
}

// kind: 0 = cách nhau giữa các click, 1 = nghỉ giữa 2 vòng.
- (CGFloat)acDelayRowAt:(CGFloat)y title:(NSString *)title kind:(NSInteger)kind
                  value:(double)value min:(double)minV max:(double)maxV {
    CGFloat w = self.scroll.bounds.size.width;
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, y, w - 16, 76)];
    row.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    row.layer.cornerRadius = 8;
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, row.frame.size.width - 70, 18)];
    lab.text = title;
    lab.textColor = [UIColor whiteColor];
    lab.font = [UIFont systemFontOfSize:12];
    [row addSubview:lab];
    UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(row.frame.size.width - 66, 4, 56, 18)];
    val.tag = 910 + kind;
    val.textAlignment = NSTextAlignmentRight;
    val.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    val.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    val.text = [NSString stringWithFormat:@"%.2fs", value];
    [row addSubview:val];

    UIButton *minus = [UIButton buttonWithType:UIButtonTypeSystem];
    minus.frame = CGRectMake(8, 28, 34, 36);
    [minus setTitle:@"−" forState:UIControlStateNormal];
    minus.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    minus.tag = 930 + kind;
    [minus addTarget:self action:@selector(acStepNudge:) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:minus];

    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(48, 32, row.frame.size.width - 96, 28)];
    sl.minimumValue = (float)minV;
    sl.maximumValue = (float)maxV;
    sl.value = (float)value;
    sl.tag = 920 + kind;
    [sl addTarget:self action:@selector(acSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sl];

    UIButton *plus = [UIButton buttonWithType:UIButtonTypeSystem];
    plus.frame = CGRectMake(row.frame.size.width - 42, 28, 34, 36);
    [plus setTitle:@"+" forState:UIControlStateNormal];
    plus.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    plus.tag = 940 + kind;
    [plus addTarget:self action:@selector(acStepNudge:) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:plus];

    [self.scroll addSubview:row];
    return y + 82;
}

- (void)acSyncDelayRow:(NSInteger)kind {
    double v = kind == 0 ? CTAutoClickStepDelay() : CTAutoClickLoopDelay();
    UILabel *val = (UILabel *)[self.scroll viewWithTag:910 + kind];
    val.text = [NSString stringWithFormat:@"%.2fs", v];
    UISlider *sl = (UISlider *)[self.scroll viewWithTag:920 + kind];
    if (sl && fabs(sl.value - v) > 0.0001) sl.value = (float)v;
}

- (void)acStepNudge:(UIButton *)b {
    BOOL plus = b.tag >= 940;
    NSInteger kind = plus ? b.tag - 940 : b.tag - 930;
    double v = (kind == 0 ? CTAutoClickStepDelay() : CTAutoClickLoopDelay()) + (plus ? 0.05 : -0.05);
    v = round(v / 0.05) * 0.05;
    if (kind == 0) CTAutoClickSetStepDelay(v);
    else CTAutoClickSetLoopDelay(v);
    [self acSyncDelayRow:kind];
}

- (void)acRefreshStatus {
    UILabel *status = (UILabel *)[self.scroll viewWithTag:900];
    if (status) {
        if (CTAutoClickIsRecording() && !CTAutoClickRecordAvailable())
            status.text = @"Không ghi được: hook click chưa cài (bản _safe?)";
        else
            status.text = CTAutoClickStatus();
    }
    UIButton *rec = (UIButton *)[self.scroll viewWithTag:901];
    UIButton *play = (UIButton *)[self.scroll viewWithTag:902];
    if (rec) {
        [rec setTitle:(CTAutoClickIsRecording() ? @"■ Dừng ghi" : @"● Ghi") forState:UIControlStateNormal];
        rec.backgroundColor = CTAutoClickIsRecording() ? [UIColor systemRedColor] : [UIColor colorWithWhite:0.2 alpha:1];
    }
    if (play) {
        [play setTitle:(CTAutoClickIsPlaying() ? @"■ Dừng" : @"▶ Phát") forState:UIControlStateNormal];
        play.backgroundColor = CTAutoClickIsPlaying() ? [UIColor systemGreenColor] : [UIColor colorWithWhite:0.2 alpha:1];
    }
}

- (void)startACTimerIfNeeded {
    if (self.tab == 3) {
        if (!self.acTimer) {
            self.acTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self
                                                         selector:@selector(acTick) userInfo:nil repeats:YES];
        }
    } else if (self.acTimer) {
        [self.acTimer invalidate];
        self.acTimer = nil;
    }
}

- (void)acTick {
    if (self.tab != 3 || !self.panelOpen) { [self startACTimerIfNeeded]; return; }
    [self acRefreshStatus];
    // số bước có thể tăng khi đang ghi -> dựng lại danh sách
    static NSInteger lastCount = -1;
    NSInteger n = CTAutoClickStepCount();
    if (n != lastCount) { lastCount = n; [self rebuildRows]; }
}

- (void)acRecordTapped:(UIButton *)b {
    (void)b;
    if (!CTAutoClickIsRecording() && !CTAutoClickRecordAvailable()) {
        [self flash:@"Hook click chưa cài — dùng bản thường, không phải _safe"];
        return;
    }
    CTAutoClickToggleRecording();
    [self acRefreshStatus];
    [self flash:CTAutoClickIsRecording() ? @"Đang ghi — bấm nút trong game" : @"Đã dừng ghi"];
}

- (void)acPlayTapped:(UIButton *)b {
    (void)b;
    if (!CTAutoClickIsPlaying() && CTAutoClickStepCount() == 0) {
        [self flash:@"Chưa có bước nào"];
        return;
    }
    CTAutoClickTogglePlaying();
    [self acRefreshStatus];
    [self flash:CTAutoClickIsPlaying() ? @"Đang phát lặp" : @"Đã dừng"];
}

- (void)acClearTapped:(UIButton *)b {
    (void)b;
    static BOOL armed = NO;
    static NSTimeInterval armedAt = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!armed || now - armedAt > 3.0) {
        armed = YES;
        armedAt = now;
        [self flash:@"Ấn lại lần nữa để xoá hết"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ armed = NO; });
        return;
    }
    armed = NO;
    CTAutoClickSetPlaying(NO);
    CTAutoClickClearSteps();
    [self rebuildRows];
    [self flash:@"Đã xoá hết bước"];
}

- (void)acDeleteTapped:(UIButton *)b {
    CTAutoClickDeleteStep(b.tag);
    [self rebuildRows];
}

- (void)acOverlayChanged:(UISwitch *)sw {
    CTAutoClickSetOverlayVisible(sw.on);
}

- (void)acSliderChanged:(UISlider *)sl {
    NSInteger kind = sl.tag - 920;
    double v = round(sl.value / 0.05) * 0.05;
    if (kind == 0) CTAutoClickSetStepDelay(v);
    else CTAutoClickSetLoopDelay(v);
    [self acSyncDelayRow:kind];
}

- (void)switchChanged:(UISwitch *)sw {
    size_t n = 0;
    const CTFeatureDef *fs = ct_features(&n);
    size_t i = (size_t)sw.tag;
    if (i >= n) return;
    NSString *fid = @(fs[i].fid);
    if ([fid isEqualToString:@"debug_log"]) {
        CTHooksSetFlag(fid, sw.on);
        if (sw.on) [self showOverlay:CTLogText()];
        return;
    }
    CTHooksSetFlag(fid, sw.on);
    CTHooksSaveConfig();
}

- (void)sliderChanged:(UISlider *)sl {
    size_t n = 0;
    const CTFeatureDef *fs = ct_features(&n);
    size_t i = (size_t)sl.tag;
    if (i >= n) return;
    NSString *fid = @(fs[i].fid);
    // làm tròn theo bước
    double step = fs[i].step > 0 ? fs[i].step : 1;
    double v = round(sl.value / step) * step;
    CTHooksSetNumber(fid, v);
    UILabel *val = [self.scroll viewWithTag:500 + (NSInteger)i];
    val.text = [NSString stringWithFormat:@"%.2f", v];
    if ([fid isEqualToString:@"battle_speed"]) CTApplyBattleSpeed(v);
}

- (void)actionTapped:(UIButton *)btn {
    size_t n = 0;
    const CTFeatureDef *fs = ct_features(&n);
    size_t i = (size_t)btn.tag;
    if (i >= n) return;
    NSString *fid = @(fs[i].fid);

    if ([fid isEqualToString:@"debug_resolved"]) {
        NSString *txt = [self resolvedText];
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [txt writeToFile:[docs stringByAppendingPathComponent:@"cherrytale_hookcount.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [self showOverlay:txt];
    } else if ([fid isEqualToString:@"debug_buttons"]) {
        [self showOverlay:CTAutoDumpButtons()];
    } else if ([fid isEqualToString:@"debug_export"]) {
        [self exportDump];
    } else if ([fid isEqualToString:@"emergency_off"]) {
        static BOOL armed = NO;
        static NSTimeInterval armedAt = 0;
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!armed || now - armedAt > 3.0) {
            armed = YES;
            armedAt = now;
            [self flash:@"Ấn lại lần nữa để TẮT TOÀN BỘ"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ armed = NO; });
            return;
        }
        armed = NO;
        CTEmergencySet(YES);
        CTHooksSaveConfig();
        [self flash:@"Đã TẮT TOÀN BỘ hook"];
        [self rebuildRows];
    }
}

- (NSString *)resolvedText {
    NSMutableString *s = [NSMutableString stringWithString:@"== Hook đã cài ==\n"];
    NSString *log = CTLogText();
    for (NSString *line in [log componentsSeparatedByString:@"\n"]) {
        if ([line containsString:@"hook OK"] || [line containsString:@"hook:"])
            [s appendFormat:@"%@\n", line];
    }
    [s appendString:@"\n== Trạng thái tính năng ==\n"];
    size_t n = 0;
    const CTFeatureDef *fs = ct_features(&n);
    for (size_t i = 0; i < n; i++) {
        [s appendFormat:@"%@ %@%@\n", CTFeatureAvailable(i) ? @"[OK] " : @"[--] ",
         @(fs[i].title), CTFeatureAvailable(i) ? @"" : [NSString stringWithFormat:@" — %@", @(CTFeatureReason(i))]];
    }
    [s appendString:@"\n== Số lần hook được gọi ==\n"];
    for (size_t i = 0; i < CTHookTargetCount(); i++)
        [s appendFormat:@"%-14s %llu\n", CTHookTargetKey(i), (unsigned long long)CTHookTargetHits(i)];
    return s;
}

- (void)exportDump {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *out = [docs stringByAppendingPathComponent:@"cherrytale_dump.cs"];
    NSString *gz = [[NSBundle mainBundle] pathForResource:@"dump" ofType:@"cs.gz"];
    if (gz) {
        FILE *in = fopen(gz.fileSystemRepresentation, "rb");
        FILE *of = fopen(out.fileSystemRepresentation, "wb");
        if (in && of) {
            // giải nén gzip bằng zlib
            gzFile g = gzdopen(dup(fileno(in)), "rb");
            char buf[65536];
            int r;
            while (g && (r = gzread(g, buf, sizeof(buf))) > 0) fwrite(buf, 1, (size_t)r, of);
            if (g) gzclose(g);
            fclose(in);
            fclose(of);
            [self showOverlay:[NSString stringWithFormat:@"Đã xuất dump.cs →\n%@", out]];
            return;
        }
        if (in) fclose(in);
        if (of) fclose(of);
    }
    NSString *fallback = [docs stringByAppendingPathComponent:@"cherrytale_dump.txt"];
    [[self resolvedText] writeToFile:fallback atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self showOverlay:[NSString stringWithFormat:@"Không có dump.cs.gz trong bundle.\nĐã ghi danh sách resolve →\n%@", fallback]];
}

- (void)showOverlay:(NSString *)text {
    for (UIView *v in self.view.subviews) if ([v isKindOfClass:[CTOverlayView class]]) [v removeFromSuperview];
    CGSize s = self.view.bounds.size;
    CTOverlayView *o = [[CTOverlayView alloc] initWithFrame:CGRectMake(10, 10, s.width - 20, s.height - 20)];
    [o setText:text];
    __weak CTMenuViewController *weakSelf = self;
    o.onClose = ^{
        CTPassThroughView *root = (CTPassThroughView *)weakSelf.view;
        root.interactiveView = weakSelf.panelOpen ? weakSelf.panel : weakSelf.button;
        root.secondaryView = weakSelf.panelOpen ? weakSelf.button : nil;
    };
    [self.view addSubview:o];
    [self.view bringSubviewToFront:o];
    ((CTPassThroughView *)self.view).interactiveView = o;
}

@end

// ---------------------------------------------------------------------------
// Khởi động: gắn menu vào CHÍNH window của app (không tạo UIWindow riêng).
// Window riêng ở level cao từng làm Unity không nhận được chạm -> game "đơ".
// Gắn làm subview của window: chạm ngoài nút do CTPassThroughView trả NO nên
// rơi xuống view Unity phía dưới trong cùng window.
// ---------------------------------------------------------------------------
static UIView *g_overlayView = nil;

static UIWindow *appWindow(void) {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)s;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) return w;
        }
        if (ws.windows.count) return ws.windows.firstObject;
    }
    return [UIApplication sharedApplication].keyWindow;
}

static void startUITry(int attempt) {
    if (g_overlayView) { CTUIRefresh(); return; }
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ startUITry(attempt); });
        return;
    }
    UIWindow *w = appWindow();
    if (!w || w.bounds.size.width < 100) {
        if (attempt < 240) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ startUITry(attempt + 1); });
        } else {
            CTLog(@"ui: không tìm thấy window của app");
        }
        return;
    }

    CTMenuViewController *vc = [[CTMenuViewController alloc] initWithNibName:nil bundle:nil];
    vc.view.frame = w.bounds;
    vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [w addSubview:vc.view];
    [w bringSubviewToFront:vc.view];
    g_vc = vc;
    g_overlayView = vc.view;
    CTAutoClickAttachOverlay(vc.view);
    CTLog(@"ui: đã gắn menu vào window %@ (%.0fx%.0f)", w, w.bounds.size.width, w.bounds.size.height);
}

void CTUIStart(void) {
    if (g_started) return;
    g_started = YES;
    if (CT_RECON_PHASE) {
        // Bản recon: chỉ ghi log, không hiện UI để không ảnh hưởng game.
        CTLog(@"ui: bản recon — không hiện menu");
        return;
    }
    // chờ app vào foreground ổn định rồi mới gắn
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ startUITry(0); });
}

void CTUIRefresh(void) {
    if (!g_vc) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        CTMenuViewController *vc = (CTMenuViewController *)g_vc;
        [vc updateStatus];
        if (vc.panelOpen) [vc rebuildRows];
    });
}

void CTUIShowResolvedList(void) {
    if (!g_vc) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        CTMenuViewController *vc = (CTMenuViewController *)g_vc;
        [vc showOverlay:[vc resolvedText]];
    });
}
