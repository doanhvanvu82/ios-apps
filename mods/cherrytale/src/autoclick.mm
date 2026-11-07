// Auto click dạng "macro": người dùng bấm tay các nút trên màn hình game, mỗi
// lần bấm được ghi thành một bước (toạ độ + nhãn nút). Khi phát lại, engine tự
// raycast đúng toạ độ đó rồi gọi OnPointerClick của nút nằm dưới.
//
// Vì sao ghi bằng hook OnPointerClick mà không phải overlay UIKit:
//   - Hook là code C++ chạy ngay trong lời gọi click của game, nên chỉ thấy
//     click THẬT vào nút game. Nút Save/Close của menu mod là UIView riêng,
//     không đi qua đây -> không bao giờ bị ghi nhầm.
//   - Toạ độ lấy từ PointerEventData.position (pixel màn hình, gốc trái-dưới),
//     chuẩn hoá theo Screen.width/height để phát lại đúng cả khi đổi độ phân
//     giải / xoay máy.
//
// Mọi hàm trong file này PHẢI chạy trên main thread (il2cpp + Unity UI).
#import "common.h"

#include <string.h>
#include <math.h>
#include <mach/mach_time.h>

// ---------------------------------------------------------------------------
// Trạng thái
// ---------------------------------------------------------------------------
typedef struct {
    double nx, ny;        // toạ độ chuẩn hoá 0..1 (gốc trái-dưới)
    char name[64];        // tên GameObject
    char label[96];       // nhãn hiển thị
} CTStep;

#define CT_MAX_STEPS 200

static CTStep g_steps[CT_MAX_STEPS];
static int g_stepCount = 0;
static volatile BOOL g_recording = NO;
static volatile BOOL g_playing = NO;
static volatile int g_injecting = 0;   // >0 khi engine đang tự gọi OnPointerClick
static double g_stepDelay = 0.35;      // giây giữa 2 lần click
static double g_loopDelay = 1.20;      // giây nghỉ giữa 2 vòng
static NSInteger g_playIndex = -1;
static NSInteger g_loopCount = 0;
static uint64_t g_lastRecordNs = 0;

static NSString *kStoreSteps = @"ac_steps";
static NSString *kStoreStepDelay = @"ac_step_delay";
static NSString *kStoreLoopDelay = @"ac_loop_delay";
static NSString *kStoreOverlay = @"ac_overlay";

static void ac_refresh_dots(void);

// ---------------------------------------------------------------------------
// Unity API resolve (lười, trên main thread)
// ---------------------------------------------------------------------------
static BOOL g_apiReady = NO;
static void *clsGameObject = NULL, *clsComponent = NULL, *clsObject = NULL;
static void *clsEventSystem = NULL, *clsPointerEventData = NULL;
static void *clsGraphic = NULL, *clsCanvasRenderer = NULL;
static void *clsButton = NULL, *clsBtnClick = NULL;
static void *clsScreen = NULL, *clsTMP = NULL, *clsText = NULL;
static void *typeEventSystem = NULL, *typePointerEventData = NULL;
static void *typeGraphic = NULL, *typeBtnClick = NULL, *typeButton = NULL;
static void *typeTMP = NULL, *typeText = NULL;
static void *mFind, *mGetName, *mGoGetCompChild, *mGoGetCompParent, *mGetActiveInHier;
static void *mGetCurrent, *mGetScreenW, *mGetScreenH;
static void *mGetCanvasRenderer, *mGetCull, *mGoFromComp;
static void *mRaycastAll = NULL;
static size_t offPosition = 0, offClickCount = 0;

