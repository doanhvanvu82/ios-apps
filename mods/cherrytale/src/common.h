// Khai báo dùng chung cho dylib mod Cherry Tale.
// Toàn bộ code là ObjC++ (không Swift) vì app Unity không có libswiftCore.
#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef NS_ENUM(NSInteger, CTRisk) {
    CTRiskSafe = 0,
    CTRiskMedium = 1,
    CTRiskHigh = 2,
};

typedef NS_ENUM(NSInteger, CTControl) {
    CTControlSwitch = 0,
    CTControlSlider = 1,
    CTControlAction = 2,
};

// Một mục trong menu. install() trả về NO nếu resolve/hook thất bại; khi đó
// menu hiện mục ở trạng thái xám kèm lý do (describe ghi vào buf).
typedef struct CTFeatureDef {
    const char *fid;
    const char *title;
    const char *tab;
    CTRisk risk;
    CTControl control;
    double minValue;
    double maxValue;
    double step;
    double defaultValue;
    BOOL (*install)(void);
    void (*uninstall)(void);
    void (*describe)(char *buf, size_t len);
} CTFeatureDef;

extern const CTFeatureDef *ct_features(size_t *count);

// ---- config (NSUserDefaults suite vn.vudv.cherrytale.mod) ----
double CTConfigGetNumber(NSString *key, double def);
BOOL CTConfigGetBool(NSString *key, BOOL def);
void CTConfigSetNumber(NSString *key, double v);
void CTConfigSetBool(NSString *key, BOOL v);
NSString *CTConfigGetString(NSString *key, NSString *def);
void CTConfigSetString(NSString *key, NSString *v);
void CTConfigFlush(void);

// ---- il2cpp ----
void CTIL2CPPStart(void);
BOOL CTIL2CPPTryInit(void);   // GỌI TRÊN MAIN THREAD
BOOL CTIL2CPPReady(void);
void *CTFindClass(const char *name);           // namespace rỗng (game dùng global namespace)
void *CTFindMethod(void *klass, const char *name, int paramCount);
void *CTFindAnyMethod(void *klass, const char *name);
BOOL CTFindFieldOffset(void *klass, const char *name, size_t *outOffset);
NSString *CTMethodSignature(void *method);
void *CTMethodPtr(void *method);
BOOL CTObjectIsNumericActor(void *obj);
BOOL CTObjectIsClass(void *obj, const char *name);
void *CTFindClassNS(const char *ns, const char *name);
void *CTObjectClass(void *obj);
void *CTSafeInvoke(void *method, void *obj, void **args);
// Như CTSafeInvoke nhưng trả YES/NO theo exception và cho lấy kết quả thô
// (hàm void trả về NULL hợp lệ nên không thể dùng con trỏ để đoán thành công).
BOOL CTSafeInvokeR(void *method, void *obj, void **args, void **outResult);
void *CTTypeObject(void *klass);
void *CTObjectNew(void *klass);                    // il2cpp_object_new
void *CTClassFromType(void *type);                 // il2cpp_class_from_type
void *CTObjectUnbox(void *boxed);                  // il2cpp_object_unbox
void *CTMethodParam(void *method, int index);      // Il2CppType của tham số
void *CTNewInstance(void *klass, void **args);     // object_new + gọi .ctor(args)
BOOL CTInvokeVirtual(void *obj, void *method, void **args); // runtime_invoke bắt exception
int CTArrayLength(void *arr);
void *CTArrayElem(void *arr, int index);
NSString *CTString(void *il2cppString);
void *CTVirtualMethod(void *obj, void *method);

// Liệt kê nút UI (Debug)
NSString *CTAutoDumpButtons(void);

// ---- auto click (mọi hàm phải gọi trên MAIN THREAD) ----
void CTAutoClickLoad(void);
BOOL CTAutoClickIsRecording(void);
BOOL CTAutoClickIsPlaying(void);
void CTAutoClickSetRecording(BOOL on);
void CTAutoClickSetPlaying(BOOL on);
void CTAutoClickToggleRecording(void);
void CTAutoClickTogglePlaying(void);
NSInteger CTAutoClickStepCount(void);
NSString *CTAutoClickStepLabel(NSInteger index);
void CTAutoClickDeleteStep(NSInteger index);
void CTAutoClickClearSteps(void);
double CTAutoClickStepDelay(void);
double CTAutoClickLoopDelay(void);
void CTAutoClickSetStepDelay(double v);
void CTAutoClickSetLoopDelay(double v);
NSInteger CTAutoClickCurrentStep(void);   // -1 khi không phát
NSInteger CTAutoClickLoopCount(void);
NSString *CTAutoClickStatus(void);
void CTAutoClickSetOverlayVisible(BOOL on);
void CTAutoClickAttachOverlay(UIView *host);
// Hook OnPointerClick gọi vào đây (self = BtnClickEvent, eventData = PointerEventData).
void CTAutoClickObserveClick(void *self, void *eventData);
// Hook ghi click đã được cài chưa (bản _safe / emergency off -> NO).
BOOL CTAutoClickRecordAvailable(void);

// ---- hooks ----
BOOL CTHooksActive(void);
void CTStaticSetup(void);   // gọi sớm trong constructor
void CTHooksInstallAll(void);
void CTHooksUninstallAll(void);
void CTHooksLoadConfig(void);
void CTHooksSaveConfig(void);
BOOL CTHooksGetFlag(NSString *fid);
double CTHooksGetNumber(NSString *fid);
void CTHooksSetFlag(NSString *fid, BOOL value);
void CTHooksSetNumber(NSString *fid, double value);
void CTApplyPreset(NSInteger preset);
void CTApplyBattleSpeed(double speed);

// Thống kê số lần hook được gọi (chẩn đoán Debug).
size_t CTHookTargetCount(void);
const char *CTHookTargetKey(size_t index);
uint64_t CTHookTargetHits(size_t index);

// Trạng thái từng mục sau khi cài hook (UI hiện xám nếu NO).
BOOL CTFeatureAvailable(size_t index);
const char *CTFeatureReason(size_t index);
void CTHooksMarkUnavailable(const char *reason); // dùng cho bản recon/_safe
BOOL CTEmergencyDisabled(void);
void CTEmergencySet(BOOL disabled);

// ---- recon ----
void CTReconRun(void);

// ---- log ----
void CTLog(NSString *fmt, ...);
NSString *CTLogText(void);
void CTLogClear(void);

// ---- UI ----
void CTUIStart(void);
void CTUIRefresh(void);
void CTUIShowResolvedList(void);

#ifdef __cplusplus
}
#endif
