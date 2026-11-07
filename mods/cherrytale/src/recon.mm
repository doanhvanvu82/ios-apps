// PHASE=recon: chỉ resolve theo tên và ghi log, KHÔNG cài hook nào.
// Kết quả: Documents/cherrytale_recon.txt + NSLog.
#import "common.h"

#include <vector>
#include <string>

typedef struct {
    const char *group;
    const char *className;
    const char *methodName;
    int paramCount; // -1 = liệt kê mọi overload
    const char *note;
} CTCandidate;

// Danh sách ứng viên cho từng tính năng. Nhiều phương án dự phòng mỗi mục.
static const CTCandidate kCandidates[] = {
    // ---- Chiến đấu ----
    {"Chiến đấu", "NumericSkillManager", "GetBaseDmgWith_CritAndBlk", 6, "sát thương gốc (có crit/block)"},
    {"Chiến đấu", "NumericSkillManager", "DmgToActor", 2, "áp sát thương lên actor"},
    {"Chiến đấu", "NumericSkillManager", "DmgToActorByProtect", 2, "sát thương qua protect"},
    {"Chiến đấu", "NumericSkillManager", "IsCritial", 1, "quyết định chí mạng"},
    {"Chiến đấu", "NumericSkillManager", "CheckDmgIsInvalid", 1, "đánh dấu sát thương vô hiệu"},
    {"Chiến đấu", "NumericSkillManager", "CheckIgnoreDmg", 2, "bỏ qua sát thương"},
    {"Chiến đấu", "NumericSkillManager", "GetBaseHealWith_Crit", 3, "hồi máu gốc"},
    {"Chiến đấu", "NumericTimeToEffect", "SetSureCrit", 0, "ép chí mạng"},
    {"Chiến đấu", "NumericTimeToEffect", "get_SureCrit", 0, "cờ chí mạng"},
    {"Chiến đấu", "NumericActor", "GetSkillCDTime", 1, "hồi chiêu kỹ năng"},
    {"Chiến đấu", "NumericActor", "IsPlayerTeam", 0, "phân biệt team người chơi"},
    {"Chiến đấu", "NumericActor", "get_eBattleTeam", 0, "team enum"},
    {"Chiến đấu", "NumericBattleCenter", "GetMana", 1, "mana/điểm kỹ năng"},
    {"Chiến đấu", "NumericBattleCenter", "SetMana", 2, "đặt mana"},
    {"Chiến đấu", "NumericBattleCenter", "IsMaxMana", 1, "mana đầy"},
    {"Chiến đấu", "NumericCalculate", "IsWin", 0, "kết quả thắng"},
    {"Chiến đấu", "NumericCalculate", "get_FrameDeltaTimeToFloat", 0, "tốc độ mô phỏng trận"},
    {"Chiến đấu", "NumericCalculate", "OnCalculateNextRoundStep", 1, "bước vòng đấu"},
    {"Chiến đấu", "NumericCalculate", "SetAutoFight", 1, "auto fight"},
    {"Chiến đấu", "NumericBattleCenter", "SetAutoFight", 1, "auto fight"},
    {"Chiến đấu", "BattleFormula", "Get_Final_HP", 1, "HP cuối cùng"},
    {"Chiến đấu", "BattleFormula", "Get_Final_pAtk", 1, "ATK vật lý cuối"},
    {"Chiến đấu", "BattleFormula", "Get_Final_mAtk", 1, "ATK phép cuối"},
    {"Chiến đấu", "BattleFormula", "Get_Final_pDef", 1, "DEF vật lý cuối"},
    {"Chiến đấu", "BattleCenter", "IsSkipBattle", 0, "bỏ qua animation trận"},
    {"Chiến đấu", "BattleCenter", "CallSkipBattle", 0, "gọi bỏ qua trận"},

    // ---- Gallery / nội dung ----
    {"Gallery", "RoleSecret", "IsLock", 1, "khoá CG"},
    {"Gallery", "RoleSecret", "GetProgress_Puzzle", 0, "tiến độ puzzle"},
    {"Gallery", "SecretModule", "CheckNowRoleSectionState", 0, "trạng thái section hiện tại"},
    {"Gallery", "SecretModule", "GetServerData_HcgBy", 1, "dữ liệu HCG từ server"},
    {"Gallery", "SecretModule", "IsReviewSameHCG", 1, "review HCG"},
    {"Gallery", "RolePuzzleData", "get_GetOpenLv", 0, "level mở puzzle"},
    {"Gallery", "RoleSecretSetionData", "get_GetOpenLv", 0, "level mở section"},
    {"Gallery", "RoleFavorability", "get_Exp", 0, "affection exp"},
    {"Gallery", "RoleFavorability", "get_Level", 0, "affection level"},
    {"Gallery", "RoleFavorability", "get_FavoriteMaxLv", 0, "affection max"},
    {"Gallery", "AttributeAltarModule", "IsHcgUnlock", 1, "HCG unlock"},
    {"Gallery", "AttributeAltarModule", "CheckHcgIsOpen", 1, "HCG open"},
    {"Gallery", "SecretHCGClickGameMainUI", "AddExcited", 1, "thanh climax"},
    {"Gallery", "SecretHCGClickGameMainUI", "CanClick", 1, "điều kiện click"},
    {"Gallery", "SecretHCGClickGameMainUI", "OnClick", 0, "xử lý click"},
    {"Gallery", "SecretModule.HCG", "IsComplete", 0, "CG hoàn thành"},
    {"Gallery", "SecretModule.HCG", "IsColorful", 0, "CG colorful"},
    {"Gallery", "SecretModule.HCG.Puzzle", "get_MaxPiece", 0, "số mảnh puzzle"},

    // ---- QoL ----
    {"QoL", "StageModule", "get_IsNeedAutoFight", 0, "tự lặp ải"},
    {"QoL", "StageModule", "SetAutoFightStatus", 1, "bật auto fight"},
    {"QoL", "UIPreferecneModule", "get_AutoFighting", 0, "auto fighting"},
    {"QoL", "TeachingModule", "isTeachingID_CanBeTrigger", 1, "tutorial trigger"},
    {"QoL", "TeachingModule", "CheckTeachingPoint_And_Trigger", 3, "điểm tutorial"},
    {"QoL", "StoryPlayModule", "IsStoryPlaying", 0, "story đang chạy"},
    {"QoL", "StoryPlayModule", "SkipStory", 0, "bỏ qua story"},
};

