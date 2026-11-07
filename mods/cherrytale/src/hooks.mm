// Registry hook dùng CƠ CHẾ TĨNH: entry của hàm trong UnityFramework đã bị vá
// sẵn lúc build để nhảy qua slot trong segment __CTHOOK. Dylib chỉ ghi địa chỉ
// vào slot (trang dữ liệu — không phải trang code) nên bản ký Ksign
// (CS_HARD|CS_KILL, không get-task-allow) không giết tiến trình.
//
// Mặc định mỗi slot trỏ tới trampoline trong dylib: chạy lại 3 lệnh gốc rồi
// nhảy về func+12 => hành vi y như chưa mod. Bật tính năng = ghi địa chỉ hook.
#import "common.h"
#include "ct_targets.h"

#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <mach-o/dyld.h>

// ---------------------------------------------------------------------------
// Cache giá trị (hook đọc nóng)
// ---------------------------------------------------------------------------
static volatile BOOL g_hooksActive = YES;
static volatile float g_dmgMul = 3.0f;
static volatile float g_dmgTakenDiv = 1.0f;
static volatile BOOL g_invincible = NO;
static volatile BOOL g_alwaysCrit = NO;
static volatile float g_critMul = 1.0f;
static volatile BOOL g_cdZero = NO;
static volatile BOOL g_unlimitedSP = NO;
static volatile BOOL g_autoWin = NO;
static volatile BOOL g_enemyHp1 = NO;
static volatile BOOL g_unlockPuzzles = NO;
static volatile BOOL g_unlockSecrets = NO;
static volatile BOOL g_instantClimax = NO;
static volatile BOOL g_maxAffection = NO;
static volatile BOOL g_unlockAllCG = NO;
static volatile BOOL g_skipBattleAnim = NO;
static volatile BOOL g_autoRepeat = NO;
static volatile BOOL g_skipTutorial = NO;
static volatile BOOL g_analyticsOff = YES;

BOOL CTHooksActive(void) { return g_hooksActive; }

// ---------------------------------------------------------------------------
// Trạng thái tĩnh
// ---------------------------------------------------------------------------
static uintptr_t g_uf_base = 0;
static BOOL g_static_ok = NO;
static BOOL g_target_ok[CT_TARGET_COUNT];
static void *g_tramps[CT_TARGET_COUNT] = CT_TRAMP_TABLE;
static uint64_t *g_backs[CT_TARGET_COUNT] = CT_BACK_TABLE;
static char g_lastError[512] = {0};
static volatile uint64_t g_hits[CT_TARGET_COUNT];

static BOOL (*fn_IsPlayerTeam)(void *) = NULL;
static size_t off_FromActor = 0, off_TargetActor = 0;
static BOOL offsets_ok = NO;

static void ct_apply_analytics_early(void);

// ---------------------------------------------------------------------------
// Khởi tạo sớm: gọi từ constructor TRƯỚC khi UnityFramework chạy code.
// ---------------------------------------------------------------------------
void CTStaticSetup(void) {
    if (g_static_ok) return;

    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework.framework/UnityFramework")) {
            g_uf_base = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    if (!g_uf_base) {
        CTLog(@"static: chưa thấy UnityFramework, base=0");
        return;
    }

    for (int i = 0; i < CT_TARGET_COUNT; i++) {
        *g_backs[i] = (uint64_t)(g_uf_base + CT_TARGETS[i].rva + 12);
        *(uint64_t *)(g_uf_base + CT_TARGETS[i].slotRva) = (uint64_t)g_tramps[i];
        g_target_ok[i] = YES;
    }
    g_static_ok = YES;
    ct_apply_analytics_early(); // chặn analytics trước khi SDK kịp gửi
    CTLog(@"static: UF base=%p, %d slot", (void *)g_uf_base, CT_TARGET_COUNT);
}

static void ct_set_slot(int idx, BOOL on, void *hook) {
    if (!g_static_ok || idx < 0 || idx >= CT_TARGET_COUNT) return;
    if (on && !g_target_ok[idx]) on = NO;
    uint64_t *slot = (uint64_t *)(g_uf_base + CT_TARGETS[idx].slotRva);
    *slot = on ? (uint64_t)hook : (uint64_t)g_tramps[idx];
}

// ---------------------------------------------------------------------------
// Resolve phụ trợ
// ---------------------------------------------------------------------------
static void ensure_team_fn(void) {
    if (fn_IsPlayerTeam) return;
    void *k = CTFindClass("NumericActor");
    if (!k) return;
    void *m = CTFindMethod(k, "IsPlayerTeam", 0);
    if (!m) m = CTFindAnyMethod(k, "IsPlayerTeam");
    if (m) fn_IsPlayerTeam = (BOOL (*)(void *)) CTMethodPtr(m);
}

static void ensure_effect_offsets(void) {
    if (offsets_ok) return;
    void *k = CTFindClass("NumericTimeToEffect");
    if (!k) return;
    size_t a = 0, b = 0;
    if (CTFindFieldOffset(k, "FromActor", &a) && CTFindFieldOffset(k, "TargetActor", &b)) {
        off_FromActor = a; off_TargetActor = b; offsets_ok = YES;
    }
}

// Team người chơi = 0 (theo NumericActor.IsPlayerTeam). Get_Final_HP nhận
// IActor nên có thể là ActorData, không chỉ NumericActor.
static size_t off_OldFromActor = 0, off_OldTargetActor = 0;
static BOOL old_offsets_ok = NO;
static void ensure_old_effect_offsets(void) {
    if (old_offsets_ok) return;
    void *k = CTFindClass("TimeToEffect");
    if (!k) return;
    size_t a = 0, b = 0;
    if (CTFindFieldOffset(k, "FromActor", &a) && CTFindFieldOffset(k, "TargetActor", &b)) {
        off_OldFromActor = a; off_OldTargetActor = b; old_offsets_ok = YES;
    }
}
static inline void *oeff_from(void *e) { return *(void **)((char *)e + off_OldFromActor); }
static inline void *oeff_target(void *e) { return *(void **)((char *)e + off_OldTargetActor); }

