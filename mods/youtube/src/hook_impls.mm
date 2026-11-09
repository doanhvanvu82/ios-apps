// Thân hook + bảng hook cho dylib mod YouTube.
// Mỗi hàm dưới đây là IMP thay cho method gốc; con trỏ gốc nằm trong biến
// static `*_orig` do bảng YTM_HOOKS trỏ tới.
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Chặn quảng cáo
// ---------------------------------------------------------------------------
static IMP _orig_isMonetized;
static BOOL ytm_isMonetized(id self, SEL _cmd) {
    if (YTAdsOffEnabled()) return NO;
    return ((BOOL (*)(id, SEL))_orig_isMonetized)(self, _cmd);
}

static IMP _orig_hasPrerollAds;
static BOOL ytm_hasPrerollAds(id self, SEL _cmd) {
    if (YTAdsOffEnabled()) return NO;
    return ((BOOL (*)(id, SEL))_orig_hasPrerollAds)(self, _cmd);
}

static IMP _orig_isCuepointAdsEnabled;
static BOOL ytm_isCuepointAdsEnabled(id self, SEL _cmd) {
    if (YTAdsOffEnabled()) return NO;
    return ((BOOL (*)(id, SEL))_orig_isCuepointAdsEnabled)(self, _cmd);
}

static IMP _orig_adsAllowReuse;
static BOOL ytm_adsAllowReuse(id self, SEL _cmd) {
    if (YTAdsOffEnabled()) return NO;
    return ((BOOL (*)(id, SEL))_orig_adsAllowReuse)(self, _cmd);
}

static IMP _orig_isDAIEnabledPlayback;
static BOOL ytm_isDAIEnabledPlayback(id self, SEL _cmd) {
    if (YTAdsOffEnabled()) return NO;
    return ((BOOL (*)(id, SEL))_orig_isDAIEnabledPlayback)(self, _cmd);
}

static IMP _orig_hasVideoAdTrackingRenderer;
static BOOL ytm_hasVideoAdTrackingRenderer(id self, SEL _cmd) {
    if (YTAdsOffEnabled()) return NO;
    return ((BOOL (*)(id, SEL))_orig_hasVideoAdTrackingRenderer)(self, _cmd);
}

// Chặn ở nguồn: ad break service không được request nữa. Callback error là
// block `void (^)(NSError *)`; gọi với nil để luồng player coi như "không có ad".
static IMP _orig_makeAdBreakRequest;
static void ytm_makeAdBreakRequest(id self, SEL _cmd, id req, id response, id error) {
    if (YTAdsOffEnabled()) {
        if (error) ((void (^)(id))error)(nil);
        return;
    }
    ((void (*)(id, SEL, id, id, id))_orig_makeAdBreakRequest)(self, _cmd, req, response, error);
}

// Bản retryEnabled: gọi qua bản 3 tham số gốc để tránh trùng logic.
static IMP _orig_makeAdBreakRequestRetry;
static void ytm_makeAdBreakRequestRetry(id self, SEL _cmd, id req, id response, id error, BOOL retry) {
    if (YTAdsOffEnabled()) {
        if (error) ((void (^)(id))error)(nil);
        return;
    }
    ((void (*)(id, SEL, id, id, id))_orig_makeAdBreakRequest)(self, _cmd, req, response, error);
}

// Pipeline slot quảng cáo: bỏ qua toàn bộ bước dựng layout.
static IMP _orig_buildAndRegister;
static void ytm_buildAndRegister(id self, SEL _cmd, id resp, id brk, id cpn, id pr, id intro, id slot, id layout) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id, id, id, id, id, id))_orig_buildAndRegister)(self, _cmd, resp, brk, cpn, pr, intro, slot, layout);
}

static IMP _orig_processThrottled;
static void ytm_processThrottled(id self, SEL _cmd, id resp, id cpn, id pr) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id, id))_orig_processThrottled)(self, _cmd, resp, cpn, pr);
}

static IMP _orig_addPlayerBytesSlots;
static void ytm_addPlayerBytesSlots(id self, SEL _cmd, id pr, id slots, id cpn, id intro, BOOL enabled) {
    if (YTAdsOffEnabled()) return;
    ((void (*)(id, SEL, id, id, id, id, BOOL))_orig_addPlayerBytesSlots)(self, _cmd, pr, slots, cpn, intro, enabled);
}

static IMP _orig_playerAdsDAI;
static id ytm_playerAdsDAI(id self, SEL _cmd, id resp) {
    if (YTAdsOffEnabled()) return nil;
    return ((id (*)(id, SEL, id))_orig_playerAdsDAI)(self, _cmd, resp);
}