static void ac_api_setup(void) {
    if (g_apiReady) return;
    if (!CTIL2CPPReady()) return;

    clsGameObject        = CTFindClassNS("UnityEngine", "GameObject");
    clsComponent         = CTFindClassNS("UnityEngine", "Component");
    clsObject            = CTFindClassNS("UnityEngine", "Object");
    clsEventSystem       = CTFindClassNS("UnityEngine.EventSystems", "EventSystem");
    clsPointerEventData  = CTFindClassNS("UnityEngine.EventSystems", "PointerEventData");
    clsGraphic           = CTFindClassNS("UnityEngine.UI", "Graphic");
    clsCanvasRenderer    = CTFindClassNS("UnityEngine", "CanvasRenderer");
    clsButton            = CTFindClassNS("UnityEngine.UI", "Button");
    clsBtnClick          = CTFindClass("BtnClickEvent");
    clsScreen            = CTFindClassNS("UnityEngine", "Screen");
    clsTMP               = CTFindClassNS("TMPro", "TMP_Text");
    clsText              = CTFindClassNS("UnityEngine.UI", "Text");

    typeEventSystem      = clsEventSystem ? CTTypeObject(clsEventSystem) : NULL;
    typePointerEventData = clsPointerEventData ? CTTypeObject(clsPointerEventData) : NULL;
    typeGraphic          = clsGraphic ? CTTypeObject(clsGraphic) : NULL;
    typeBtnClick         = clsBtnClick ? CTTypeObject(clsBtnClick) : NULL;
    typeButton           = clsButton ? CTTypeObject(clsButton) : NULL;
    typeTMP              = clsTMP ? CTTypeObject(clsTMP) : NULL;
    typeText             = clsText ? CTTypeObject(clsText) : NULL;

    if (clsObject) {
        mFind    = CTFindMethod(clsObject, "FindObjectsOfType", 1);
        mGetName = CTFindMethod(clsObject, "get_name", 0);
    }
    if (clsComponent) mGoFromComp = CTFindMethod(clsComponent, "get_gameObject", 0);
    if (clsGameObject) {
        mGoGetCompChild  = CTFindMethod(clsGameObject, "GetComponentInChildren", 2);
        mGoGetCompParent = CTFindMethod(clsGameObject, "GetComponentInParent", 2);
        mGetActiveInHier = CTFindMethod(clsGameObject, "get_activeInHierarchy", 0);
    }
    if (clsEventSystem) {
        mGetCurrent = CTFindMethod(clsEventSystem, "get_current", 0);
        mRaycastAll = CTFindMethod(clsEventSystem, "RaycastAll", 2);
    }

    if (clsPointerEventData) {
        if (!CTFindFieldOffset(clsPointerEventData, "<position>k__BackingField", &offPosition))
            offPosition = 0x100; // arm64 theo dump
        if (!CTFindFieldOffset(clsPointerEventData, "<clickCount>k__BackingField", &offClickCount))
            offClickCount = 0x134;
    }
    if (clsGraphic) mGetCanvasRenderer = CTFindMethod(clsGraphic, "get_canvasRenderer", 0);
    if (clsCanvasRenderer) mGetCull = CTFindMethod(clsCanvasRenderer, "get_cull", 0);
    if (clsScreen) {
        mGetScreenW = CTFindMethod(clsScreen, "get_width", 0);
        mGetScreenH = CTFindMethod(clsScreen, "get_height", 0);
    }

    g_apiReady = (mGetName && mGetCurrent && mRaycastAll && mGoGetCompParent &&
                  mGetScreenW && mGetScreenH && offPosition &&
                  typeEventSystem && typePointerEventData &&
                  typeBtnClick && typeButton);
    if (!g_apiReady)
        CTLog(@"autoclick: thiếu API Unity (cur=%p ray=%p parent=%p pos=0x%zx btn=%p/%p)",
              (void *)mGetCurrent, (void *)mRaycastAll, (void *)mGoGetCompParent,
              offPosition, (void *)typeBtnClick, (void *)typeButton);
}

static double screen_w(void) {
    if (!mGetScreenW) return 0;
    return ((int (*)(void)) CTMethodPtr(mGetScreenW))();
}
static double screen_h(void) {
    if (!mGetScreenH) return 0;
    return ((int (*)(void)) CTMethodPtr(mGetScreenH))();
}

static NSString *obj_name(void *obj) {
    if (!obj || !mGetName) return nil;
    void *(*fn)(void *) = (void *(*)(void *)) CTMethodPtr(mGetName);
    return CTString(fn(obj));
}

static void *comp_gameobject(void *comp) {
    if (!comp || !mGoFromComp) return NULL;
    return ((void *(*)(void *)) CTMethodPtr(mGoFromComp))(comp);
}