// Đọc ActorData.TeamType (0 = team người chơi), dùng chung cho Actor và ActorData.
static size_t off_ActorDataField = (size_t)-1, off_TeamType = (size_t)-1;
static BOOL read_team_from_data(void *ad, BOOL *ok) {
    *ok = NO;
    if (!ad) return NO;
    if (off_TeamType == (size_t)-1) {
        void *k = CTFindClass("ActorData");
        size_t o = 0;
        off_TeamType = (k && CTFindFieldOffset(k, "TeamType", &o)) ? o : (size_t)-2;
    }
    if (off_TeamType == (size_t)-2) return NO;
    *ok = YES;
    return (*(int *)((char *)ad + off_TeamType)) == 0;
}

static BOOL actor_is_player(void *actor) {
    if (!actor) return NO;
    if (CTObjectIsNumericActor(actor)) return fn_IsPlayerTeam ? fn_IsPlayerTeam(actor) : NO;
    if (CTObjectIsClass(actor, "ActorData")) {
        BOOL ok = NO;
        BOOL p = read_team_from_data(actor, &ok);
        return ok ? p : NO;
    }
    if (CTObjectIsClass(actor, "Actor")) {
        if (off_ActorDataField == (size_t)-1) {
            void *k = CTFindClass("Actor");
            size_t o = 0;
            off_ActorDataField = (k && CTFindFieldOffset(k, "actorData", &o)) ? o : (size_t)-2;
        }
        if (off_ActorDataField != (size_t)-2) {
            void *ad = *(void **)((char *)actor + off_ActorDataField);
            BOOL ok = NO;
            BOOL p = read_team_from_data(ad, &ok);
            return ok ? p : NO;
        }
    }
    return NO;
}
static inline void *eff_from(void *eff) { return *(void **)((char *)eff + off_FromActor); }
static inline void *eff_target(void *eff) { return *(void **)((char *)eff + off_TargetActor); }

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------
static int hook_dmg(void *self, void *eff, bool refOp, float overflow,
                    bool *isCrit, bool *isBlock, bool *isThrough) {
    g_hits[CT_T_dmg]++;
    int (*orig)(void *, void *, bool, float, bool *, bool *, bool *) =
        (int (*)(void *, void *, bool, float, bool *, bool *, bool *)) g_tramps[CT_T_dmg];
    int r = orig(self, eff, refOp, overflow, isCrit, isBlock, isThrough);
    if (!g_hooksActive || !eff || !offsets_ok) return r;
    void *from = eff_from(eff);
    void *target = eff_target(eff);
    BOOL crit = (isCrit && *isCrit);
    if (g_alwaysCrit) {
        crit = YES;
        if (isCrit) *isCrit = true;
    }
    if (from && actor_is_player(from)) {
        if (g_dmgMul > 1.0f && r > 0) r = (int)lrintf((float)r * g_dmgMul);
        if (crit && g_critMul > 1.0f && r > 0) r = (int)lrintf((float)r * g_critMul);
    }
    if (target && actor_is_player(target) && g_dmgTakenDiv > 1.0f && r > 0) {
        r = (int)lrintf((float)r / g_dmgTakenDiv);
        if (r < 1) r = 1;
    }
    return r;
}

static bool hook_crit(void *self, int chance) {
    g_hits[CT_T_crit]++;
    bool (*orig)(void *, int) = (bool (*)(void *, int)) g_tramps[CT_T_crit];
    if (g_hooksActive && g_alwaysCrit) return true;
    return orig(self, chance);
}

static bool hook_inval(void *self, void *eff) {
    g_hits[CT_T_inval]++;
    bool (*orig)(void *, void *) = (bool (*)(void *, void *)) g_tramps[CT_T_inval];
    if (g_hooksActive && g_invincible && eff && offsets_ok && actor_is_player(eff_target(eff)))
        return true;
    return orig(self, eff);
}

static float hook_cd(void *self, int type) {
    g_hits[CT_T_cd]++;
    float (*orig)(void *, int) = (float (*)(void *, int)) g_tramps[CT_T_cd];
    if (g_hooksActive && g_cdZero) return 0.0f;
    return orig(self, type);
}

static int hook_mana(void *self, int team) {
    g_hits[CT_T_mana]++;
    int (*orig)(void *, int) = (int (*)(void *, int)) g_tramps[CT_T_mana];
    if (g_hooksActive && g_unlimitedSP && team == 0) return 9999;
    return orig(self, team);
}

static bool hook_win(void *self) {
    g_hits[CT_T_win]++;
    bool (*orig)(void *) = (bool (*)(void *)) g_tramps[CT_T_win];
    if (g_hooksActive && g_autoWin) return true;
    return orig(self);
}

static int hook_hp(void *actor) {
    g_hits[CT_T_hp]++;
    int (*orig)(void *) = (int (*)(void *)) g_tramps[CT_T_hp];
    int r = orig(actor);
    if (g_hooksActive && g_enemyHp1 && actor &&
        (CTObjectIsNumericActor(actor) || CTObjectIsClass(actor, "ActorData"))) {
        if (!actor_is_player(actor)) return 1;
    }
    return r;
}