static IMP _orig_playerAdsSlot;
static id ytm_playerAdsSlot(id self, SEL _cmd, id resp) {
    if (YTAdsOffEnabled()) return nil;
    return ((id (*)(id, SEL, id))_orig_playerAdsSlot)(self, _cmd, resp);
}

static IMP _orig_inPlayerSlot;
static id ytm_inPlayerSlot(id self, SEL _cmd, id bytesSlot, id brk, id cpn, id ad, id pr, id ctx) {
    if (YTAdsOffEnabled()) return nil;
    return ((id (*)(id, SEL, id, id, id, id, id, id))_orig_inPlayerSlot)(self, _cmd, bytesSlot, brk, cpn, ad, pr, ctx);
}

// ---------------------------------------------------------------------------
// Phát nền (khoá máy vẫn phát tiếng)
// ---------------------------------------------------------------------------
static IMP _orig_isBackgroundable;
static BOOL ytm_isBackgroundable(id self, SEL _cmd) {
    if (YTBackgroundEnabled()) return YES;
    return ((BOOL (*)(id, SEL))_orig_isBackgroundable)(self, _cmd);
}

static IMP _orig_isPlayableInBackground;
static BOOL ytm_isPlayableInBackground(id self, SEL _cmd) {
    if (YTBackgroundEnabled()) return YES;
    return ((BOOL (*)(id, SEL))_orig_isPlayableInBackground)(self, _cmd);
}

static IMP _orig_setAllowsBackgroundPlayback;
static void ytm_setAllowsBackgroundPlayback(id self, SEL _cmd, BOOL v) {
    if (YTBackgroundEnabled()) v = YES;
    ((void (*)(id, SEL, BOOL))_orig_setAllowsBackgroundPlayback)(self, _cmd, v);
}

// ---------------------------------------------------------------------------
// PiP (rời app thì thu nhỏ cửa sổ phát)
// ---------------------------------------------------------------------------
static IMP _orig_isPlayableInPiPBySettings;
static BOOL ytm_isPlayableInPiPBySettings(id self, SEL _cmd) {
    if (YTPiPEnabled()) return YES;
    return ((BOOL (*)(id, SEL))_orig_isPlayableInPiPBySettings)(self, _cmd);
}

static IMP _orig_isPlayableInPiP;
static BOOL ytm_isPlayableInPiP(id self, SEL _cmd) {
    if (YTPiPEnabled()) return YES;
    return ((BOOL (*)(id, SEL))_orig_isPlayableInPiP)(self, _cmd);
}

static IMP _orig_isPipOffByDefault;
static BOOL ytm_isPipOffByDefault(id self, SEL _cmd) {
    if (YTPiPEnabled()) return NO;
    return ((BOOL (*)(id, SEL))_orig_isPipOffByDefault)(self, _cmd);
}

static IMP _orig_isPlayableInPiPPlayerResponse;
static BOOL ytm_isPlayableInPiPPlayerResponse(id self, SEL _cmd) {
    if (YTPiPEnabled()) return YES;
    return ((BOOL (*)(id, SEL))_orig_isPlayableInPiPPlayerResponse)(self, _cmd);
}