static void *go_get_child(void *go, void *type) {
    if (!go || !type || !mGoGetCompChild) return NULL;
    void *(*fn)(void *, void *, bool) = (void *(*)(void *, void *, bool)) CTMethodPtr(mGoGetCompChild);
    return fn(go, type, true);
}
static void *go_get_parent(void *go, void *type) {
    if (!go || !type || !mGoGetCompParent) return NULL;
    void *(*fn)(void *, void *, bool) = (void *(*)(void *, void *, bool)) CTMethodPtr(mGoGetCompParent);
    return fn(go, type, true);
}

static NSString *text_of(void *comp, void *cls) {
    if (!comp || !cls) return nil;
    void *mt = CTFindMethod(cls, "get_text", 0);
    if (!mt) return nil;
    void *m = CTVirtualMethod(comp, mt);
    return CTString(((void *(*)(void *)) CTMethodPtr(m ? m : mt))(comp));
}

static NSString *go_label(void *go) {
    if (!go) return nil;
    NSString *t = text_of(go_get_child(go, typeTMP), clsTMP);
    if (t.length) return t;
    t = text_of(go_get_child(go, typeText), clsText);
    if (t.length) return t;
    t = text_of(go_get_parent(go, typeTMP), clsTMP);
    if (t.length) return t;
    return text_of(go_get_parent(go, typeText), clsText);
}

// ---------------------------------------------------------------------------
// Lưu / tải các bước
// ---------------------------------------------------------------------------
static void ac_save(void) {
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < g_stepCount; i++) {
        [s appendFormat:@"%.6f\t%.6f\t%s\t%s\n", g_steps[i].nx, g_steps[i].ny,
         g_steps[i].name, g_steps[i].label];
    }
    CTConfigSetString(kStoreSteps, s);
    CTConfigSetNumber(kStoreStepDelay, g_stepDelay);
    CTConfigSetNumber(kStoreLoopDelay, g_loopDelay);
    CTConfigFlush();
}

// Nạp lười: constructor dylib chạy khi container NSUserDefaults chưa sẵn nên
// đọc ở đó dễ hụt và rơi về mặc định. Chỉ nạp một lần khi menu thật sự dùng.
static BOOL g_loaded = NO;

static void ac_load_once(void) {
    if (g_loaded) return;
    g_loaded = YES;
    CTAutoClickLoad();
    ac_refresh_dots();
}

void CTAutoClickLoad(void) {
    g_loaded = YES;
    g_stepCount = 0;
    NSString *raw = CTConfigGetString(kStoreSteps, @"");
    for (NSString *line in [raw componentsSeparatedByString:@"\n"]) {
        if (line.length == 0) continue;
        NSArray *p = [line componentsSeparatedByString:@"\t"];
        if (p.count < 2) continue;
        if (g_stepCount >= CT_MAX_STEPS) break;
        CTStep *st = &g_steps[g_stepCount];
        memset(st, 0, sizeof(*st));
        st->nx = [p[0] doubleValue];
        st->ny = [p[1] doubleValue];
        if (p.count > 2) snprintf(st->name, sizeof(st->name), "%s", [p[2] UTF8String] ?: "");
        if (p.count > 3) snprintf(st->label, sizeof(st->label), "%s", [p[3] UTF8String] ?: "");
        g_stepCount++;
    }
    double sd = CTConfigGetNumber(kStoreStepDelay, 0.35);
    double ld = CTConfigGetNumber(kStoreLoopDelay, 1.20);
    if (sd >= 0.05 && sd <= 5.0) g_stepDelay = sd;
    if (ld >= 0.05 && ld <= 30.0) g_loopDelay = ld;
    CTLog(@"autoclick: tải %d bước", g_stepCount);
}

// ---------------------------------------------------------------------------
// Ghi bước — gọi từ hook OnPointerClick
// ---------------------------------------------------------------------------
static void ac_add_step(double nx, double ny, NSString *name, NSString *label) {
    ac_load_once();
    if (g_stepCount >= CT_MAX_STEPS) return;

    // Chống ghi trùng khi game gọi OnPointerClick 2 lần cho cùng một chạm
    // (cùng toạ độ trong 150 ms -> bỏ).
    uint64_t now = mach_absolute_time();
    static mach_timebase_info_data_t tb = {0, 0};
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t ns = now * tb.numer / tb.denom;
    if (g_stepCount > 0) {
        CTStep *prev = &g_steps[g_stepCount - 1];
        if (fabs(prev->nx - nx) < 0.004 && fabs(prev->ny - ny) < 0.004 &&
            ns - g_lastRecordNs < 150000000ULL) {
            return;
        }
    }
    g_lastRecordNs = ns;

    CTStep *st = &g_steps[g_stepCount++];
    memset(st, 0, sizeof(*st));
    st->nx = nx;
    st->ny = ny;
    snprintf(st->name, sizeof(st->name), "%s", name.UTF8String ?: "");
    snprintf(st->label, sizeof(st->label), "%s", label.UTF8String ?: "");
    ac_save();
    ac_refresh_dots();
}