static NSMutableString *g_out = nil;

static void out(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    [g_out appendString:s];
    [g_out appendString:@"\n"];
    NSLog(@"[Recon] %@", s);
}

static NSString *documentsPath(void) {
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    if (urls.count) return [urls[0] path];
    return NSTemporaryDirectory();
}

void CTReconRun(void) {
    if (!g_out) g_out = [NSMutableString new];
    [g_out setString:@""];

    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    out(@"Cherry Tale mod — RECON");
    out(@"Thời gian: %@", [NSDate date]);
    out(@"Bundle: %@  version %@ (%@)",
        info[@"CFBundleIdentifier"], info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]);
    out(@"il2cpp ready: %@", CTIL2CPPReady() ? @"YES" : @"NO");
    out(@"");

    if (!CTIL2CPPReady()) {
        out(@"KHÔNG resolve được: il2cpp chưa sẵn sàng sau thời gian chờ.");
    } else {
        out(@"Định dạng: [nhóm] Class.Method/paramCount -> trạng thái | chữ ký");
        out(@"");
        NSString *lastGroup = nil;
        for (size_t i = 0; i < sizeof(kCandidates) / sizeof(kCandidates[0]); i++) {
            const CTCandidate &c = kCandidates[i];
            NSString *group = @(c.group);
            if (!lastGroup || ![lastGroup isEqualToString:group]) {
                out(@"================ %@ ================", group);
                lastGroup = group;
            }
            NSString *cls = @(c.className);
            NSString *mth = @(c.methodName);
            void *klass = CTFindClass(c.className);
            if (!klass) {
                out(@"[%@] %@.%@ -> KHÔNG THẤY CLASS (%@)", group, cls,
                    c.paramCount >= 0 ? [NSString stringWithFormat:@"%@/%d", mth, c.paramCount] : mth, @(c.note));
                continue;
            }
            if (c.paramCount >= 0) {
                void *m = CTFindMethod(klass, c.methodName, c.paramCount);
                if (m) {
                    out(@"[%@] %@.%@/%d -> OK | %@  // %@", group, cls, mth, c.paramCount,
                        CTMethodSignature(m), @(c.note));
                } else {
                    void *any = CTFindAnyMethod(klass, c.methodName);
                    if (any) {
                        out(@"[%@] %@.%@/%d -> SAI PARAM COUNT (có overload khác) | %@  // %@",
                            group, cls, mth, c.paramCount, CTMethodSignature(any), @(c.note));
                    } else {
                        out(@"[%@] %@.%@/%d -> KHÔNG THẤY METHOD  // %@", group, cls, mth, c.paramCount, @(c.note));
                    }
                }
            } else {
                void *any = CTFindAnyMethod(klass, c.methodName);
                if (any) {
                    out(@"[%@] %@.%@ -> OK | %@  // %@", group, cls, mth, CTMethodSignature(any), @(c.note));
                } else {
                    out(@"[%@] %@.%@ -> KHÔNG THẤY METHOD  // %@", group, cls, mth, @(c.note));
                }
            }
        }
    }

    out(@"");
    out(@"Ghi chú: script.json/dump.cs sinh bằng Il2CppDumper v6.7.46 (metadata v27.1).");

    NSString *path = [documentsPath() stringByAppendingPathComponent:@"cherrytale_recon.txt"];
    NSError *err = nil;
    BOOL ok = [g_out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) {
        path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cherrytale_recon.txt"];
        ok = [g_out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    }
    CTLog(@"recon: ghi %@ -> %@ (lỗi: %@)", ok ? @"OK" : @"THẤT BẠI", path, err);
    NSLog(@"[Recon] file: %@\n%@", path, g_out);
}