// ---------------------------------------------------------------------------
// Bảng hook (thứ tự cố định — build.sh kiểm tra type encoding từ dump).
// ---------------------------------------------------------------------------
const YTMHook YTM_HOOKS[] = {
    // Chặn quảng cáo
    {"YTIPlayerResponse", "isMonetized", "B16@0:8", (IMP)ytm_isMonetized, &_orig_isMonetized, "yt: isMonetized=NO"},
    {"YTIPlayerResponse", "hasPrerollAds", "B16@0:8", (IMP)ytm_hasPrerollAds, &_orig_hasPrerollAds, "yt: hasPrerollAds=NO"},
    {"YTIPlayerResponse", "isCuepointAdsEnabled", "B16@0:8", (IMP)ytm_isCuepointAdsEnabled, &_orig_isCuepointAdsEnabled, "yt: cuepointAds=NO"},
    {"YTIPlayerResponse", "adsAllowReuse", "B16@0:8", (IMP)ytm_adsAllowReuse, &_orig_adsAllowReuse, "yt: adsAllowReuse=NO"},
    {"YTIPlayerResponse", "isDAIEnabledPlayback", "B16@0:8", (IMP)ytm_isDAIEnabledPlayback, &_orig_isDAIEnabledPlayback, "yt: DAI=NO"},
    {"YTIPlayerResponse", "hasVideoAdTrackingRenderer", "B16@0:8", (IMP)ytm_hasVideoAdTrackingRenderer, &_orig_hasVideoAdTrackingRenderer, "yt: videoAdRenderer=NO"},

    {"YTAdBreakServiceImpl", "makeAdBreakRequest:responseBlock:errorBlock:",
     "v40@0:8@16@?24@?32", (IMP)ytm_makeAdBreakRequest, &_orig_makeAdBreakRequest, "adb: chặn request"},
    {"YTAdBreakServiceImpl", "makeAdBreakRequest:responseBlock:errorBlock:retryEnabled:",
     "v44@0:8@16@?24@?32B40", (IMP)ytm_makeAdBreakRequestRetry, &_orig_makeAdBreakRequestRetry, "adb: chặn request retry"},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl",
     "buildAndRegisterSlotsFromAdBreakResponse:forAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:fromSlot:fromLayout:",
     "v72@0:8@16@24@32@40@48@56@64", (IMP)ytm_buildAndRegister, &_orig_buildAndRegister, "adb: bỏ dựng layout"},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "processThrottledAdBreakResponse:contentCPN:contentPlayerResponse:",
     "v40@0:8@16@24@32", (IMP)ytm_processThrottled, &_orig_processThrottled, "adb: bỏ throttled"},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl",
     "addPlayerBytesAndForecastingSlotsFromPlayerResponse:intoSlotArray:contentCPN:cachedAdIntro:isIosEnableAdBreakRequestSlot:",
     "v52@0:8@16@24@32@40B48", (IMP)ytm_addPlayerBytesSlots, &_orig_addPlayerBytesSlots, "adb: bỏ slot player-bytes"},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "playerAdsFromAdBreakResponse:",
     "@24@0:8@16", (IMP)ytm_playerAdsDAI, &_orig_playerAdsDAI, "adb: DAI playerAds=nil"},
    {"YTPlayerBytesSlotFulfillmentAdapter", "playerAdsFromAdBreakResponse:",
     "@24@0:8@16", (IMP)ytm_playerAdsSlot, &_orig_playerAdsSlot, "adb: playerAds=nil"},
    {"YTPlayerBytesLayoutEnteredOpportunityAdapterImpl",
     "inPlayerSlotFromPlayerBytesSlot:adBreak:contentCPN:ad:playerResponse:gaplessContext:",
     "@64@0:8@16@24@32@40@48@56", (IMP)ytm_inPlayerSlot, &_orig_inPlayerSlot, "adb: inPlayerSlot=nil"},

    // Phát nền
    {"YTIPlayabilityStatus", "isPlayableInBackground", "B16@0:8", (IMP)ytm_isPlayableInBackground, &_orig_isPlayableInBackground, "bg: playableInBackground=YES"},
    {"HAMPlayer", "setAllowsBackgroundPlayback:", "v20@0:8B16", (IMP)ytm_setAllowsBackgroundPlayback, &_orig_setAllowsBackgroundPlayback, "bg: HAMPlayer allows=YES"},
    {"YTBackgroundabilityPolicyImpl", "isBackgroundableByUserSettings", "B16@0:8", (IMP)ytm_isBackgroundable, &_orig_isBackgroundable, "bg: backgroundableBySettings=YES"},

    // PiP
    {"YTIPlayabilityStatus", "isPlayableInPictureInPicture", "B16@0:8", (IMP)ytm_isPlayableInPiP, &_orig_isPlayableInPiP, "pip: playableInPiP=YES"},
    {"YTPlayerResponse", "isPipOffByDefault", "B16@0:8", (IMP)ytm_isPipOffByDefault, &_orig_isPipOffByDefault, "pip: pipOffByDefault=NO"},
    {"YTPlayerResponse", "isPlayableInPictureInPicture", "B16@0:8", (IMP)ytm_isPlayableInPiPPlayerResponse, &_orig_isPlayableInPiPPlayerResponse, "pip: playerResponse PiP=YES"},
    {"YTBackgroundabilityPolicyImpl", "isPlayableInPictureInPictureByUserSettings", "B16@0:8", (IMP)ytm_isPlayableInPiPBySettings, &_orig_isPlayableInPiPBySettings, "pip: playableBySettings=YES"},
};
const int YTM_HOOK_COUNT = (int)(sizeof(YTM_HOOKS) / sizeof(YTM_HOOKS[0]));