static bool hook_lock2(void *self, int section, void *role) {
    g_hits[CT_T_lock2]++;
    bool (*orig)(void *, int, void *) = (bool (*)(void *, int, void *)) g_tramps[CT_T_lock2];
    if (g_hooksActive && (g_unlockAllCG || g_unlockSecrets)) return false;
    return orig(self, section, role);
}
static bool hook_lock3(void *self, int section, void *role, int *outNeedLv) {
    g_hits[CT_T_lock3]++;
    bool (*orig)(void *, int, void *, int *) = (bool (*)(void *, int, void *, int *)) g_tramps[CT_T_lock3];
    if (g_hooksActive && (g_unlockAllCG || g_unlockSecrets)) {
        if (outNeedLv) *outNeedLv = 0;
        return false;
    }
    return orig(self, section, role, outNeedLv);
}

static int hook_puzlv(void *self) {
    g_hits[CT_T_puzlv]++;
    int (*orig)(void *) = (int (*)(void *)) g_tramps[CT_T_puzlv];
    if (g_hooksActive && g_unlockPuzzles) return 0;
    return orig(self);
}
static int hook_seclv(void *self) {
    g_hits[CT_T_seclv]++;
    int (*orig)(void *) = (int (*)(void *)) g_tramps[CT_T_seclv];
    if (g_hooksActive && g_unlockPuzzles) return 0;
    return orig(self);
}

static int hook_favexp(void *self) {
    g_hits[CT_T_favexp]++;
    int (*orig)(void *) = (int (*)(void *)) g_tramps[CT_T_favexp];
    if (g_hooksActive && g_maxAffection) return 999999999;
    return orig(self);
}
static int hook_favlvl(void *self) {
    g_hits[CT_T_favlvl]++;
    int (*orig)(void *) = (int (*)(void *)) g_tramps[CT_T_favlvl];
    if (g_hooksActive && g_maxAffection) return 99;
    return orig(self);
}

static void hook_excited(void *self, int value) {
    g_hits[CT_T_excited]++;
    void (*orig)(void *, int) = (void (*)(void *, int)) g_tramps[CT_T_excited];
    if (g_hooksActive && g_instantClimax) value = 9999;
    orig(self, value);
}

static bool hook_skipbattle(void *self) {
    g_hits[CT_T_skipbattle]++;
    bool (*orig)(void *) = (bool (*)(void *)) g_tramps[CT_T_skipbattle];
    if (g_hooksActive && g_skipBattleAnim) return true;
    return orig(self);
}

static bool hook_autofight(void *self) {
    g_hits[CT_T_autofight]++;
    bool (*orig)(void *) = (bool (*)(void *)) g_tramps[CT_T_autofight];
    if (g_hooksActive && g_autoRepeat) return true;
    return orig(self);
}
static bool hook_autofighting(void *self) {
    g_hits[CT_T_autofighting]++;
    bool (*orig)(void *) = (bool (*)(void *)) g_tramps[CT_T_autofighting];
    if (g_hooksActive && g_autoRepeat) return true;
    return orig(self);
}

static int hook_favlvmain(void *self) {
    g_hits[CT_T_favlvmain]++;
    int (*orig)(void *) = (int (*)(void *)) g_tramps[CT_T_favlvmain];
    if (g_hooksActive && g_maxAffection) return 99;
    return orig(self);
}

static int hook_odmg(void *self, void *eff, bool refOp, float overflow,
                     bool *isCrit, bool *isBlock, bool *isThrough) {
    g_hits[CT_T_odmg]++;
    int (*orig)(void *, void *, bool, float, bool *, bool *, bool *) =
        (int (*)(void *, void *, bool, float, bool *, bool *, bool *)) g_tramps[CT_T_odmg];
    int r = orig(self, eff, refOp, overflow, isCrit, isBlock, isThrough);
    if (!g_hooksActive || !eff || !old_offsets_ok) return r;
    void *from = oeff_from(eff);
    void *target = oeff_target(eff);
    BOOL crit = (isCrit && *isCrit);
    if (g_alwaysCrit) { crit = YES; if (isCrit) *isCrit = true; }
    if (from && actor_is_player(from)) {
        if (g_dmgMul > 1.0f && r > 0) r = (int)lrintf((float)r * g_dmgMul);
        if (crit && g_critMul > 1.0f && r > 0) r = (int)lrintf((float)r * g_critMul);
    }
    if (target && actor_is_player(target) && g_dmgTakenDiv > 1.0f && r > 0) {
        r = (int)lrintf((float)r / g_dmgTakenDiv);
        if (r < 1) r = 1;
    }
    return r;
}

static bool hook_ocrit(void *self, int chance) {
    g_hits[CT_T_ocrit]++;
    bool (*orig)(void *, int) = (bool (*)(void *, int)) g_tramps[CT_T_ocrit];
    if (g_hooksActive && g_alwaysCrit) return true;
    return orig(self, chance);
}

static float hook_ocd(void *self, int type) {
    g_hits[CT_T_ocd]++;
    float (*orig)(void *, int) = (float (*)(void *, int)) g_tramps[CT_T_ocd];
    if (g_hooksActive && g_cdZero) return 0.0f;
    return orig(self, type);
}

static bool hook_storytag(void *self, int tagId) {
    g_hits[CT_T_storytag]++;
    bool (*orig)(void *, int) = (bool (*)(void *, int)) g_tramps[CT_T_storytag];
    if (g_hooksActive && g_unlockAllCG) return true;
    return orig(self, tagId);
}

static bool hook_storymem(void *self, int areaId) {
    g_hits[CT_T_storymem]++;
    bool (*orig)(void *, int) = (bool (*)(void *, int)) g_tramps[CT_T_storymem];
    if (g_hooksActive && g_unlockAllCG) return true;
    return orig(self, areaId);
}