// Hook chạy TRƯỚC handler gốc (xem hooks.mm): đọc tên/nhãn ở đây vì handler
// có thể SetActive(false)/Destroy object — đọc sau sẽ ra tên rỗng.
void CTAutoClickObserveClick(void *self, void *eventData) {
    if (g_playing || g_injecting > 0) return;
    if (!self || !eventData) return;
    ac_load_once();
    if (!g_recording) return;

    ac_api_setup();
    if (!offPosition) return;

    double sw = screen_w(), sh = screen_h();
    if (sw < 1 || sh < 1) return;
    const float *pos = (const float *)((const char *)eventData + offPosition);
    double nx = pos[0] / sw, ny = pos[1] / sh;
    if (nx < 0 || nx > 1 || ny < 0 || ny > 1) return;

    NSString *name = obj_name(self);
    NSString *label = go_label(comp_gameobject(self));
    ac_add_step(nx, ny, name ?: @"?", label ?: @"");
    CTLog(@"autoclick: ghi bước %d %@ (%.0f%%,%.0f%%)", g_stepCount, name ?: @"?",
          nx * 100, ny * 100);
}

// ---------------------------------------------------------------------------
// Phát lại
// ---------------------------------------------------------------------------
static void ac_play_tick(void);

@interface CTAutoClickTimer : NSObject
+ (CTAutoClickTimer *)shared;
- (void)tick;
@end

static CTAutoClickTimer *g_timerTarget = nil;
static NSTimer *g_timer = nil;

@implementation CTAutoClickTimer
+ (CTAutoClickTimer *)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g_timerTarget = [CTAutoClickTimer new]; });
    return g_timerTarget;
}
- (void)tick { ac_play_tick(); }
@end

static void ac_schedule(NSTimeInterval delay) {
    if (g_timer) [g_timer invalidate];
    g_timer = [NSTimer scheduledTimerWithTimeInterval:delay
                                               target:[CTAutoClickTimer shared]
                                             selector:@selector(tick)
                                             userInfo:nil
                                              repeats:NO];
}

// Lý do trượt gần nhất, để log biết engine dừng ở đâu (chỉ ghi tối đa 2 giây/lần).
static NSString *g_lastFail = nil;
static uint64_t g_lastFailNs = 0;

static BOOL ac_fail(NSString *why) {
    uint64_t now = mach_absolute_time();
    static mach_timebase_info_data_t tb = {0, 0};
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t ns = now * tb.numer / tb.denom;
    if (![why isEqualToString:g_lastFail] || ns - g_lastFailNs > 2000000000ULL) {
        CTLog(@"autoclick: trượt — %@", why);
        g_lastFail = why;
        g_lastFailNs = ns;
    }
    return NO;
}

// Gọi OnPointerClick trên một handler cụ thể. Trả YES nếu không ném exception.
static BOOL ac_invoke_handler(void *go, void *handler, void *method, void *ped, const char *kind) {
    (void)go;
    void *ev[1] = { ped };
    g_injecting++;
    BOOL ok = CTInvokeVirtual(handler, method, ev);
    g_injecting--;
    CTLog(@"autoclick: click %s '%@' -> %@", kind, obj_name(go) ?: @"?", ok ? @"OK" : @"lỗi");
    return ok;
}

// Handler trên CHÍNH GameObject hoặc cha gần nhất — đúng như
// ExecuteEvents.ExecuteHierarchy của EventSystem. Không dùng
// GetComponentInChildren vì nó vớ handler của object anh em.
static void *ac_handler_on_go(void *go, void *type) {
    if (!go || !type || !mGoGetCompParent) return NULL;
    // includeInactive = false: giống ExecuteEvents.GetEventHandler của Unity,
    // bỏ qua handler nằm trên GameObject đang tắt.
    return ((void *(*)(void *, void *, bool)) CTMethodPtr(mGoGetCompParent))(go, type, false);
}