static bool hook_oinval(void *self, void *eff) {
    g_hits[CT_T_oinval]++;
    bool (*orig)(void *, void *) = (bool (*)(void *, void *)) g_tramps[CT_T_oinval];
    if (g_hooksActive && g_invincible && eff && old_offsets_ok && actor_is_player(oeff_target(eff)))
        return true;
    return orig(self, eff);
}

static int hook_omana(void *self, int team) {
    g_hits[CT_T_omana]++;
    int (*orig)(void *, int) = (int (*)(void *, int)) g_tramps[CT_T_omana];
    if (g_hooksActive && g_unlimitedSP && team == 0) return 9999;
    return orig(self, team);
}

static bool hook_owin(void *self) {
    g_hits[CT_T_owin]++;
    bool (*orig)(void *) = (bool (*)(void *)) g_tramps[CT_T_owin];
    if (g_hooksActive && g_autoWin) return true;
    return orig(self);
}

static bool hook_onotenough(void *self, int team) {
    g_hits[CT_T_onotenough]++;
    bool (*orig)(void *, int) = (bool (*)(void *, int)) g_tramps[CT_T_onotenough];
    if (g_hooksActive && g_unlimitedSP && team == 0) return false;
    return orig(self, team);
}
static bool hook_ostep1(void *self, int team) {
    g_hits[CT_T_ostep1]++;
    bool (*orig)(void *, int) = (bool (*)(void *, int)) g_tramps[CT_T_ostep1];
    if (g_hooksActive && g_unlimitedSP && team == 0) return true;
    return orig(self, team);
}
static bool hook_ostep2(void *self, int team) {
    g_hits[CT_T_ostep2]++;
    bool (*orig)(void *, int) = (bool (*)(void *, int)) g_tramps[CT_T_ostep2];
    if (g_hooksActive && g_unlimitedSP && team == 0) return true;
    return orig(self, team);
}

// Điều kiện sao ải: trả true để mọi điều kiện đều đạt (3 sao).
// --- Tắt analytics: no-op các hàm gửi sự kiện (static, không có self) ---
static void hook_ad_tapdb_start(void *a, void *b, void *c) { (void)a; (void)b; (void)c; }
static void hook_ad_tapdb_event(void *a, void *b) { (void)a; (void)b; }
static void hook_ad_adjust_start(void) {}
static void hook_ad_adjust_event(void *a) { (void)a; }
static void hook_ad_adjust_purchase(double price, void *currency) { (void)price; (void)currency; }

static void ct_apply_analytics_early(void) {
    if (!g_static_ok) return;
    BOOL off = CTConfigGetBool(@"analytics_off", YES);
    ct_set_slot(CT_T_ad_tapdb_start, off, (void *)hook_ad_tapdb_start);
    ct_set_slot(CT_T_ad_tapdb_event, off, (void *)hook_ad_tapdb_event);
    ct_set_slot(CT_T_ad_adjust_start, off, (void *)hook_ad_adjust_start);
    ct_set_slot(CT_T_ad_adjust_event, off, (void *)hook_ad_adjust_event);
    ct_set_slot(CT_T_ad_adjust_buy, off, (void *)hook_ad_adjust_purchase);
}

static bool hook_starcond(void *self, void *achieve, void *record) {
    g_hits[CT_T_starcond]++;
    bool (*orig)(void *, void *, void *) = (bool (*)(void *, void *, void *)) g_tramps[CT_T_starcond];
    if (g_hooksActive && g_autoWin) return true;
    return orig(self, achieve, record);
}

static bool hook_hcgcomplete(void *self) {
    g_hits[CT_T_hcgcomplete]++;
    bool (*orig)(void *) = (bool (*)(void *)) g_tramps[CT_T_hcgcomplete];
    if (g_hooksActive && g_unlockAllCG) return true;
    return orig(self);
}

static bool hook_teaching(void *self, int tid) {
    g_hits[CT_T_teaching]++;
    bool (*orig)(void *, int) = (bool (*)(void *, int)) g_tramps[CT_T_teaching];
    if (g_hooksActive && g_skipTutorial) return false;
    return orig(self, tid);
}

#ifdef CT_T_click_btnev
// Ghi nhận click thật của người dùng cho engine autoclick. Quan sát TRƯỚC khi
// gọi nguyên bản: handler gốc có thể tắt/huỷ object nên đọc tên sau sẽ rỗng.
static void hook_click_btnev(void *self, void *eventData) {
    g_hits[CT_T_click_btnev]++;
    void (*orig)(void *, void *) = (void (*)(void *, void *)) g_tramps[CT_T_click_btnev];
    CTAutoClickObserveClick(self, eventData);
    orig(self, eventData);
}
#endif

// ---------------------------------------------------------------------------
// Áp cờ -> slot
// ---------------------------------------------------------------------------
static void ct_apply_all(void) {
    if (!g_static_ok) return;
    BOOL dmgOn = g_hooksActive && (g_dmgMul > 1.001f || g_dmgTakenDiv > 1.001f || g_alwaysCrit);
    ct_set_slot(CT_T_dmg, dmgOn, (void *)hook_dmg);
    ct_set_slot(CT_T_crit, g_hooksActive && g_alwaysCrit, (void *)hook_crit);
    ct_set_slot(CT_T_inval, g_hooksActive && g_invincible, (void *)hook_inval);
    ct_set_slot(CT_T_cd, g_hooksActive && g_cdZero, (void *)hook_cd);
    ct_set_slot(CT_T_mana, g_hooksActive && g_unlimitedSP, (void *)hook_mana);
    ct_set_slot(CT_T_win, g_hooksActive && g_autoWin, (void *)hook_win);
    ct_set_slot(CT_T_hp, g_hooksActive && g_enemyHp1, (void *)hook_hp);
    ct_set_slot(CT_T_lock2, g_hooksActive && (g_unlockAllCG || g_unlockSecrets), (void *)hook_lock2);
    ct_set_slot(CT_T_lock3, g_hooksActive && (g_unlockAllCG || g_unlockSecrets), (void *)hook_lock3);
    ct_set_slot(CT_T_puzlv, g_hooksActive && g_unlockPuzzles, (void *)hook_puzlv);
    ct_set_slot(CT_T_seclv, g_hooksActive && g_unlockPuzzles, (void *)hook_seclv);
    ct_set_slot(CT_T_favexp, g_hooksActive && g_maxAffection, (void *)hook_favexp);
    ct_set_slot(CT_T_favlvl, g_hooksActive && g_maxAffection, (void *)hook_favlvl);
    ct_set_slot(CT_T_excited, g_hooksActive && g_instantClimax, (void *)hook_excited);
    ct_set_slot(CT_T_skipbattle, g_hooksActive && g_skipBattleAnim, (void *)hook_skipbattle);
    ct_set_slot(CT_T_autofight, g_hooksActive && g_autoRepeat, (void *)hook_autofight);
    ct_set_slot(CT_T_autofighting, g_hooksActive && g_autoRepeat, (void *)hook_autofighting);
    ct_set_slot(CT_T_teaching, g_hooksActive && g_skipTutorial, (void *)hook_teaching);
    ct_set_slot(CT_T_hcgcomplete, g_hooksActive && g_unlockAllCG, (void *)hook_hcgcomplete);
    ct_set_slot(CT_T_favlvmain, g_hooksActive && g_maxAffection, (void *)hook_favlvmain);
    ct_set_slot(CT_T_odmg, dmgOn, (void *)hook_odmg);
    ct_set_slot(CT_T_ocrit, g_hooksActive && g_alwaysCrit, (void *)hook_ocrit);
    ct_set_slot(CT_T_ocd, g_hooksActive && g_cdZero, (void *)hook_ocd);
    ct_set_slot(CT_T_storytag, g_hooksActive && g_unlockAllCG, (void *)hook_storytag);
    ct_set_slot(CT_T_storymem, g_hooksActive && g_unlockAllCG, (void *)hook_storymem);
    ct_set_slot(CT_T_oinval, g_hooksActive && g_invincible, (void *)hook_oinval);
    ct_set_slot(CT_T_omana, g_hooksActive && g_unlimitedSP, (void *)hook_omana);
    ct_set_slot(CT_T_owin, g_hooksActive && g_autoWin, (void *)hook_owin);
    ct_set_slot(CT_T_starcond, g_hooksActive && g_autoWin, (void *)hook_starcond);
    BOOL adOff = (BOOL)g_analyticsOff;
    ct_set_slot(CT_T_ad_tapdb_start, adOff, (void *)hook_ad_tapdb_start);
    ct_set_slot(CT_T_ad_tapdb_event, adOff, (void *)hook_ad_tapdb_event);
    ct_set_slot(CT_T_ad_adjust_start, adOff, (void *)hook_ad_adjust_start);
    ct_set_slot(CT_T_ad_adjust_event, adOff, (void *)hook_ad_adjust_event);
    ct_set_slot(CT_T_ad_adjust_buy, adOff, (void *)hook_ad_adjust_purchase);
    ct_set_slot(CT_T_onotenough, g_hooksActive && g_unlimitedSP, (void *)hook_onotenough);
    ct_set_slot(CT_T_ostep1, g_hooksActive && g_unlimitedSP, (void *)hook_ostep1);
    ct_set_slot(CT_T_ostep2, g_hooksActive && g_unlimitedSP, (void *)hook_ostep2);
#ifdef CT_T_click_btnev
    // Luôn bật khi hooks hoạt động: engine chỉ ghi khi người dùng bật ghi.
    ct_set_slot(CT_T_click_btnev, g_hooksActive, (void *)hook_click_btnev);
#endif
}

// ---------------------------------------------------------------------------
// Feature -> target
// ---------------------------------------------------------------------------
typedef struct { const char *fid; int t[6]; } CTFidTargets;
static const CTFidTargets kFidTargets[] = {
    {"dmg_dealt",       {CT_T_dmg, CT_T_odmg, -1, -1, -1, -1}},
    {"dmg_taken",       {CT_T_dmg, CT_T_odmg, -1, -1, -1, -1}},
    {"crit_mult",       {CT_T_dmg, CT_T_odmg, -1, -1, -1, -1}},
    {"invincible",      {CT_T_inval, CT_T_oinval, -1, -1, -1, -1}},
    {"always_crit",     {CT_T_crit, CT_T_ocrit, -1, -1, -1, -1}},
    {"cd_zero",         {CT_T_cd, CT_T_ocd, -1, -1, -1, -1}},
    {"unlimited_sp",    {CT_T_mana, CT_T_omana, CT_T_onotenough, CT_T_ostep1, CT_T_ostep2, -1}},
    {"auto_win",        {CT_T_win, CT_T_owin, CT_T_starcond, -1, -1, -1}},
    {"enemy_hp1",       {CT_T_hp, -1, -1, -1, -1, -1}},
    {"unlock_puzzles",  {CT_T_puzlv, CT_T_seclv, -1, -1, -1, -1}},
    {"unlock_secrets",  {CT_T_lock2, CT_T_lock3, -1, -1, -1, -1}},
    {"instant_climax",  {CT_T_excited, -1, -1, -1, -1, -1}},
    {"max_affection",   {CT_T_favexp, CT_T_favlvl, CT_T_favlvmain, -1, -1, -1}},
    {"unlock_all_cg",   {CT_T_lock2, CT_T_lock3, CT_T_hcgcomplete, CT_T_storytag, CT_T_storymem, -1}},
    {"skip_battle_anim",{CT_T_skipbattle, -1, -1, -1, -1, -1}},
    {"auto_repeat",     {CT_T_autofight, CT_T_autofighting, -1, -1, -1, -1}},
    {"skip_tutorial",   {CT_T_teaching, -1, -1, -1, -1, -1}},
    {"analytics_off",   {CT_T_ad_tapdb_start, CT_T_ad_tapdb_event, CT_T_ad_adjust_start, CT_T_ad_adjust_event, CT_T_ad_adjust_buy, -1}},
};