// Tìm handler theo TOẠ ĐỘ như EventSystem thật vẫn làm: RaycastAll tại điểm
// rồi lấy BtnClickEvent/Button trên chính GO trúng hoặc cha gần nhất. Không
// dùng GetComponentInChildren (vớ handler của object anh em).
static void *ac_find_by_point(void *ped, void **outMethod, const char **outKind) {
    if (outMethod) *outMethod = NULL;
    if (outKind) *outKind = NULL;
    if (!mRaycastAll) return NULL;

    void *(*getcur)(void) = (void *(*)(void)) CTMethodPtr(mGetCurrent);
    void *es = getcur ? getcur() : NULL;
    if (!es) return NULL;

    void *listType = CTMethodParam(mRaycastAll, 1);
    void *listKlass = CTClassFromType(listType);
    if (!listKlass) return NULL;
    void *list = CTObjectNew(listKlass);
    if (!list) return NULL;
    void *ctor = CTFindMethod(listKlass, ".ctor", 0);
    if (ctor && !CTSafeInvokeR(ctor, list, NULL, NULL)) return NULL;

    void *args[2] = { ped, list };
    if (!CTSafeInvokeR(mRaycastAll, es, args, NULL)) return NULL;

    void *mCount = CTFindMethod(listKlass, "get_Count", 0);
    void *mItem  = CTFindMethod(listKlass, "get_Item", 1);
    if (!mCount || !mItem) return NULL;
    int n = ((int (*)(void *)) CTMethodPtr(mCount))(list);
    if (n <= 0) return NULL;

    // EventSystem chỉ dùng kết quả ĐẦU TIÊN rồi cho sự kiện nổi lên cha
    // (ExecuteHierarchy). Làm y hệt để một cú chạm ảo giống chạm thật.
    int idx = 0;
    void *ri[1] = { &idx };
    void *boxed = NULL;
    if (!CTSafeInvokeR(mItem, list, ri, &boxed) || !boxed) return NULL;
    void *rr = CTObjectUnbox(boxed);
    if (!rr) return NULL;
    void *go = *(void **)rr;  // RaycastResult.m_GameObject @ 0x0
    if (!go) return NULL;
    if (mGetActiveInHier && !((bool (*)(void *)) CTMethodPtr(mGetActiveInHier))(go)) return NULL;

    for (int k = 0; k < 2; k++) {
        void *type = k == 0 ? typeBtnClick : typeButton;
        void *cls  = k == 0 ? clsBtnClick : clsButton;
        if (!type || !cls) continue;
        void *handler = ac_handler_on_go(go, type);
        if (!handler) continue;
        void *method = CTFindMethod(cls, "OnPointerClick", 1);
        if (!method) continue;
        if (outMethod) *outMethod = method;
        if (outKind) *outKind = k == 0 ? "BtnClickEvent" : "Button";
        return handler;
    }
    return NULL;
}

// Macro toạ độ: chiếu đúng điểm đã ghi như một ngón tay chạm vào đó, không
// phụ thuộc tên nút — UI đổi bố cục thì điểm cũ trượt, đúng như macro thật.
static BOOL ac_click_at(CTStep *st, double nx, double ny) {
    (void)st;
    ac_api_setup();
    if (!g_apiReady) return ac_fail(@"thiếu API Unity");

    void *(*getcur)(void) = (void *(*)(void)) CTMethodPtr(mGetCurrent);
    void *es = getcur ? getcur() : NULL;
    if (!es) return ac_fail(@"không có EventSystem.current");

    void *ctor = CTFindMethod(clsPointerEventData, ".ctor", 1);
    if (!ctor) return ac_fail(@"không tìm thấy PointerEventData..ctor");
    void *ped = CTObjectNew(clsPointerEventData);
    if (!ped) return ac_fail(@"không tạo được PointerEventData");
    void *a1[1] = { es };
    if (!CTSafeInvokeR(ctor, ped, a1, NULL)) return ac_fail(@"PointerEventData..ctor ném lỗi");

    double sw = screen_w(), sh = screen_h();
    float *pos = (float *)((char *)ped + offPosition);
    pos[0] = (float)(nx * (sw > 1 ? sw : 1));
    pos[1] = (float)(ny * (sh > 1 ? sh : 1));
    *(int *)((char *)ped + offClickCount) = 1;

    // Macro toạ độ: chiếu đúng điểm đã ghi, y như một ngón tay chạm vào đó.
    void *method = NULL;
    const char *kind = NULL;
    void *handler = ac_find_by_point(ped, &method, &kind);
    if (!handler || !method) return ac_fail(@"điểm không có nút bấm được");

    if (!ac_invoke_handler(comp_gameobject(handler), handler, method, ped, kind))
        return ac_fail(@"OnPointerClick ném exception");
    return YES;
}

static void ac_play_tick(void) {
    if (!g_playing) return;
    if (g_stepCount <= 0) { g_playIndex = -1; return; }

    NSInteger idx = g_playIndex < 0 ? 0 : g_playIndex;
    if (idx >= g_stepCount) {
        g_playIndex = -1;
        g_loopCount++;
        ac_refresh_dots();
        ac_schedule(g_loopDelay);
        return;
    }

    CTStep *st = &g_steps[idx];
    BOOL ok = ac_click_at(st, st->nx, st->ny);
    CTLog(@"autoclick: bước %ld/%d %@ %@", (long)(idx + 1), g_stepCount,
          @(st->name), ok ? @"OK" : @"trượt");
    g_playIndex = idx + 1;
    ac_refresh_dots();
    ac_schedule(g_stepDelay);
}

// ---------------------------------------------------------------------------
// API cho menu
// ---------------------------------------------------------------------------
BOOL CTAutoClickIsRecording(void) { return g_recording; }
BOOL CTAutoClickIsPlaying(void) { return g_playing; }

void CTAutoClickSetRecording(BOOL on) {
    if (on && g_playing) CTAutoClickSetPlaying(NO);
    g_recording = on;
    CTLog(@"autoclick: ghi %@", on ? @"BẬT" : @"TẮT");
}

void CTAutoClickSetPlaying(BOOL on) {
    ac_load_once();
    if (on) {
        if (g_stepCount <= 0) return;
        g_recording = NO;
        g_playing = YES;
        g_playIndex = 0;
        g_loopCount = 0;
        ac_schedule(0.05);
        CTLog(@"autoclick: phát %d bước, cách %.2fs, nghỉ vòng %.2fs", g_stepCount, g_stepDelay, g_loopDelay);
    } else {
        g_playing = NO;
        g_playIndex = -1;
        if (g_timer) { [g_timer invalidate]; g_timer = nil; }
        ac_refresh_dots();
        CTLog(@"autoclick: dừng");
    }
}

void CTAutoClickToggleRecording(void) { CTAutoClickSetRecording(!g_recording); }
void CTAutoClickTogglePlaying(void) { CTAutoClickSetPlaying(!g_playing); }

NSInteger CTAutoClickStepCount(void) { ac_load_once(); return g_stepCount; }
NSInteger CTAutoClickCurrentStep(void) { return g_playing ? g_playIndex : -1; }
NSInteger CTAutoClickLoopCount(void) { return g_loopCount; }

NSString *CTAutoClickStepLabel(NSInteger index) {
    ac_load_once();
    if (index < 0 || index >= g_stepCount) return @"";
    CTStep *st = &g_steps[index];
    NSString *name = @(st->name);
    NSString *label = @(st->label);
    if (label.length && ![label isEqualToString:name])
        return [NSString stringWithFormat:@"%ld. %@ · %@", (long)(index + 1), name, label];
    return [NSString stringWithFormat:@"%ld. %@", (long)(index + 1), name];
}

void CTAutoClickDeleteStep(NSInteger index) {
    ac_load_once();
    if (index < 0 || index >= g_stepCount) return;
    for (int i = (int)index; i < g_stepCount - 1; i++) g_steps[i] = g_steps[i + 1];
    g_stepCount--;
    ac_save();
    ac_refresh_dots();
}

void CTAutoClickClearSteps(void) {
    ac_load_once();
    g_stepCount = 0;
    g_playIndex = -1;
    ac_save();
    ac_refresh_dots();
}