static const CTFidTargets *fid_targets(NSString *fid) {
    for (size_t i = 0; i < sizeof(kFidTargets) / sizeof(kFidTargets[0]); i++)
        if ([fid isEqualToString:@(kFidTargets[i].fid)]) return &kFidTargets[i];
    return NULL;
}

static BOOL feature_targets_ok(NSString *fid) {
    const CTFidTargets *ft = fid_targets(fid);
    if (!ft) return YES; // tính năng không hook (tốc độ trận, debug)
    for (int i = 0; i < 6 && ft->t[i] >= 0; i++)
        if (!g_target_ok[ft->t[i]]) return NO;
    return YES;
}

// ---------------------------------------------------------------------------
// Bảng tính năng
// ---------------------------------------------------------------------------
static BOOL inst_any(void) { return YES; }
static void uninst_noop(void) {}
static void desc_from_error(char *buf, size_t len) {
    snprintf(buf, len, "%s", g_lastError);
}

static const CTFeatureDef kFeatures[] = {
    // ---- Chiến đấu ----
    {"dmg_dealt",   "Sát thương gây x",        "Chiến đấu", CTRiskMedium, CTControlSlider, 1, 100, 1, 3,  inst_any, uninst_noop, desc_from_error},
    {"dmg_taken",   "Giảm sát thương nhận x",  "Chiến đấu", CTRiskMedium, CTControlSlider, 1, 100, 1, 1,  inst_any, uninst_noop, desc_from_error},
    {"invincible",  "Bất tử",                  "Chiến đấu", CTRiskMedium, CTControlSwitch, 0, 1, 1, 0,    inst_any, uninst_noop, desc_from_error},
    {"always_crit", "Luôn chí mạng",           "Chiến đấu", CTRiskMedium, CTControlSwitch, 0, 1, 1, 0,    inst_any, uninst_noop, desc_from_error},
    {"crit_mult",   "Hệ số sát thương chí mạng","Chiến đấu", CTRiskMedium, CTControlSlider, 1, 20, 0.5, 2, inst_any, uninst_noop, desc_from_error},
    {"cd_zero",     "Hồi chiêu kỹ năng = 0",   "Chiến đấu", CTRiskMedium, CTControlSwitch, 0, 1, 1, 0,    inst_any, uninst_noop, desc_from_error},
    {"unlimited_sp","Điểm kỹ năng không giới hạn","Chiến đấu", CTRiskMedium, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"battle_speed","Tốc độ trận x",           "Chiến đấu", CTRiskMedium, CTControlSlider, 1, 5, 0.5, 1,  inst_any, uninst_noop, desc_from_error},
    {"auto_win",    "Tự thắng trận",           "Chiến đấu", CTRiskHigh,   CTControlSwitch, 0, 1, 1, 0,    inst_any, uninst_noop, desc_from_error},
    {"enemy_hp1",   "Quái HP = 1",             "Chiến đấu", CTRiskHigh,   CTControlSwitch, 0, 1, 1, 0,    inst_any, uninst_noop, desc_from_error},

    // ---- Gallery ----
    {"unlock_puzzles", "Mở khoá Puzzles",      "Gallery", CTRiskSafe, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"unlock_secrets", "Mở khoá Peachy Secrets","Gallery", CTRiskSafe, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"instant_climax", "Instant Climax",       "Gallery", CTRiskSafe, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"max_affection",  "Affection tối đa",     "Gallery", CTRiskSafe, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"unlock_all_cg",  "Mở khoá toàn bộ CG/truyện","Gallery", CTRiskSafe, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},

    // ---- QoL ----
    {"skip_battle_anim", "Bỏ animation chiến đấu","QoL", CTRiskMedium, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"auto_repeat",      "Tự lặp ải",            "QoL", CTRiskMedium, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"skip_tutorial",    "Bỏ qua tutorial",      "QoL", CTRiskMedium, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"analytics_off",    "Tắt analytics",        "QoL", CTRiskSafe,   CTControlSwitch, 0, 1, 1, 1, inst_any, uninst_noop, desc_from_error},

    // ---- Debug ----
    {"debug_resolved", "Liệt kê method đã resolve","Debug", CTRiskSafe, CTControlAction, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"debug_export",   "Xuất dump.cs ra Documents","Debug", CTRiskSafe, CTControlAction, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"debug_log",      "Log panel",               "Debug", CTRiskSafe, CTControlSwitch, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"debug_buttons",  "Liệt kê nút UI ra Documents","Debug", CTRiskSafe, CTControlAction, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
    {"emergency_off",  "TẮT TOÀN BỘ (khẩn cấp)", "Debug", CTRiskSafe, CTControlAction, 0, 1, 1, 0, inst_any, uninst_noop, desc_from_error},
};

const CTFeatureDef *ct_features(size_t *count) {
    if (count) *count = sizeof(kFeatures) / sizeof(kFeatures[0]);
    return kFeatures;
}

// ---------------------------------------------------------------------------
// Trạng thái khả dụng
// ---------------------------------------------------------------------------
static BOOL g_allInstalled = NO;
static BOOL *g_featOK = NULL;
static char **g_featReason = NULL;
static size_t g_featCount = 0;

static void ensure_status_arrays(void) {
    if (g_featOK) return;
    size_t n = 0;
    ct_features(&n);
    g_featCount = n;
    g_featOK = (BOOL *)calloc(n, sizeof(BOOL));
    g_featReason = (char **)calloc(n, sizeof(char *));
}

BOOL CTFeatureAvailable(size_t index) {
    ensure_status_arrays();
    return index < g_featCount ? g_featOK[index] : NO;
}
const char *CTFeatureReason(size_t index) {
    ensure_status_arrays();
    return index < g_featCount && g_featReason[index] ? g_featReason[index] : "";
}

void CTHooksMarkUnavailable(const char *reason) {
    ensure_status_arrays();
    for (size_t i = 0; i < g_featCount; i++) {
        g_featOK[i] = NO;
        free(g_featReason[i]);
        g_featReason[i] = strdup(reason ? reason : "không khả dụng");
    }
    g_hooksActive = NO;
    ct_apply_all(); // đưa mọi slot về trampoline
}

static void set_reason(size_t i, const char *reason) {
    free(g_featReason[i]);
    g_featReason[i] = strdup(reason ? reason : "");
}

void CTHooksInstallAll(void) {
    if (g_allInstalled) return;
    ensure_status_arrays();
    if (!CTIL2CPPReady()) { CTLog(@"hooks: il2cpp chưa sẵn sàng"); return; }
    CTStaticSetup();
    if (!g_static_ok) {
        CTHooksMarkUnavailable("không xác định được UnityFramework");
        return;
    }
    g_allInstalled = YES;

    // Xác minh tên -> đúng RVA đã vá (an toàn nếu IPA khác bản dump)
    for (int i = 0; i < CT_TARGET_COUNT; i++) {
        const CTTarget &t = CT_TARGETS[i];
        void *cls = CTFindClass(t.cls);
        void *m = cls ? CTFindMethod(cls, t.meth, t.pc) : NULL;
        void *ptr = m ? CTMethodPtr(m) : NULL;
        if (!ptr) {
            g_target_ok[i] = NO;
            CTLog(@"verify: không resolve %s.%s/%d", t.cls, t.meth, t.pc);
        } else if ((uintptr_t)ptr != g_uf_base + t.rva) {
            g_target_ok[i] = NO;
            CTLog(@"verify: %s.%s lệch RVA (thực %p, mong %p)",
                  t.cls, t.meth, ptr, (void *)(g_uf_base + t.rva));
        }
    }

    ensure_team_fn();
    ensure_effect_offsets();
    ensure_old_effect_offsets();

    for (size_t i = 0; i < g_featCount; i++) {
        NSString *fid = @(kFeatures[i].fid);
        BOOL ok = feature_targets_ok(fid);
        g_featOK[i] = ok;
        set_reason(i, ok ? "" : "hook không resolve được");
    }
    g_hooksActive = YES;
    ct_apply_all();
    CTLog(@"hooks: sẵn sàng (%d target)", (int)CT_TARGET_COUNT);
}

void CTHooksUninstallAll(void) {
    g_hooksActive = NO;
    ct_apply_all();
    CTLog(@"hooks: về trampoline toàn bộ");
}

BOOL CTAutoClickRecordAvailable(void) {
#ifdef CT_T_click_btnev
    return g_static_ok && g_target_ok[CT_T_click_btnev] && g_hooksActive;
#else
    return NO;
#endif
}

BOOL CTEmergencyDisabled(void) { return CTConfigGetBool(@"emergency_disabled", NO); }

void CTEmergencySet(BOOL disabled) {
    CTConfigSetBool(@"emergency_disabled", disabled);
    CTConfigFlush();
    if (disabled) {
        CTHooksUninstallAll();
        CTHooksMarkUnavailable("đã tắt khẩn cấp");
    } else {
        CTLog(@"hooks: đã bật lại — khởi động lại app");
    }
}

// ---------------------------------------------------------------------------
// Cấu hình
// ---------------------------------------------------------------------------
typedef struct { const char *fid; volatile BOOL *p; } CTFlagEntry;
typedef struct { const char *fid; volatile float *p; } CTNumEntry;

static const CTFlagEntry kFlags[] = {
    {"invincible", &g_invincible}, {"always_crit", &g_alwaysCrit},
    {"cd_zero", &g_cdZero}, {"unlimited_sp", &g_unlimitedSP},
    {"auto_win", &g_autoWin}, {"enemy_hp1", &g_enemyHp1},
    {"unlock_puzzles", &g_unlockPuzzles}, {"unlock_secrets", &g_unlockSecrets},
    {"instant_climax", &g_instantClimax}, {"max_affection", &g_maxAffection},
    {"unlock_all_cg", &g_unlockAllCG}, {"skip_battle_anim", &g_skipBattleAnim},
    {"auto_repeat", &g_autoRepeat}, {"skip_tutorial", &g_skipTutorial},
};
static const CTNumEntry kNums[] = {
    {"dmg_dealt", &g_dmgMul}, {"dmg_taken", &g_dmgTakenDiv}, {"crit_mult", &g_critMul},
};

static volatile BOOL *flag_slot(NSString *fid) {
    for (size_t i = 0; i < sizeof(kFlags) / sizeof(kFlags[0]); i++)
        if ([fid isEqualToString:@(kFlags[i].fid)]) return kFlags[i].p;
    return NULL;
}
static volatile float *num_slot(NSString *fid) {
    for (size_t i = 0; i < sizeof(kNums) / sizeof(kNums[0]); i++)
        if ([fid isEqualToString:@(kNums[i].fid)]) return kNums[i].p;
    return NULL;
}

BOOL CTHooksGetFlag(NSString *fid) { volatile BOOL *p = flag_slot(fid); return p ? *p : NO; }
double CTHooksGetNumber(NSString *fid) { volatile float *p = num_slot(fid); return p ? *p : 0; }

void CTHooksSetFlag(NSString *fid, BOOL value) {
    volatile BOOL *p = flag_slot(fid);
    if (p) *p = value;
    CTConfigSetBool(fid, value);
    ct_apply_all();
}
void CTHooksSetNumber(NSString *fid, double value) {
    volatile float *p = num_slot(fid);
    if (p) *p = (float)value;
    CTConfigSetNumber(fid, value);
    ct_apply_all();
}

void CTHooksLoadConfig(void) {
    g_dmgMul = (float)CTConfigGetNumber(@"dmg_dealt", 3.0);
    g_dmgTakenDiv = (float)CTConfigGetNumber(@"dmg_taken", 1.0);
    g_critMul = (float)CTConfigGetNumber(@"crit_mult", 2.0);
    g_invincible = CTConfigGetBool(@"invincible", NO);
    g_alwaysCrit = CTConfigGetBool(@"always_crit", NO);
    g_cdZero = CTConfigGetBool(@"cd_zero", NO);
    g_unlimitedSP = CTConfigGetBool(@"unlimited_sp", NO);
    g_autoWin = CTConfigGetBool(@"auto_win", NO);
    g_enemyHp1 = CTConfigGetBool(@"enemy_hp1", NO);
    g_unlockPuzzles = CTConfigGetBool(@"unlock_puzzles", NO);
    g_unlockSecrets = CTConfigGetBool(@"unlock_secrets", NO);
    g_instantClimax = CTConfigGetBool(@"instant_climax", NO);
    g_maxAffection = CTConfigGetBool(@"max_affection", NO);
    g_unlockAllCG = CTConfigGetBool(@"unlock_all_cg", NO);
    g_skipBattleAnim = CTConfigGetBool(@"skip_battle_anim", NO);
    g_autoRepeat = CTConfigGetBool(@"auto_repeat", NO);
    g_skipTutorial = CTConfigGetBool(@"skip_tutorial", NO);
    g_analyticsOff = CTConfigGetBool(@"analytics_off", YES);
    g_hooksActive = YES;
}

void CTHooksSaveConfig(void) {
    CTConfigSetNumber(@"dmg_dealt", g_dmgMul);
    CTConfigSetNumber(@"dmg_taken", g_dmgTakenDiv);
    CTConfigSetNumber(@"crit_mult", g_critMul);
    CTConfigSetBool(@"invincible", g_invincible);
    CTConfigSetBool(@"always_crit", g_alwaysCrit);
    CTConfigSetBool(@"cd_zero", g_cdZero);
    CTConfigSetBool(@"unlimited_sp", g_unlimitedSP);
    CTConfigSetBool(@"auto_win", g_autoWin);
    CTConfigSetBool(@"enemy_hp1", g_enemyHp1);
    CTConfigSetBool(@"unlock_puzzles", g_unlockPuzzles);
    CTConfigSetBool(@"unlock_secrets", g_unlockSecrets);
    CTConfigSetBool(@"instant_climax", g_instantClimax);
    CTConfigSetBool(@"max_affection", g_maxAffection);
    CTConfigSetBool(@"unlock_all_cg", g_unlockAllCG);
    CTConfigSetBool(@"skip_battle_anim", g_skipBattleAnim);
    CTConfigSetBool(@"auto_repeat", g_autoRepeat);
    CTConfigSetBool(@"skip_tutorial", g_skipTutorial);
    CTConfigSetBool(@"analytics_off", g_analyticsOff);
    CTConfigFlush();
}

void CTApplyPreset(NSInteger preset) {
    g_dmgMul = (preset == 0) ? 3.0f : (preset == 1 ? 10.0f : 100.0f);
    g_dmgTakenDiv = 1.0f;
    g_alwaysCrit = (preset >= 2);
    g_invincible = (preset >= 2);
    g_critMul = (preset >= 2) ? 5.0f : 1.0f;
    g_autoRepeat = (preset >= 1);
    g_skipBattleAnim = (preset >= 1);
    g_unlockAllCG = (preset >= 2);
    CTHooksSaveConfig();
    ct_apply_all();
    CTLog(@"preset áp dụng: %ld", (long)preset);
}

// UnityEngine.Time.timeScale (managed static, không cần vá code)
void CTApplyBattleSpeed(double speed) {
    if (!CTIL2CPPReady()) return;
    void *k = CTFindClass("UnityEngine.Time");
    if (!k) return;
    void *m = CTFindMethod(k, "set_timeScale", 1);
    if (!m) return;
    void (*fn)(float) = (void (*)(float)) CTMethodPtr(m);
    if (fn) fn((float)speed);
}

// ---- thống kê runtime (Đebug) ----
size_t CTHookTargetCount(void) { return CT_TARGET_COUNT; }
const char *CTHookTargetKey(size_t i) { return i < CT_TARGET_COUNT ? CT_TARGETS[i].key : ""; }
uint64_t CTHookTargetHits(size_t i) { return i < CT_TARGET_COUNT ? g_hits[i] : 0; }