double CTAutoClickStepDelay(void) { ac_load_once(); return g_stepDelay; }
double CTAutoClickLoopDelay(void) { ac_load_once(); return g_loopDelay; }
void CTAutoClickSetStepDelay(double v) {
    ac_load_once();
    if (v < 0.05) v = 0.05;
    if (v > 5.0) v = 5.0;
    g_stepDelay = v;
    ac_save();
}
void CTAutoClickSetLoopDelay(double v) {
    ac_load_once();
    if (v < 0.05) v = 0.05;
    if (v > 30.0) v = 30.0;
    g_loopDelay = v;
    ac_save();
}

NSString *CTAutoClickStatus(void) {
    ac_load_once();
    if (g_playing)
        return [NSString stringWithFormat:@"Đang phát %ld/%d · vòng %ld",
                (long)(g_playIndex < 0 ? 0 : g_playIndex + 1), g_stepCount, (long)g_loopCount];
    if (g_recording)
        return [NSString stringWithFormat:@"Đang ghi · %d bước", g_stepCount];
    return [NSString stringWithFormat:@"%d bước", g_stepCount];
}

// ---------------------------------------------------------------------------
// Overlay chấm số trên màn hình game (chỉ để xem, không nhận chạm)
// ---------------------------------------------------------------------------
@interface CTAutoClickDotsView : UIView
@end

static CTAutoClickDotsView *g_dots = nil;
static __weak UIView *g_dotsHost = nil;
static BOOL g_overlayOn = NO;

@implementation CTAutoClickDotsView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (g_stepCount <= 0) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (w < 10 || h < 10) return;

    NSInteger cur = g_playing ? g_playIndex : -1;
    UIFont *font = [UIFont boldSystemFontOfSize:12];
    NSDictionary *attrs = @{ NSFontAttributeName: font,
                             NSForegroundColorAttributeName: [UIColor blackColor] };
    for (int i = 0; i < g_stepCount; i++) {
        CGFloat sx = g_steps[i].nx * w;
        CGFloat sy = h - g_steps[i].ny * h;
        BOOL active = (cur == i);
        UIColor *fill = active ? [UIColor systemYellowColor]
                               : [UIColor colorWithRed:1 green:0.35 blue:0.5 alpha:0.95];
        CGContextSetFillColorWithColor(ctx, fill.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(sx - 11, sy - 11, 22, 22));

        NSString *n = [NSString stringWithFormat:@"%d", i + 1];
        CGSize sz = [n sizeWithAttributes:attrs];
        [n drawAtPoint:CGPointMake(sx - sz.width / 2, sy - sz.height / 2) withAttributes:attrs];
    }
}
@end

static UIView *ac_find_window_view(void) {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)s;
        for (UIWindow *w in ws.windows) if (w.isKeyWindow) return w;
        if (ws.windows.count) return ws.windows.firstObject;
    }
    return [UIApplication sharedApplication].keyWindow;
}

static void ac_refresh_dots(void) {
    if (!g_overlayOn) {
        if (g_dots) { [g_dots removeFromSuperview]; g_dots = nil; }
        return;
    }
    // Ưu tiên host của menu mod (nằm trên Unity, dưới panel) để chấm không
    // che panel; nếu chưa có thì tạm dùng window.
    UIView *host = g_dotsHost ?: ac_find_window_view();
    if (!host) return;
    if (!g_dots || g_dots.superview != host) {
        [g_dots removeFromSuperview];
        g_dots = [[CTAutoClickDotsView alloc] initWithFrame:host.bounds];
        if (host == g_dotsHost) [host insertSubview:g_dots atIndex:0];
        else [host addSubview:g_dots];
    } else {
        g_dots.frame = host.bounds;
    }
    [g_dots setNeedsDisplay];
}

void CTAutoClickSetOverlayVisible(BOOL on) {
    g_overlayOn = on;
    CTConfigSetBool(kStoreOverlay, on);
    ac_refresh_dots();
}

void CTAutoClickAttachOverlay(UIView *host) {
    g_dotsHost = host;
    if (!CTConfigGetBool(kStoreOverlay, YES)) g_overlayOn = NO;
    else g_overlayOn = YES;
    if (!g_overlayOn) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ac_refresh_dots(); });
}
