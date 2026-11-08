// TRACER tạm thời — SINH TỰ ĐỘNG từ trace_hooks.inc, đừng sửa tay.
// Log method void của pipeline ad để tìm đường ads thật (key `ad_trace`).
#import "common.h"
#import "hooks.h"
#import <objc/runtime.h>

static int g_traceHits = 0;
static const int g_traceMax = 200;

static IMP o0;
static IMP o1;
static IMP o2;
static IMP o3;
static IMP o4;
static IMP o5;
static IMP o6;
static IMP o7;
static IMP o8;
static IMP o9;
static IMP o10;
static IMP o11;
static IMP o12;
static IMP o13;
static IMP o14;
static IMP o15;
static IMP o16;
static IMP o17;
static IMP o18;
static IMP o19;
static IMP o20;
static IMP o21;
static IMP o22;
static IMP o23;
static IMP o24;
static IMP o25;
static IMP o26;
static IMP o27;
static IMP o28;
static IMP o29;
static IMP o30;
static IMP o31;
static IMP o32;
static IMP o33;
static IMP o34;
static IMP o35;
static IMP o36;
static IMP o37;
static IMP o38;
static IMP o39;
static IMP o40;
static IMP o41;
static IMP o42;
static IMP o43;
static IMP o44;
static IMP o45;
static IMP o46;
static IMP o47;
static IMP o48;
static IMP o49;
static IMP o50;
static IMP o51;
static IMP o52;
static IMP o53;
static IMP o54;
static IMP o55;
static IMP o56;
static IMP o57;
static IMP o58;
static IMP o59;
static IMP o60;
static IMP o61;
static IMP o62;
static IMP o63;
static IMP o64;
static IMP o65;
static IMP o66;
static IMP o67;
static IMP o68;
static IMP o69;
static IMP o70;
static IMP o71;
static IMP o72;
static IMP o73;
static IMP o74;
static IMP o75;
static IMP o76;
static IMP o77;
static IMP o78;
static IMP o79;
static IMP o80;
static IMP o81;
static IMP o82;
static IMP o83;
static IMP o84;
static IMP o85;
static IMP o86;
static IMP o87;
static IMP o88;
static IMP o89;
static IMP o90;
static IMP o91;
static IMP o92;
static IMP o93;
static IMP o94;
static IMP o95;
static IMP o96;
static IMP o97;
static IMP o98;
static IMP o99;
static IMP o100;
static IMP o101;
static IMP o102;
static IMP o103;
static IMP o104;
static IMP o105;
static IMP o106;
static IMP o107;
static IMP o108;
static IMP o109;
static IMP o110;
static IMP o111;
static IMP o112;
static IMP o113;
static IMP o114;
static IMP o115;
static IMP o116;
static IMP o117;
static IMP o118;
static IMP o119;
static IMP o120;
static IMP o121;
static IMP o122;
static IMP o123;
static IMP o124;
static IMP o125;
static IMP o126;
static IMP o127;
static IMP o128;
static IMP o129;
static IMP o130;
static IMP o131;
static IMP o132;
static IMP o133;
static IMP o134;
static IMP o135;
static IMP o136;
static IMP o137;
static IMP o138;
static IMP o139;
static IMP o140;
static IMP o141;
static IMP o142;
static IMP o143;
static IMP o144;
static IMP o145;
static IMP o146;
static IMP o147;
static IMP o148;
static IMP o149;
static IMP o150;
static IMP o151;
static IMP o152;
static IMP o153;
static IMP o154;
static IMP o155;
static IMP o156;
static IMP o157;
static IMP o158;
static IMP o159;
static IMP o160;
static IMP o161;
static IMP o162;
static IMP o163;
static IMP o164;
static IMP o165;
static IMP o166;
static IMP o167;
static IMP o168;
static IMP o169;
static IMP o170;
static IMP o171;
static IMP o172;
static IMP o173;
static IMP o174;
static IMP o175;
static IMP o176;
static IMP o177;
static IMP o178;
static IMP o179;
static IMP o180;
static IMP o181;
static IMP o182;
static IMP o183;
static IMP o184;
static IMP o185;
static IMP o186;
static IMP o187;
static IMP o188;
static IMP o189;
static IMP o190;
static IMP o191;
static IMP o192;
static IMP o193;
static IMP o194;
static IMP o195;
static IMP o196;
static IMP o197;
static IMP o198;
static IMP o199;
static IMP o200;
static IMP o201;
static IMP o202;
static IMP o203;
static IMP o204;
static IMP o205;
static IMP o206;
static IMP o207;
static IMP o208;
static IMP o209;
static IMP o210;
static IMP o211;
static IMP o212;
static IMP o213;
static IMP o214;
static IMP o215;
static IMP o216;
static IMP o217;
static IMP o218;
static IMP o219;
static IMP o220;
static IMP o221;
static IMP o222;
static IMP o223;
static IMP o224;
static IMP o225;
static IMP o226;
static IMP o227;
static IMP o228;
static IMP o229;
static IMP o230;
static IMP o231;
static IMP o232;
static IMP o233;
static IMP o234;
static IMP o235;
static IMP o236;
static IMP o237;
static IMP o238;
static IMP o239;
static IMP o240;
static IMP o241;
static IMP o242;
static IMP o243;
static IMP o244;
static IMP o245;
static IMP o246;
static IMP o247;
static IMP o248;
static IMP o249;
static IMP o250;
static IMP o251;
static IMP o252;
static IMP o253;
static IMP o254;
static IMP o255;
static IMP o256;
static IMP o257;
static IMP o258;
static IMP o259;
static IMP o260;
static IMP o261;
static IMP o262;
static IMP o263;
static IMP o264;
static IMP o265;
static IMP o266;
static IMP o267;
static IMP o268;
static IMP o269;
static IMP o270;
static IMP o271;
static IMP o272;
static IMP o273;
static IMP o274;
static IMP o275;
static IMP o276;
static IMP o277;
static IMP o278;
static IMP o279;
static IMP o280;
static IMP o281;
static IMP o282;
static IMP o283;
static IMP o284;
static IMP o285;
static IMP o286;
static IMP o287;
static IMP o288;
static IMP o289;
static IMP o290;
static IMP o291;
static IMP o292;
static IMP o293;
static IMP o294;
static IMP o295;
static IMP o296;
static IMP o297;
static IMP o298;
static IMP o299;
static IMP o300;
static IMP o301;
static IMP o302;
static IMP o303;
static IMP o304;
static IMP o305;
static IMP o306;
static IMP o307;
static IMP o308;
static IMP o309;
static IMP o310;
static IMP o311;
static IMP o312;
static IMP o313;
static IMP o314;
static IMP o315;
static IMP o316;
static IMP o317;
static IMP o318;
static IMP o319;
static IMP o320;
static IMP o321;
static IMP o322;
static IMP o323;
static IMP o324;
static IMP o325;
static IMP o326;
static IMP o327;
static IMP o328;
static IMP o329;
static IMP o330;
static IMP o331;
static IMP o332;
static IMP o333;
static IMP o334;
static IMP o335;
static IMP o336;
static IMP o337;
static IMP o338;
static IMP o339;
static IMP o340;
static IMP o341;
static IMP o342;
static IMP o343;
static IMP o344;
static IMP o345;
static IMP o346;
static IMP o347;
static IMP o348;
static IMP o349;
static IMP o350;
static IMP o351;
static IMP o352;
static IMP o353;
static IMP o354;
static IMP o355;
static IMP o356;
static IMP o357;
static IMP o358;
static IMP o359;
static IMP o360;
static IMP o361;
static IMP o362;
static IMP o363;
static IMP o364;
static IMP o365;
static IMP o366;
static IMP o367;
static IMP o368;
static IMP o369;
static IMP o370;
static IMP o371;
static IMP o372;
static IMP o373;
static IMP o374;
static IMP o375;
static IMP o376;
static IMP o377;
static IMP o378;
static IMP o379;
static IMP o380;
static IMP o381;
static IMP o382;
static IMP o383;
static IMP o384;
static IMP o385;
static IMP o386;
static IMP o387;
static IMP o388;
static IMP o389;
static IMP o390;
static IMP o391;
static IMP o392;
static IMP o393;
static IMP o394;
static IMP o395;
static IMP o396;
static IMP o397;
static IMP o398;
static IMP o399;
static IMP o400;
static IMP o401;
static IMP o402;
static IMP o403;
static IMP o404;
static IMP o405;
static IMP o406;
static IMP o407;
static IMP o408;
static IMP o409;
static IMP o410;
static IMP o411;
static IMP o412;
static IMP o413;
static IMP o414;
static IMP o415;
static IMP o416;
static IMP o417;
static IMP o418;
static IMP o419;
static IMP o420;
static IMP o421;
static IMP o422;
static IMP o423;
static IMP o424;
static IMP o425;
static IMP o426;
static IMP o427;
static IMP o428;
static IMP o429;
static IMP o430;
static IMP o431;
static IMP o432;
static IMP o433;
static IMP o434;
static IMP o435;
static IMP o436;
static IMP o437;
static IMP o438;
static IMP o439;
static IMP o440;
static IMP o441;
static IMP o442;
static IMP o443;
static IMP o444;
static IMP o445;
static IMP o446;
static IMP o447;
static IMP o448;
static IMP o449;
static IMP o450;
static IMP o451;
static IMP o452;
static IMP o453;
static IMP o454;
static IMP o455;
static IMP o456;
static IMP o457;
static IMP o458;
static IMP o459;
static IMP o460;
static IMP o461;
static IMP o462;
static IMP o463;
static IMP o464;
static IMP o465;
static IMP o466;
static IMP o467;
static IMP o468;
static IMP o469;
static IMP o470;
static IMP o471;
static IMP o472;
static IMP o473;
static IMP o474;
static IMP o475;
static IMP o476;
static IMP o477;
static IMP o478;
static IMP o479;
static IMP o480;
static IMP o481;
static IMP o482;
static IMP o483;
static IMP o484;
static IMP o485;
static IMP o486;
static IMP o487;
static IMP o488;
static IMP o489;
static IMP o490;
static IMP o491;
static IMP o492;

typedef struct { const char *cls; const char *sel; IMP hook; IMP *orig; } YTMTraceEntry;
static void t0(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | init"); }
    ((void (*)(id, SEL))o0)(self, _cmd);
}
static void t1(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | pauseAdBreakRequestSlotFromAdBreak:metadata:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o1)(self, _cmd, a1, a2, a3);
}
static void t2(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | pauseAdBreakRequestSlotFromAdBreak:slotID:metadata:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o2)(self, _cmd, a1, a2, a3, a4);
}
static void t3(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | adBreakRequestSlotFromAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:isGapless:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o3)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t4(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | adBreakRequestSlotFromAdThrottledSlot:"); }
    ((void (*)(id, SEL, id a1))o4)(self, _cmd, a1);
}
static void t5(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | gaplessPlayerBytesSlotFromAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o5)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t6(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | playerBytesSlotFromAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o6)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t7(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | playerBytesSlotFromAdThrottledSlot:"); }
    ((void (*)(id, SEL, id a1))o7)(self, _cmd, a1);
}
static void t8(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | playerBytesSlotFromAdBreakResponseForVod:forAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:adBreakRequestSlot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o8)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t9(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | forecastingSlotFromAdRenderer:adBreak:nextAdBreak:contentCPN:contentPlayerResponse:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o9)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t10(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | forecastingSlotFromAd:playerBytesSlot:offlineAdBreak:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o10)(self, _cmd, a1, a2, a3);
}
static void t11(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | belowPlayerSlotFromWatchNextPromise:instreamAd:playerBytesLayoutID:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o11)(self, _cmd, a1, a2, a3, a4);
}
static void t12(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | createBelowPlayerOrBelowPlayerImmersiveSlotFromAdSlotRenderer:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2))o12)(self, _cmd, a1, a2);
}
static void t13(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | belowPlayerSlotFromWatchNextResponse:playerBytesLayoutID:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o13)(self, _cmd, a1, a2, a3);
}
static void t14(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | belowPlayerImmersiveSlotFromWatchNextPromise:instreamAd:playerBytesLayoutID:belowPlayerSlotID:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o14)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t15(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | belowPlayerImmersiveSlotFromWatchNextResponse:playerBytesLayoutID:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o15)(self, _cmd, a1, a2, a3);
}
static void t16(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | fullscreenEngagementSlotFromAd:adBreakType:playerBytesLayoutID:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o16)(self, _cmd, a1, a2, a3, a4);
}
static void t17(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | inPlayerSlotFromPlayerBytesLayoutID:adBreak:contentCPN:playerResponse:gaplessContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o17)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t18(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | createInPlayerSlotFromAdSlotRenderer:adBreak:contentCPN:playerBytesLayoutID:playerResponse:gaplessContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o18)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t19(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | externallyManagedInPlayerSlotFromAd:"); }
    ((void (*)(id, SEL, id a1))o19)(self, _cmd, a1);
}
static void t20(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | slotFromAdSlotMetadata:controlFlowLayer:"); }
    ((void (*)(id, SEL, id a1, id a2))o20)(self, _cmd, a1, a2);
}
static void t21(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | externallyManagedSlotFromSlotLoggingData:controlFlowLayer:"); }
    ((void (*)(id, SEL, id a1, id a2))o21)(self, _cmd, a1, a2);
}
static void t22(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | belowPlayerDiscoverySlotFromPlayerResponse:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2))o22)(self, _cmd, a1, a2);
}
static void t23(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | discoveryPlaybackTrackingSlotFromPlayerResponse:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2))o23)(self, _cmd, a1, a2);
}
static void t24(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | DAIPlayerBytesSlotFromCuepoint:adBreak:adBreakIndex:contentCPN:contentPlayerResponse:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o24)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t25(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | nonDAIPlayerBytesSlotFromCuepoint:adBreak:adBreakIndex:contentCPN:fulfillmentStartTime:contentPlayerResponse:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o25)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t26(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | DAIAdBreakRequestSlotFromCuepoint:adBreak:adBreakIndex:contentCPN:contentPlayerResponse:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o26)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t27(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | discoveryInPlayerSlotFromCTAOverlayRenderer:contentCPN:associatedDiscoveryLayoutID:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o27)(self, _cmd, a1, a2, a3);
}
static void t28(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | discoveryBelowPlayerImmersiveSlotFromRenderer:onUIReadyCommand:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o28)(self, _cmd, a1, a2, a3);
}
static void t29(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | playerBytesSequenceItemSlotFromReelWatchEndpoint:"); }
    ((void (*)(id, SEL, id a1))o29)(self, _cmd, a1);
}
static void t30(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | sequenceItemInPlayerSlotFromPlayerBytesSlot:mediaLayout:reelWatchEndpoint:elementRenderer:adLayoutLoggingData:slotPhysicalPosition:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o30)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t31(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | createBelowPlayerImmersiveSlotFromAdSlotRenderer:contentCPN:adBreak:adBreakResponse:adBreakRequestSlot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o31)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t32(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | createPlayerBytesSlotFromAdSlotRenderer:contentCPN:playerResponse:adBreak:fulfilledLayout:DAIMetadata:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o32)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t33(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | sequenceItemPlayerUnderlaySlotFromPlayerBytesSlot:mediaLayout:reelWatchEndpoint:playerResponse:adSlotRenderer:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o33)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t34(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | sequenceItemPlayerUnderlaySlotFromPlayerBytesSlot:mediaLayout:reelWatchEndpoint:adSlotRenderer:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o34)(self, _cmd, a1, a2, a3, a4);
}
static void t35(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | sequenceItemPlayerSideSlotFromPlayerBytesSlot:mediaLayout:reelWatchEndpoint:adSlotRenderer:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o35)(self, _cmd, a1, a2, a3, a4);
}
static void t36(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | sequenceItemPlayerOrganicOverlaySlotFromWatchEndpoint:adSlotRenderer:"); }
    ((void (*)(id, SEL, id a1, id a2))o36)(self, _cmd, a1, a2);
}
static void t37(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | lockscreenSlotFromInstreamAd:playerBytesLayoutID:"); }
    ((void (*)(id, SEL, id a1, id a2))o37)(self, _cmd, a1, a2);
}
static void t38(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | playerBytesSequenceItemSlotFromImageAdEndpoint:"); }
    ((void (*)(id, SEL, id a1))o38)(self, _cmd, a1);
}
static void t39(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | sequenceItemInPlayerSlotFromSlot:mediaBreakLayout:imageAdEndpoint:slotPhysicalPosition:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o39)(self, _cmd, a1, a2, a3, a4);
}
static void t40(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | HalftimePrerollPlayerBytesSlot:contentCPN:contentPlayerResponse:playbackData:cachedAdIntro:YTDAIMetadata:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o40)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t41(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | gaplessPlayerBytesSlotFromAdSlotRenderer:contentCPN:contentPlayerResponse:adBreak:fulfilledLayout:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o41)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t42(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | playbackIntervalEnd:videoLength:"); }
    ((void (*)(id, SEL, id a1, id a2))o42)(self, _cmd, a1, a2);
}
static void t43(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | stitchedDIBSInsertionTimeFromAdSlotRenderer:playbackStart:"); }
    ((void (*)(id, SEL, id a1, id a2))o43)(self, _cmd, a1, a2);
}
static void t44(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | createTriggerFromTrigger:slotID:"); }
    ((void (*)(id, SEL, id a1, id a2))o44)(self, _cmd, a1, a2);
}
static void t45(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | createExpirationTriggersForSlotID:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2))o45)(self, _cmd, a1, a2);
}
static void t46(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | createExpirationTriggersForSlotIDForDAI:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2))o46)(self, _cmd, a1, a2);
}
static void t47(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | metadataFromContentCPN:contentPlayerResponse:adBreak:cachedAdIntro:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o47)(self, _cmd, a1, a2, a3, a4);
}
static void t48(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | metadataFromContentCPN:contentPlayerResponse:adBreak:cachedAdIntro:gaplessContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o48)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t49(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | metadataFromContentCPN:contentPlayerResponse:adBreak:cachedAdIntro:gaplessContext:midrollCueRange:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o49)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t50(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | forecastingMetadataFromContentCPN:forecastingAd:adBreak:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o50)(self, _cmd, a1, a2, a3);
}
static void t51(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | belowPlayerMetadataFromWatchNextPromise:playerBytesLayoutID:instreamAd:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o51)(self, _cmd, a1, a2, a3);
}
static void t52(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | belowPlayerImmersiverMetadataFromWatchNextPromise:playerBytesLayoutID:belowPlayerSlotID:instreamAd:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o52)(self, _cmd, a1, a2, a3, a4);
}
static void t53(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | fullscreenEngagementMetadataFromAd:playerBytesLayoutID:"); }
    ((void (*)(id, SEL, id a1, id a2))o53)(self, _cmd, a1, a2);
}
static void t54(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | metadataFromPlayerResponse:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2))o54)(self, _cmd, a1, a2);
}
static void t55(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | lockscreenMetadataFromAd:playerBytesLayoutID:"); }
    ((void (*)(id, SEL, id a1, id a2))o55)(self, _cmd, a1, a2);
}
static void t56(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | shouldEnableTimelineSlotForAdBreak:"); }
    ((void (*)(id, SEL, id a1))o56)(self, _cmd, a1);
}
static void t57(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | forecastingSlotFromAd:adBreak:adBreakStartTime:adBreakEndTime:contentCPN:adSlotLoggingData:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o57)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t58(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | externallyManagedSlotFromAdSlotRenderer:clientMetadata:fulfilledLayout:clientSlotID:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o58)(self, _cmd, a1, a2, a3, a4);
}
static void t59(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTSlotFactoryImpl | playerBytesSequenceItemTrackingSlotFromAdSlotRenderer:reelWatchEndpoint:fulfilledLayout:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o59)(self, _cmd, a1, a2, a3);
}
static void t60(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesLayoutEnteredOpportunityAdapterImpl | init"); }
    ((void (*)(id, SEL))o60)(self, _cmd);
}
static void t61(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesLayoutEnteredOpportunityAdapterImpl | didEnterLayout:forSlot:"); }
    ((void (*)(id, SEL, id a1, id a2))o61)(self, _cmd, a1, a2);
}
static void t62(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesLayoutEnteredOpportunityAdapterImpl | didEnterMediaLayout:forPlayerBytesSlot:"); }
    ((void (*)(id, SEL, id a1, id a2))o62)(self, _cmd, a1, a2);
}
static void t63(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesLayoutEnteredOpportunityAdapterImpl | maybeBuildAndScheduleInPlayerSlotsFromPlayerBytesSlot:layout:"); }
    ((void (*)(id, SEL, id a1, id a2))o63)(self, _cmd, a1, a2);
}
static void t64(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesLayoutEnteredOpportunityAdapterImpl | inPlayerSlotFromPlayerBytesSlot:adBreak:contentCPN:ad:playerResponse:gaplessContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o64)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t65(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesLayoutEnteredOpportunityAdapterImpl | inPlayerAdSlotRendererMatchingTriggeringID:adSlotsArray:"); }
    ((void (*)(id, SEL, id a1, id a2))o65)(self, _cmd, a1, a2);
}
static void t66(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesLayoutEnteredOpportunityAdapterImpl | adSlotRendererList:"); }
    ((void (*)(id, SEL, id a1))o66)(self, _cmd, a1);
}
static void t67(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | init"); }
    ((void (*)(id, SEL))o67)(self, _cmd);
}
static void t68(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | parseCachedAdsFromAdBreakResponse:adRequestID:serviceID:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o68)(self, _cmd, a1, a2, a3);
}
static void t69(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onPrefetchInstructionUpdate:"); }
    ((void (*)(id, SEL, id a1))o69)(self, _cmd, a1);
}
static void t70(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onPrefetchServiceShouldExpire:"); }
    ((void (*)(id, SEL, id a1))o70)(self, _cmd, a1);
}
static void t71(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | requestCacheSelection:selectionInstruction:"); }
    ((void (*)(id, SEL, id a1, id a2))o71)(self, _cmd, a1, a2);
}
static void t72(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdRequestScheduled:adRequestID:"); }
    ((void (*)(id, SEL, id a1, id a2))o72)(self, _cmd, a1, a2);
}
static void t73(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdRequestInFlight:adRequestID:"); }
    ((void (*)(id, SEL, id a1, id a2))o73)(self, _cmd, a1, a2);
}
static void t74(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdResponseSucceeded:adRequestID:adBreakResponse:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o74)(self, _cmd, a1, a2, a3);
}
static void t75(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdResponseFailed:adRequestID:error:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o75)(self, _cmd, a1, a2, a3);
}
static void t76(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdRequestCancelled:adRequestID:"); }
    ((void (*)(id, SEL, id a1, id a2))o76)(self, _cmd, a1, a2);
}
static void t77(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | getAdRequestStateForServiceID:adRequestID:"); }
    ((void (*)(id, SEL, id a1, id a2))o77)(self, _cmd, a1, a2);
}
static void t78(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onPrefetchServiceExpired:"); }
    ((void (*)(id, SEL, id a1))o78)(self, _cmd, a1);
}
static void t79(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdRequestScheduledLocked:adRequestID:"); }
    ((void (*)(id, SEL, id a1, id a2))o79)(self, _cmd, a1, a2);
}
static void t80(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdRequestInFlightLocked:adRequestID:"); }
    ((void (*)(id, SEL, id a1, id a2))o80)(self, _cmd, a1, a2);
}
static void t81(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | ingestCachedAdLocked:intoServiceObjectID:logger:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o81)(self, _cmd, a1, a2, a3);
}
static void t82(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdResponseSucceededLocked:adRequestID:adBreakResponse:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o82)(self, _cmd, a1, a2, a3);
}
static void t83(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdResponseFailedLocked:adRequestID:error:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o83)(self, _cmd, a1, a2, a3);
}
static void t84(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onAdRequestCancelledLocked:adRequestID:"); }
    ((void (*)(id, SEL, id a1, id a2))o84)(self, _cmd, a1, a2);
}
static void t85(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | onPrefetchServiceShouldExpireLocked:"); }
    ((void (*)(id, SEL, id a1))o85)(self, _cmd, a1);
}
static void t86(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | clientAdSelectionInfoMacrosWithSourceAdRequestID:"); }
    ((void (*)(id, SEL, id a1))o86)(self, _cmd, a1);
}
static void t87(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | tryPing:sourceAdRequestID:"); }
    ((void (*)(id, SEL, id a1, id a2))o87)(self, _cmd, a1, a2);
}
static void t88(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | logServiceEvent:fetchJobID:event:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o88)(self, _cmd, a1, a2, a3);
}
static void t89(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | logServiceEvent:fetchJobID:event:error:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o89)(self, _cmd, a1, a2, a3, a4);
}
static void t90(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | disposeInternal"); }
    ((void (*)(id, SEL))o90)(self, _cmd);
}
static void t91(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | serviceRegistry"); }
    ((void (*)(id, SEL))o91)(self, _cmd);
}
static void t92(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | serialQueue"); }
    ((void (*)(id, SEL))o92)(self, _cmd);
}
static void t93(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | setSerialQueue:"); }
    ((void (*)(id, SEL, id a1))o93)(self, _cmd, a1);
}
static void t94(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | pingService"); }
    ((void (*)(id, SEL))o94)(self, _cmd);
}
static void t95(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsRequestAndCacheService | setPingService:"); }
    ((void (*)(id, SEL, id a1))o95)(self, _cmd, a1);
}
static void t96(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | initWithServiceRegistryScope:overlayManager:delegate:parentResponder:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o96)(self, _cmd, a1, a2, a3, a4);
}
static void t97(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | initWithServiceRegistryScope:overlayFactory:delegate:parentResponder:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o97)(self, _cmd, a1, a2, a3, a4);
}
static void t98(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | init"); }
    ((void (*)(id, SEL))o98)(self, _cmd);
}
static void t99(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | setSinglePlayerBytesEventListener:"); }
    ((void (*)(id, SEL, id a1))o99)(self, _cmd, a1);
}
static void t100(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | adsCuepointObserver"); }
    ((void (*)(id, SEL))o100)(self, _cmd);
}
static void t101(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | supportsPlaybackForContentPlayerResponse:"); }
    ((void (*)(id, SEL, id a1))o101)(self, _cmd, a1);
}
static void t102(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | playbackControllerWillActivatePrebufferingAdTransitionWithBufferedMediaTime:"); }
    ((void (*)(id, SEL, id a1))o102)(self, _cmd, a1);
}
static void t103(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | acquireOverlay"); }
    ((void (*)(id, SEL))o103)(self, _cmd);
}
static void t104(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | startOverlayForAd:"); }
    ((void (*)(id, SEL, id a1))o104)(self, _cmd, a1);
}
static void t105(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | prepareOverlays"); }
    ((void (*)(id, SEL))o105)(self, _cmd);
}
static void t106(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | setOverlayFactory:"); }
    ((void (*)(id, SEL, id a1))o106)(self, _cmd, a1);
}
static void t107(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | getPrerollMode"); }
    ((void (*)(id, SEL))o107)(self, _cmd);
}
static void t108(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | startPrerollAdBreak"); }
    ((void (*)(id, SEL))o108)(self, _cmd);
}
static void t109(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | startPostrollAdBreak"); }
    ((void (*)(id, SEL))o109)(self, _cmd);
}
static void t110(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | setContentSingleVideo:playbackTimeline:"); }
    ((void (*)(id, SEL, id a1, id a2))o110)(self, _cmd, a1, a2);
}
static void t111(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | didStopPlayingAd"); }
    ((void (*)(id, SEL))o111)(self, _cmd);
}
static void t112(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | didSkipOrCompleteAd:"); }
    ((void (*)(id, SEL, id a1))o112)(self, _cmd, a1);
}
static void t113(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | didFailToPlayAdWithPlaybackError:"); }
    ((void (*)(id, SEL, id a1))o113)(self, _cmd, a1);
}
static void t114(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | didPressSkipAdWithTouchPoint:"); }
    ((void (*)(id, SEL, id a1))o114)(self, _cmd, a1);
}
static void t115(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | willPlayNewVideoWithAutoplay:"); }
    ((void (*)(id, SEL, id a1))o115)(self, _cmd, a1);
}
static void t116(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | doneWithCurrentAd"); }
    ((void (*)(id, SEL))o116)(self, _cmd);
}
static void t117(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | reset"); }
    ((void (*)(id, SEL))o117)(self, _cmd);
}
static void t118(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | currentAd"); }
    ((void (*)(id, SEL))o118)(self, _cmd);
}
static void t119(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | lastAdTotalMediaTime"); }
    ((void (*)(id, SEL))o119)(self, _cmd);
}
static void t120(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | lastAdVideoID"); }
    ((void (*)(id, SEL))o120)(self, _cmd);
}
static void t121(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | instreamForcedAdParameters"); }
    ((void (*)(id, SEL))o121)(self, _cmd);
}
static void t122(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | setPlayerViewLayout:"); }
    ((void (*)(id, SEL, id a1))o122)(self, _cmd, a1);
}
static void t123(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | externalPlaybackActiveDidChange:"); }
    ((void (*)(id, SEL, id a1))o123)(self, _cmd, a1);
}
static void t124(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | debugParameters"); }
    ((void (*)(id, SEL))o124)(self, _cmd);
}
static void t125(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | supportsSkippingToUpcomingPlayback"); }
    ((void (*)(id, SEL))o125)(self, _cmd);
}
static void t126(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | supportsOverlaysManagementByAds"); }
    ((void (*)(id, SEL))o126)(self, _cmd);
}
static void t127(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | setAdsManageOverlayLifecycleEnabled:"); }
    ((void (*)(id, SEL, id a1))o127)(self, _cmd, a1);
}
static void t128(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | playbackContextForAd"); }
    ((void (*)(id, SEL))o128)(self, _cmd);
}
static void t129(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | autoplayEnabled"); }
    ((void (*)(id, SEL))o129)(self, _cmd);
}
static void t130(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | isOfflinePlayback"); }
    ((void (*)(id, SEL))o130)(self, _cmd);
}
static void t131(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | isPodcastPlayback"); }
    ((void (*)(id, SEL))o131)(self, _cmd);
}
static void t132(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | playerViewLayout"); }
    ((void (*)(id, SEL))o132)(self, _cmd);
}
static void t133(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | contentPlaybackInfoAvailable"); }
    ((void (*)(id, SEL))o133)(self, _cmd);
}
static void t134(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | serviceAvailableForPlayerBytes"); }
    ((void (*)(id, SEL))o134)(self, _cmd);
}
static void t135(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | overlayInAdInterruptIsDisabled"); }
    ((void (*)(id, SEL))o135)(self, _cmd);
}
static void t136(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | setPrerollModeWithMode:"); }
    ((void (*)(id, SEL, id a1))o136)(self, _cmd, a1);
}
static void t137(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | singlePlayerBytesLayoutRenderingAdapter:didRequestPlayAnAdInterrupt:forSlot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o137)(self, _cmd, a1, a2, a3);
}
static void t138(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | registerContentVideoPrerollSlot:postrollSlot:midrollSlots:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o138)(self, _cmd, a1, a2, a3, a4);
}
static void t139(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | registerContentVideoAdBreakRequestSlot:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2))o139)(self, _cmd, a1, a2);
}
static void t140(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | addNewMidrollSlotDueToThrottling:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2))o140)(self, _cmd, a1, a2);
}
static void t141(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | isAirPlayActive"); }
    ((void (*)(id, SEL))o141)(self, _cmd);
}
static void t142(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | playerVisibility"); }
    ((void (*)(id, SEL))o142)(self, _cmd);
}
static void t143(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | midrollIndex"); }
    ((void (*)(id, SEL))o143)(self, _cmd);
}
static void t144(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | contentVideo"); }
    ((void (*)(id, SEL))o144)(self, _cmd);
}
static void t145(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | isStartUpState"); }
    ((void (*)(id, SEL))o145)(self, _cmd);
}
static void t146(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | CPNForCurrentPlayback"); }
    ((void (*)(id, SEL))o146)(self, _cmd);
}
static void t147(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | addContentPlaybackEventListener:"); }
    ((void (*)(id, SEL, id a1))o147)(self, _cmd, a1);
}
static void t148(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | removeContentPlaybackEventListener:"); }
    ((void (*)(id, SEL, id a1))o148)(self, _cmd, a1);
}
static void t149(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | addAPIListener:"); }
    ((void (*)(id, SEL, id a1))o149)(self, _cmd, a1);
}
static void t150(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | removeAPIListener:"); }
    ((void (*)(id, SEL, id a1))o150)(self, _cmd, a1);
}
static void t151(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | addLiveMidrollStatusFromSlot:"); }
    ((void (*)(id, SEL, id a1))o151)(self, _cmd, a1);
}
static void t152(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | prebufferAdInterrupt:atMediaTime:"); }
    ((void (*)(id, SEL, id a1, id a2))o152)(self, _cmd, a1, a2);
}
static void t153(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | cancelPrebufferingAdInterrupt:"); }
    ((void (*)(id, SEL, id a1))o153)(self, _cmd, a1);
}
static void t154(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | makeCompletionRequestWithAd:completeType:"); }
    ((void (*)(id, SEL, id a1, id a2))o154)(self, _cmd, a1, a2);
}
static void t155(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | adBreakTrackingControllerFromAdBreak:slot:layout:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o155)(self, _cmd, a1, a2, a3);
}
static void t156(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | adTrackingControllerFromAd:adBreak:slot:layout:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o156)(self, _cmd, a1, a2, a3, a4);
}
static void t157(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | discoveryAdPingControllerFromPlayerResponse:videoAdTracking:progressCommands:slot:layout:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o157)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t158(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | responder"); }
    ((void (*)(id, SEL))o158)(self, _cmd);
}
static void t159(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | didUnscheduleSlot:"); }
    ((void (*)(id, SEL, id a1))o159)(self, _cmd, a1);
}
static void t160(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | singleVideo:currentVideoTimeDidChange:"); }
    ((void (*)(id, SEL, id a1, id a2))o160)(self, _cmd, a1, a2);
}
static void t161(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | singleVideo:didFailWithError:"); }
    ((void (*)(id, SEL, id a1, id a2))o161)(self, _cmd, a1, a2);
}
static void t162(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | singleVideo:mediaStateDidChangeFromState:toState:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o162)(self, _cmd, a1, a2, a3);
}
static void t163(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | singleVideo:mediaStateDidChangeFromState:toState:stoppageReason:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o163)(self, _cmd, a1, a2, a3, a4);
}
static void t164(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | potentiallyMutatedSingleVideo:mediaStateDidChangeFromState:toState:stoppageReason:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o164)(self, _cmd, a1, a2, a3, a4);
}
static void t165(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | singleVideo:lifecycleStateDidChangeFromState:toState:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o165)(self, _cmd, a1, a2, a3);
}
static void t166(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | adDidShowSkip"); }
    ((void (*)(id, SEL))o166)(self, _cmd);
}
static void t167(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | adDidSkipWithTouchPoint:"); }
    ((void (*)(id, SEL, id a1))o167)(self, _cmd, a1);
}
static void t168(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | adDidMuteWithTouchPoint:"); }
    ((void (*)(id, SEL, id a1))o168)(self, _cmd, a1);
}
static void t169(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | adDidTapthroughWithTouchPoint:"); }
    ((void (*)(id, SEL, id a1))o169)(self, _cmd, a1);
}
static void t170(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | adSlotDidComplete"); }
    ((void (*)(id, SEL))o170)(self, _cmd);
}
static void t171(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | contentVideoThumbnails"); }
    ((void (*)(id, SEL))o171)(self, _cmd);
}
static void t172(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | contentVideoTitle"); }
    ((void (*)(id, SEL))o172)(self, _cmd);
}
static void t173(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | newActiveViewVideoMonitorWithContentPlayerResponse:trafficType:"); }
    ((void (*)(id, SEL, id a1, id a2))o173)(self, _cmd, a1, a2);
}
static void t174(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | videoAdTrackingControllerWithAd:adBreak:slot:layout:activeViewVideoMonitor:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o174)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t175(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | seekToVideoTime:"); }
    ((void (*)(id, SEL, id a1))o175)(self, _cmd, a1);
}
static void t176(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | seekToLiveHead"); }
    ((void (*)(id, SEL))o176)(self, _cmd);
}
static void t177(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | createVirtualVideoWithCPNs:"); }
    ((void (*)(id, SEL, id a1))o177)(self, _cmd, a1);
}
static void t178(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | prerollAdBreakStatus"); }
    ((void (*)(id, SEL))o178)(self, _cmd);
}
static void t179(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | postrollAdBreakStatus"); }
    ((void (*)(id, SEL))o179)(self, _cmd);
}
static void t180(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | inPlayerExternallyManagedSlotAdapter"); }
    ((void (*)(id, SEL))o180)(self, _cmd);
}
static void t181(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | prepareAdInterrupt:"); }
    ((void (*)(id, SEL, id a1))o181)(self, _cmd, a1);
}
static void t182(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | currentContentCPN"); }
    ((void (*)(id, SEL))o182)(self, _cmd);
}
static void t183(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | checkAdBreakStatus:andMaybeFinishAdBreakWithBreakType:"); }
    ((void (*)(id, SEL, id a1, id a2))o183)(self, _cmd, a1, a2);
}
static void t184(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | slotDidUnscheduleForAdBreakStatus:andMaybeEndWithBreakType:"); }
    ((void (*)(id, SEL, id a1, id a2))o184)(self, _cmd, a1, a2);
}
static void t185(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | adBreakRequestSlotDidUnscheduleForAdBreakStatus:andMaybeEndWithBreakType:"); }
    ((void (*)(id, SEL, id a1, id a2))o185)(self, _cmd, a1, a2);
}
static void t186(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | doneWithPlayerBytesSlotWithBreakType:"); }
    ((void (*)(id, SEL, id a1))o186)(self, _cmd, a1);
}
static void t187(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | breakTypeStringForBreakType:"); }
    ((void (*)(id, SEL, id a1))o187)(self, _cmd, a1);
}
static void t188(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | startObservingAdSingleVideo:"); }
    ((void (*)(id, SEL, id a1))o188)(self, _cmd, a1);
}
static void t189(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | updateStateForNewActiveAdSingleVideo:"); }
    ((void (*)(id, SEL, id a1))o189)(self, _cmd, a1);
}
static void t190(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | activateOverlayCoordinator"); }
    ((void (*)(id, SEL))o190)(self, _cmd);
}
static void t191(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | currentAdRequestConfig"); }
    ((void (*)(id, SEL))o191)(self, _cmd);
}
static void t192(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | newActiveViewVideoMonitorWithTrafficType:"); }
    ((void (*)(id, SEL, id a1))o192)(self, _cmd, a1);
}
static void t193(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | isInlineMutedPlaybackWithOverlayFactory:"); }
    ((void (*)(id, SEL, id a1))o193)(self, _cmd, a1);
}
static void t194(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | retrieveMidrollStatusForSlot:"); }
    ((void (*)(id, SEL, id a1))o194)(self, _cmd, a1);
}
static void t195(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | activeContentSingleVideo:mediaStateDidChangeToState:"); }
    ((void (*)(id, SEL, id a1, id a2))o195)(self, _cmd, a1, a2);
}
static void t196(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | activeAdSingleVideo:mediaStateDidChangeToState:"); }
    ((void (*)(id, SEL, id a1, id a2))o196)(self, _cmd, a1, a2);
}
static void t197(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | deactivateOverlayCoordinator"); }
    ((void (*)(id, SEL))o197)(self, _cmd);
}
static void t198(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | logOverlayErrorWithDescription:"); }
    ((void (*)(id, SEL, id a1))o198)(self, _cmd, a1);
}
static void t199(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | lastAdsState"); }
    ((void (*)(id, SEL))o199)(self, _cmd);
}
static void t200(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | currentAdsState"); }
    ((void (*)(id, SEL))o200)(self, _cmd);
}
static void t201(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowPlaybackCoordinator | parentResponder"); }
    ((void (*)(id, SEL))o201)(self, _cmd);
}
static void t202(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | init"); }
    ((void (*)(id, SEL))o202)(self, _cmd);
}
static void t203(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | fulfillmentAdapter:didFillSlot:withLayout:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o203)(self, _cmd, a1, a2, a3);
}
static void t204(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | fulfillmentAdapter:didFailForSlot:errorMessage:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o204)(self, _cmd, a1, a2, a3);
}
static void t205(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | fulfillmentAdapter:didCancelFulfillmentForSlot:"); }
    ((void (*)(id, SEL, id a1, id a2))o205)(self, _cmd, a1, a2);
}
static void t206(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | layoutRenderingAdapter:didEnterLayoutForSlot:layout:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o206)(self, _cmd, a1, a2, a3);
}
static void t207(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | layoutRenderingAdapter:didExitLayoutForSlot:layout:layoutExitReason:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o207)(self, _cmd, a1, a2, a3, a4);
}
static void t208(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | layoutRenderingAdapter:didFailForSlot:layout:errorType:errorMessage:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o208)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t209(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | layoutRenderingAdapter:message:slot:layout:errorType:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o209)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t210(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externalContextForSlot:"); }
    ((void (*)(id, SEL, id a1))o210)(self, _cmd, a1);
}
static void t211(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | onSlotEntered:"); }
    ((void (*)(id, SEL, id a1))o211)(self, _cmd, a1);
}
static void t212(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | onSlotExited:"); }
    ((void (*)(id, SEL, id a1))o212)(self, _cmd, a1);
}
static void t213(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | onLayoutEntered:layout:"); }
    ((void (*)(id, SEL, id a1, id a2))o213)(self, _cmd, a1, a2);
}
static void t214(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | onLayoutExitedWithSlot:layout:layoutExitReason:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o214)(self, _cmd, a1, a2, a3);
}
static void t215(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | onLayoutErrorWithSlot:layout:exception:type:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o215)(self, _cmd, a1, a2, a3, a4);
}
static void t216(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | slotAdapter:didEnterSlot:"); }
    ((void (*)(id, SEL, id a1, id a2))o216)(self, _cmd, a1, a2);
}
static void t217(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | slotAdapter:didExitSlot:"); }
    ((void (*)(id, SEL, id a1, id a2))o217)(self, _cmd, a1, a2);
}
static void t218(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | slotAdapter:didFailForSlot:errorType:errorMessage:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o218)(self, _cmd, a1, a2, a3, a4);
}
static void t219(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | slotOpportunityAdapter:didReceiveOpportunity:externalContext:fromSlot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o219)(self, _cmd, a1, a2, a3, a4);
}
static void t220(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | slotOpportunityAdapter:didProcessOpportunity:withSlots:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o220)(self, _cmd, a1, a2, a3, a4);
}
static void t221(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | lifecycleDidStartForAdSlots:context:"); }
    ((void (*)(id, SEL, id a1, id a2))o221)(self, _cmd, a1, a2);
}
static void t222(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | registerAndScheduleV2Slot:adOpportunityContext:"); }
    ((void (*)(id, SEL, id a1, id a2))o222)(self, _cmd, a1, a2);
}
static void t223(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | registerAndScheduleV2Layout:adOpportunityContext:"); }
    ((void (*)(id, SEL, id a1, id a2))o223)(self, _cmd, a1, a2);
}
static void t224(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | triggerAdapter:didActivateTriggers:"); }
    ((void (*)(id, SEL, id a1, id a2))o224)(self, _cmd, a1, a2);
}
static void t225(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didReceiveExternallyManagedSlot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o225)(self, _cmd, a1, a2, a3);
}
static void t226(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didScheduleExternallyManagedSlot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o226)(self, _cmd, a1, a2, a3);
}
static void t227(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didUnscheduleExternallyManagedSlot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o227)(self, _cmd, a1, a2, a3);
}
static void t228(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didEnterExternallyManagedSlot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o228)(self, _cmd, a1, a2, a3);
}
static void t229(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didExitExternallyManagedSlot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o229)(self, _cmd, a1, a2, a3);
}
static void t230(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didReceiveExternallyManagedLayout:forSlot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o230)(self, _cmd, a1, a2, a3, a4);
}
static void t231(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didScheduleExternallyManagedLayout:forSlot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o231)(self, _cmd, a1, a2, a3, a4);
}
static void t232(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didUnscheduleExternallyManagedLayout:forSlot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o232)(self, _cmd, a1, a2, a3);
}
static void t233(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didEnterExternallyManagedLayout:forSlot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o233)(self, _cmd, a1, a2, a3, a4);
}
static void t234(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:didExitExternallyManagedLayout:forSlot:exitReason:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o234)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t235(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | externallyManagedSlotAdapter:message:slot:layout:errorType:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o235)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t236(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | appWillResignActive"); }
    ((void (*)(id, SEL))o236)(self, _cmd);
}
static void t237(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | maybeUnscheduleSlot:isDueToError:"); }
    ((void (*)(id, SEL, id a1, id a2))o237)(self, _cmd, a1, a2);
}
static void t238(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | retrieveRenderingEventThrottlingTrackerForSlot:tier:"); }
    ((void (*)(id, SEL, id a1, id a2))o238)(self, _cmd, a1, a2);
}
static void t239(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | renderingEventThrottlingStatusWithSlot:tier:"); }
    ((void (*)(id, SEL, id a1, id a2))o239)(self, _cmd, a1, a2);
}
static void t240(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | incrementRenderingEventCountWithSlot:tier:"); }
    ((void (*)(id, SEL, id a1, id a2))o240)(self, _cmd, a1, a2);
}
static void t241(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | setThrottlingCapacity:forSlotType:"); }
    ((void (*)(id, SEL, id a1, id a2))o241)(self, _cmd, a1, a2);
}
static void t242(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | resetThrottlingCapacityForSlotType:"); }
    ((void (*)(id, SEL, id a1))o242)(self, _cmd, a1);
}
static void t243(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | getThrottlingCapacityForSlot:"); }
    ((void (*)(id, SEL, id a1))o243)(self, _cmd, a1);
}
static void t244(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | performSlotEnteredActions:"); }
    ((void (*)(id, SEL, id a1))o244)(self, _cmd, a1);
}
static void t245(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | performSlotExitedActions:"); }
    ((void (*)(id, SEL, id a1))o245)(self, _cmd, a1);
}
static void t246(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | performLayoutExitedActionsForSlot:layout:exitReason:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o246)(self, _cmd, a1, a2, a3);
}
static void t247(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | performLayoutEnteredActionsForSlot:layout:"); }
    ((void (*)(id, SEL, id a1, id a2))o247)(self, _cmd, a1, a2);
}
static void t248(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | unblockTriggerReceptionForSlot:dueToError:"); }
    ((void (*)(id, SEL, id a1, id a2))o248)(self, _cmd, a1, a2);
}
static void t249(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | handleActivationForTriggerBundles:"); }
    ((void (*)(id, SEL, id a1))o249)(self, _cmd, a1);
}
static void t250(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | onServerTriggersActivated:"); }
    ((void (*)(id, SEL, id a1))o250)(self, _cmd, a1);
}
static void t251(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | scheduleSlot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2))o251)(self, _cmd, a1, a2);
}
static void t252(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | unscheduleSlot:isDueToError:"); }
    ((void (*)(id, SEL, id a1, id a2))o252)(self, _cmd, a1, a2);
}
static void t253(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | onLayoutUnscheduled:layout:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o253)(self, _cmd, a1, a2, a3);
}
static void t254(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | maybeStartRenderingLayoutForSlot:"); }
    ((void (*)(id, SEL, id a1))o254)(self, _cmd, a1);
}
static void t255(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | processLayoutExitTriggersWithTriggerCategory:inTriggerBundles:dueToLayoutExitReason:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o255)(self, _cmd, a1, a2, a3);
}
static void t256(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | processLayoutExitServerTriggersWithTriggerCategory:inTriggerBundles:dueToLayoutExitReason:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o256)(self, _cmd, a1, a2, a3);
}
static void t257(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | processExpirationTriggersInTriggerBundles:"); }
    ((void (*)(id, SEL, id a1))o257)(self, _cmd, a1);
}
static void t258(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | processExpirationServerTriggersInTriggerBundles:"); }
    ((void (*)(id, SEL, id a1))o258)(self, _cmd, a1);
}
static void t259(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | processFulfillmentTriggersInTriggerBundles:"); }
    ((void (*)(id, SEL, id a1))o259)(self, _cmd, a1);
}
static void t260(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | processEntryTriggersInTriggerBundles:"); }
    ((void (*)(id, SEL, id a1))o260)(self, _cmd, a1);
}
static void t261(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | processEntryServerTriggersInTriggerBundles:"); }
    ((void (*)(id, SEL, id a1))o261)(self, _cmd, a1);
}
static void t262(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | stopRenderingLayoutWithSlot:layout:layoutExitReason:isDueToError:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o262)(self, _cmd, a1, a2, a3, a4);
}
static void t263(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | exitSlot:isDueToError:"); }
    ((void (*)(id, SEL, id a1, id a2))o263)(self, _cmd, a1, a2);
}
static void t264(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | logLayoutExitReason:slot:layout:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o264)(self, _cmd, a1, a2, a3, a4);
}
static void t265(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | buildErrorHandlingBlockWithErrorType:slot:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o265)(self, _cmd, a1, a2, a3);
}
static void t266(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | buildErrorHandlingBlockWithErrorType:slot:layout:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o266)(self, _cmd, a1, a2, a3, a4);
}
static void t267(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | pingDispatchDelegate:forSlot:forLayout:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o267)(self, _cmd, a1, a2, a3);
}
static void t268(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | retrieveThrottlingCapacityForSlot:"); }
    ((void (*)(id, SEL, id a1))o268)(self, _cmd, a1);
}
static void t269(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowManagerImpl | eventCenter"); }
    ((void (*)(id, SEL))o269)(self, _cmd);
}
static void t270(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | init"); }
    ((void (*)(id, SEL))o270)(self, _cmd);
}
static void t271(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | buildAndRegisterSlotsFromPlaybackData:"); }
    ((void (*)(id, SEL, id a1))o271)(self, _cmd, a1);
}
static void t272(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | gaplessBuildAndRegisterSlotsFromPlaybackData:"); }
    ((void (*)(id, SEL, id a1))o272)(self, _cmd, a1);
}
static void t273(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | setInstreamAdBreakLifecycleAPI:"); }
    ((void (*)(id, SEL, id a1))o273)(self, _cmd, a1);
}
static void t274(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | handleDiscoverySlotsFromPlayerResponse:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2))o274)(self, _cmd, a1, a2);
}
static void t275(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | addPlayerBytesAndForecastingSlotsFromPlayerResponse:intoSlotArray:contentCPN:cachedAdIntro:isIosEnableAdBreakRequestSlot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o275)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t276(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | playerBytesSlotsFromOfflinePlayerResponse:contentCPN:cachedAdIntro:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o276)(self, _cmd, a1, a2, a3);
}
static void t277(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | playerBytesAndForecastingSlotsFromOnlinePlayerResponse:adsSupportedRenderers:contentCPN:cachedAdIntro:isIosEnableAdBreakRequestSlot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o277)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t278(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | createPlayerBytesSlotFromAdSlot:contentCPN:adSlot:adBreaks:isGapless:DAIMetadata:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o278)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t279(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | adArrayFromPlayerBytesAdLayoutRenderer:adBreaks:"); }
    ((void (*)(id, SEL, id a1, id a2))o279)(self, _cmd, a1, a2);
}
static void t280(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | maybeAddVideoAdRendererFromRenderingContent:toArray:"); }
    ((void (*)(id, SEL, id a1, id a2))o280)(self, _cmd, a1, a2);
}
static void t281(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | maybeAddSurveyAdRendererFromRenderingContent:toArray:"); }
    ((void (*)(id, SEL, id a1, id a2))o281)(self, _cmd, a1, a2);
}
static void t282(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | maybeAddSurveyTextInterstitialRendererFromRenderingContent:toArray:"); }
    ((void (*)(id, SEL, id a1, id a2))o282)(self, _cmd, a1, a2);
}
static void t283(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | gaplessPlayerBytesSlotsFromPlayerResponse:adBreaks:contentCPN:cachedAdIntro:containsPrerollInAdSlotRenderer:enableAdBreakRequestSlot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o283)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t284(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | prerollPlayerBytesSlotFromOnlinePlayerResponse:adsSupportedRenderers:contentCPN:cachedAdIntro:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o284)(self, _cmd, a1, a2, a3, a4);
}
static void t285(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | adBreakRequestSlotsFromOnlinePlayerResponse:adsSupportedRenderers:slots:contentCPN:cachedAdIntro:isIosEnableAdBreakRequestSlot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o285)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t286(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | gaplessAdBreakRequestSlotsFromOnlinePlayerResponse:sortedAdBreaks:contentCPN:cachedAdIntro:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o286)(self, _cmd, a1, a2, a3, a4);
}
static void t287(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | slotForAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o287)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t288(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | slotForAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:isGapless:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o288)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t289(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | containsForecastingAdRendererInAdBreak:"); }
    ((void (*)(id, SEL, id a1))o289)(self, _cmd, a1);
}
static void t290(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | adBreakRequestSlotForAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:isGapless:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o290)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t291(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | adBreakRequestSlotForAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o291)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t292(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTContentVideoPlayerResponseSlotOpportunityAdapterImpl | getMediaLayoutIdsFromPlayerBytesAdLayoutRenderer:"); }
    ((void (*)(id, SEL, id a1))o292)(self, _cmd, a1);
}
static void t293(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | init"); }
    ((void (*)(id, SEL))o293)(self, _cmd);
}
static void t294(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | hasPlayerBytesSlotInAdSlotsArray:"); }
    ((void (*)(id, SEL, id a1))o294)(self, _cmd, a1);
}
static void t295(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | processThrottledAdBreakResponse:contentCPN:contentPlayerResponse:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o295)(self, _cmd, a1, a2, a3);
}
static void t296(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | onAdBreakResponseReceivedWithAdSlotRenderers:contentCPN:contentPlayerResponse:adBreak:adBreakResponse:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o296)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t297(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | containsPlayerBytesSlot:"); }
    ((void (*)(id, SEL, id a1))o297)(self, _cmd, a1);
}
static void t298(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | slotRendererFromAdSlotRenderer:"); }
    ((void (*)(id, SEL, id a1))o298)(self, _cmd, a1);
}
static void t299(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | legacyAdBreakResponseAndProcessAdBreak:"); }
    ((void (*)(id, SEL, id a1))o299)(self, _cmd, a1);
}
static void t300(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | adArrayFromPlayerBytesAdLayoutRenderer:adBreaks:"); }
    ((void (*)(id, SEL, id a1, id a2))o300)(self, _cmd, a1, a2);
}
static void t301(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | maybeAddVideoAdRendererFromRenderingContent:toArray:"); }
    ((void (*)(id, SEL, id a1, id a2))o301)(self, _cmd, a1, a2);
}
static void t302(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | maybeAddSurveyAdRendererFromRenderingContent:toArray:"); }
    ((void (*)(id, SEL, id a1, id a2))o302)(self, _cmd, a1, a2);
}
static void t303(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | maybeAddSurveyTextInterstitialRendererFromRenderingContent:toArray:"); }
    ((void (*)(id, SEL, id a1, id a2))o303)(self, _cmd, a1, a2);
}
static void t304(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | getMediaLayoutsIds:"); }
    ((void (*)(id, SEL, id a1))o304)(self, _cmd, a1);
}
static void t305(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | playerAdsFromAdBreakResponse:"); }
    ((void (*)(id, SEL, id a1))o305)(self, _cmd, a1);
}
static void t306(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | containsBelowPlayerImmersiveSlot:"); }
    ((void (*)(id, SEL, id a1))o306)(self, _cmd, a1);
}
static void t307(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | eligibleAdsFromThrottledAdBreakResponse:"); }
    ((void (*)(id, SEL, id a1))o307)(self, _cmd, a1);
}
static void t308(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | makeWatchNextRequestWithInstreamAdsForDAILegacy:"); }
    ((void (*)(id, SEL, id a1))o308)(self, _cmd, a1);
}
static void t309(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | makeWatchNextRequestWithInstreamAdsForDAI:mediaLayoutIds:contentCPN:playerResponse:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o309)(self, _cmd, a1, a2, a3, a4);
}
static void t310(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | playableAdsFromAds:"); }
    ((void (*)(id, SEL, id a1))o310)(self, _cmd, a1);
}
static void t311(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterImpl | scheduleNewPauseAdBreakRequestSlotFromSlot:adBreak:contentCPN:externalContext:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o311)(self, _cmd, a1, a2, a3, a4);
}
static void t312(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterV2 | initWithAdsControlFlowManagerV2Handling:"); }
    ((void (*)(id, SEL, id a1))o312)(self, _cmd, a1);
}
static void t313(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakResponseReceivedOpportunityAdapterV2 | didReceiveAdBreakResponse:fromAdBreakSlot:"); }
    ((void (*)(id, SEL, id a1, id a2))o313)(self, _cmd, a1, a2);
}
static void t314(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTCommandDrivenExternallyManagedSlotOpportunityAdapter | init"); }
    ((void (*)(id, SEL))o314)(self, _cmd);
}
static void t315(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTCommandDrivenExternallyManagedSlotOpportunityAdapter | didReceiveCommand:fromSender:"); }
    ((void (*)(id, SEL, id a1, id a2))o315)(self, _cmd, a1, a2);
}
static void t316(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTCommandDrivenExternallyManagedSlotOpportunityAdapter | slotsFromCommand:"); }
    ((void (*)(id, SEL, id a1))o316)(self, _cmd, a1);
}
static void t317(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdsControlFlowOpportunityReceivedCommandHandlerImpl | executeWithCommand:entry:fromView:sender:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o317)(self, _cmd, a1, a2, a3, a4);
}
static void t318(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTBaseOpportunityAdapter | initWithOpportunityType:adsControlFlowManagerV2Handling:"); }
    ((void (*)(id, SEL, id a1, id a2))o318)(self, _cmd, a1, a2);
}
static void t319(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTBaseOpportunityAdapter | didReceiveAdSlots:adOpportunityContext:"); }
    ((void (*)(id, SEL, id a1, id a2))o319)(self, _cmd, a1, a2);
}
static void t320(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTBaseOpportunityAdapter | opportunityType"); }
    ((void (*)(id, SEL))o320)(self, _cmd);
}
static void t321(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTBaseOpportunityAdapter | getClientSlots:adOpportunityContext:"); }
    ((void (*)(id, SEL, id a1, id a2))o321)(self, _cmd, a1, a2);
}
static void t322(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTBaseOpportunityAdapter | buildServerSlots:adOpportunityContext:"); }
    ((void (*)(id, SEL, id a1, id a2))o322)(self, _cmd, a1, a2);
}
static void t323(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTBaseOpportunityAdapter | createSlotFromAdSlotRenderer:"); }
    ((void (*)(id, SEL, id a1))o323)(self, _cmd, a1);
}
static void t324(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakServiceImpl | initWithAccountID:"); }
    ((void (*)(id, SEL, id a1))o324)(self, _cmd, a1);
}
static void t325(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakServiceImpl | makeAdBreakRequest:responseBlock:errorBlock:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o325)(self, _cmd, a1, a2, a3);
}
static void t326(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakServiceImpl | makeAdBreakRequest:responseBlock:errorBlock:retryEnabled:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o326)(self, _cmd, a1, a2, a3, a4);
}
static void t327(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererFetcher | makeWatchNextRequestWithInstreamAdsLegacy:CSILoggingResponder:"); }
    ((void (*)(id, SEL, id a1, id a2))o327)(self, _cmd, a1, a2);
}
static void t328(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererFetcher | makeWatchNextRequestWithInstreamAds:playerResponse:contentCPN:layout:slot:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o328)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t329(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererFetcher | matchingMediaLayoutIdFromLayout:slot:ad:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o329)(self, _cmd, a1, a2, a3);
}
static void t330(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererFetcher | makeWatchNextRequestWithInstreamAd:CSILoggingResponder:playerBytesLayoutID:contentCPN:playerResponse:iosSdfCompanionPrecursor:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o330)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t331(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | initWithAd:adBreak:timingData:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o331)(self, _cmd, a1, a2, a3);
}
static void t332(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | initWithAd:adBreak:timingData:adPlaybackData:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o332)(self, _cmd, a1, a2, a3, a4);
}
static void t333(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | init"); }
    ((void (*)(id, SEL))o333)(self, _cmd);
}
static void t334(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | isEqual:"); }
    ((void (*)(id, SEL, id a1))o334)(self, _cmd, a1);
}
static void t335(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | hash"); }
    ((void (*)(id, SEL))o335)(self, _cmd);
}
static void t336(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | rootExitFadeOut"); }
    ((void (*)(id, SEL))o336)(self, _cmd);
}
static void t337(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | rootEnterFadeIn"); }
    ((void (*)(id, SEL))o337)(self, _cmd);
}
static void t338(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | ad"); }
    ((void (*)(id, SEL))o338)(self, _cmd);
}
static void t339(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | adBreak"); }
    ((void (*)(id, SEL))o339)(self, _cmd);
}
static void t340(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | initialMediaTime"); }
    ((void (*)(id, SEL))o340)(self, _cmd);
}
static void t341(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | setInitialMediaTime:"); }
    ((void (*)(id, SEL, id a1))o341)(self, _cmd, a1);
}
static void t342(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | adPlaybackData"); }
    ((void (*)(id, SEL))o342)(self, _cmd);
}
static void t343(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | adOverlay"); }
    ((void (*)(id, SEL))o343)(self, _cmd);
}
static void t344(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | setAdOverlay:"); }
    ((void (*)(id, SEL, id a1))o344)(self, _cmd, a1);
}
static void t345(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | timingData"); }
    ((void (*)(id, SEL))o345)(self, _cmd);
}
static void t346(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | holdingAdBreak"); }
    ((void (*)(id, SEL))o346)(self, _cmd);
}
static void t347(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | setHoldingAdBreak:"); }
    ((void (*)(id, SEL, id a1))o347)(self, _cmd, a1);
}
static void t348(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | upcomingContentRewindOffset"); }
    ((void (*)(id, SEL))o348)(self, _cmd);
}
static void t349(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdInterrupt | setUpcomingContentRewindOffset:"); }
    ((void (*)(id, SEL, id a1))o349)(self, _cmd, a1);
}
static void t350(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | initWithSlot:"); }
    ((void (*)(id, SEL, id a1))o350)(self, _cmd, a1);
}
static void t351(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | cancelFillingSlot"); }
    ((void (*)(id, SEL))o351)(self, _cmd);
}
static void t352(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | fillSlot"); }
    ((void (*)(id, SEL))o352)(self, _cmd);
}
static void t353(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | adCuepointAPI:didReceiveCuepoint:"); }
    ((void (*)(id, SEL, id a1, id a2))o353)(self, _cmd, a1, a2);
}
static void t354(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | adCuepointAPI:noCuepointReceivedSinceTime:"); }
    ((void (*)(id, SEL, id a1, id a2))o354)(self, _cmd, a1, a2);
}
static void t355(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | playbackTimelinePlaceholderSegmentStatus"); }
    ((void (*)(id, SEL))o355)(self, _cmd);
}
static void t356(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | playableAdsFromAds:"); }
    ((void (*)(id, SEL, id a1))o356)(self, _cmd, a1);
}
static void t357(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | insertPlaceholderSegmentAndMaybeMakeAdBreakRequestWithCuepoint:"); }
    ((void (*)(id, SEL, id a1))o357)(self, _cmd, a1);
}
static void t358(id self, SEL _cmd, id a1, id a2, id a3, id a4) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | processAdBreakResponse:originalAdBreak:playerResponse:contentCPN:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4))o358)(self, _cmd, a1, a2, a3, a4);
}
static void t359(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | updatePlaceholderSegmentWithCuepoint:"); }
    ((void (*)(id, SEL, id a1))o359)(self, _cmd, a1);
}
static void t360(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | removePlaceholderSegmentFromPlaybackTimeline"); }
    ((void (*)(id, SEL))o360)(self, _cmd);
}
static void t361(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | playerAdsFromAdBreakResponse:"); }
    ((void (*)(id, SEL, id a1))o361)(self, _cmd, a1);
}
static void t362(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | eligibleAdsFromThrottledAdBreakResponse:"); }
    ((void (*)(id, SEL, id a1))o362)(self, _cmd, a1);
}
static void t363(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesDAISlotFulfillmentAdapter | matchingCueIdentifier"); }
    ((void (*)(id, SEL))o363)(self, _cmd);
}
static void t364(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | initWithSlot:"); }
    ((void (*)(id, SEL, id a1))o364)(self, _cmd, a1);
}
static void t365(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | cancelFillingSlot"); }
    ((void (*)(id, SEL))o365)(self, _cmd);
}
static void t366(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | fillSlot"); }
    ((void (*)(id, SEL))o366)(self, _cmd);
}
static void t367(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | hasFulfilledLayout:"); }
    ((void (*)(id, SEL, id a1))o367)(self, _cmd, a1);
}
static void t368(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | processAdRenderers:adBreakResponse:originalAdBreak:playerResponse:adWatchNextParams:isGapless:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o368)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t369(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | firstPrerollAdBreakInArray:"); }
    ((void (*)(id, SEL, id a1))o369)(self, _cmd, a1);
}
static void t370(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | makeOfflineAdRequestWithAdBreak:andFulfillSlot:"); }
    ((void (*)(id, SEL, id a1, id a2))o370)(self, _cmd, a1, a2);
}
static void t371(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | firstForecastingAdInAds:"); }
    ((void (*)(id, SEL, id a1))o371)(self, _cmd, a1);
}
static void t372(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | sendCSILogWhenWillRequestAdBreak"); }
    ((void (*)(id, SEL))o372)(self, _cmd);
}
static void t373(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | sendCSILogWhenAdBreakResponseReceived"); }
    ((void (*)(id, SEL))o373)(self, _cmd);
}
static void t374(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | playerAdsFromAdBreakResponse:"); }
    ((void (*)(id, SEL, id a1))o374)(self, _cmd, a1);
}
static void t375(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | currentMediaTimeFromContentVideo"); }
    ((void (*)(id, SEL))o375)(self, _cmd);
}
static void t376(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerBytesSlotFulfillmentAdapter | enableAdBreakRequestSlotWithGaplessEnabled:breakType:"); }
    ((void (*)(id, SEL, id a1, id a2))o376)(self, _cmd, a1, a2);
}
static void t377(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | initWithSlot:"); }
    ((void (*)(id, SEL, id a1))o377)(self, _cmd, a1);
}
static void t378(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | cancelFillingSlot"); }
    ((void (*)(id, SEL))o378)(self, _cmd);
}
static void t379(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | fillSlot"); }
    ((void (*)(id, SEL))o379)(self, _cmd);
}
static void t380(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | adCuepointAPI:didReceiveCuepoint:"); }
    ((void (*)(id, SEL, id a1, id a2))o380)(self, _cmd, a1, a2);
}
static void t381(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | adCuepointAPI:noCuepointReceivedSinceTime:"); }
    ((void (*)(id, SEL, id a1, id a2))o381)(self, _cmd, a1, a2);
}
static void t382(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | playbackTimelinePlaceholderSegmentStatus"); }
    ((void (*)(id, SEL))o382)(self, _cmd);
}
static void t383(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | sendCSILogWhenWillRequestAdBreak"); }
    ((void (*)(id, SEL))o383)(self, _cmd);
}
static void t384(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | sendCSILogWhenAdBreakResponseReceived"); }
    ((void (*)(id, SEL))o384)(self, _cmd);
}
static void t385(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | processAdBreakResponse:"); }
    ((void (*)(id, SEL, id a1))o385)(self, _cmd, a1);
}
static void t386(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | currentMediaTimeFromContentVideo"); }
    ((void (*)(id, SEL))o386)(self, _cmd);
}
static void t387(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | updatePlaceholderSegmentWithCuepoint:"); }
    ((void (*)(id, SEL, id a1))o387)(self, _cmd, a1);
}
static void t388(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | insertPlaceholderSegmentAndMaybeMakeAdBreakRequestForDAI"); }
    ((void (*)(id, SEL))o388)(self, _cmd);
}
static void t389(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | removePlaceholderSegmentFromPlaybackTimeline"); }
    ((void (*)(id, SEL))o389)(self, _cmd);
}
static void t390(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | maybeMakeAdBreakRequestForNonDAI"); }
    ((void (*)(id, SEL))o390)(self, _cmd);
}
static void t391(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRequestSlotFulfillmentAdapter | matchingCueIdentifier"); }
    ((void (*)(id, SEL))o391)(self, _cmd);
}
static void t392(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | initWithPlayerData:responseDate:offlineStateDate:mutableState:trailer:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5))o392)(self, _cmd, a1, a2, a3, a4, a5);
}
static void t393(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | initWithPlayerData:responseDate:offlineStateDate:mutableState:trailer:offlineRentalActivated:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3, id a4, id a5, id a6))o393)(self, _cmd, a1, a2, a3, a4, a5, a6);
}
static void t394(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | adPlayerResponse"); }
    ((void (*)(id, SEL))o394)(self, _cmd);
}
static void t395(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | trailerPlayerResponse"); }
    ((void (*)(id, SEL))o395)(self, _cmd);
}
static void t396(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | isDAICompatible"); }
    ((void (*)(id, SEL))o396)(self, _cmd);
}
static void t397(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | videoID"); }
    ((void (*)(id, SEL))o397)(self, _cmd);
}
static void t398(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | timeUntilStreamingDataExpirySeconds"); }
    ((void (*)(id, SEL))o398)(self, _cmd);
}
static void t399(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | areStreamsCloseToExpiringIfPlaybackStartsNow"); }
    ((void (*)(id, SEL))o399)(self, _cmd);
}
static void t400(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | isExpiredByMaxAgeSeconds"); }
    ((void (*)(id, SEL))o400)(self, _cmd);
}
static void t401(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | isValid"); }
    ((void (*)(id, SEL))o401)(self, _cmd);
}
static void t402(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | setCacheContext:"); }
    ((void (*)(id, SEL, id a1))o402)(self, _cmd, a1);
}
static void t403(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | setReuse:"); }
    ((void (*)(id, SEL, id a1))o403)(self, _cmd, a1);
}
static void t404(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | setLatencyLogger:"); }
    ((void (*)(id, SEL, id a1))o404)(self, _cmd, a1);
}
static void t405(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | setPlayerCompatibility:"); }
    ((void (*)(id, SEL, id a1))o405)(self, _cmd, a1);
}
static void t406(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | isPlayableInPictureInPicture"); }
    ((void (*)(id, SEL))o406)(self, _cmd);
}
static void t407(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | isPipOffByDefault"); }
    ((void (*)(id, SEL))o407)(self, _cmd);
}
static void t408(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | shouldPipResumeOnHead"); }
    ((void (*)(id, SEL))o408)(self, _cmd);
}
static void t409(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | setServerStitchedDisabled:"); }
    ((void (*)(id, SEL, id a1))o409)(self, _cmd, a1);
}
static void t410(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | serverStitchedEventCenter"); }
    ((void (*)(id, SEL))o410)(self, _cmd);
}
static void t411(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | playerData"); }
    ((void (*)(id, SEL))o411)(self, _cmd);
}
static void t412(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | responseDate"); }
    ((void (*)(id, SEL))o412)(self, _cmd);
}
static void t413(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | offlineStateDate"); }
    ((void (*)(id, SEL))o413)(self, _cmd);
}
static void t414(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | mutableState"); }
    ((void (*)(id, SEL))o414)(self, _cmd);
}
static void t415(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | isTrailer"); }
    ((void (*)(id, SEL))o415)(self, _cmd);
}
static void t416(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | QOEController"); }
    ((void (*)(id, SEL))o416)(self, _cmd);
}
static void t417(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | setQOEController:"); }
    ((void (*)(id, SEL, id a1))o417)(self, _cmd, a1);
}
static void t418(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | cacheContext"); }
    ((void (*)(id, SEL))o418)(self, _cmd);
}
static void t419(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | isReuse"); }
    ((void (*)(id, SEL))o419)(self, _cmd);
}
static void t420(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | isOfflineRentalActivated"); }
    ((void (*)(id, SEL))o420)(self, _cmd);
}
static void t421(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | latencyLogger"); }
    ((void (*)(id, SEL))o421)(self, _cmd);
}
static void t422(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | playerCompatibility"); }
    ((void (*)(id, SEL))o422)(self, _cmd);
}
static void t423(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | isDAIDisabled"); }
    ((void (*)(id, SEL))o423)(self, _cmd);
}
static void t424(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | setDAIDisabled:"); }
    ((void (*)(id, SEL, id a1))o424)(self, _cmd, a1);
}
static void t425(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTPlayerResponse | cacheKey"); }
    ((void (*)(id, SEL))o425)(self, _cmd);
}
static void t426(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | offlineUpsell"); }
    ((void (*)(id, SEL))o426)(self, _cmd);
}
static void t427(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | backgroundUpsell"); }
    ((void (*)(id, SEL))o427)(self, _cmd);
}
static void t428(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | isMonetized"); }
    ((void (*)(id, SEL))o428)(self, _cmd);
}
static void t429(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | isLivePlayback"); }
    ((void (*)(id, SEL))o429)(self, _cmd);
}
static void t430(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | storyboardSpec"); }
    ((void (*)(id, SEL))o430)(self, _cmd);
}
static void t431(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | liveStoryboardSpec"); }
    ((void (*)(id, SEL))o431)(self, _cmd);
}
static void t432(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | hasTracklistCaptionTracks"); }
    ((void (*)(id, SEL))o432)(self, _cmd);
}
static void t433(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | adIntroRenderer"); }
    ((void (*)(id, SEL))o433)(self, _cmd);
}
static void t434(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | canBeEnqueuedGaplessly"); }
    ((void (*)(id, SEL))o434)(self, _cmd);
}
static void t435(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | canEnqueueUpcomingPlaybacks"); }
    ((void (*)(id, SEL))o435)(self, _cmd);
}
static void t436(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | isDAIEnabledPlayback"); }
    ((void (*)(id, SEL))o436)(self, _cmd);
}
static void t437(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | isCuepointAdsEnabled"); }
    ((void (*)(id, SEL))o437)(self, _cmd);
}
static void t438(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | hasPrerollAds"); }
    ((void (*)(id, SEL))o438)(self, _cmd);
}
static void t439(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | mutedAtStart"); }
    ((void (*)(id, SEL))o439)(self, _cmd);
}
static void t440(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | isAudioOnlyAvailabilityBlocked"); }
    ((void (*)(id, SEL))o440)(self, _cmd);
}
static void t441(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | audioOnlyPlayabilityRenderer"); }
    ((void (*)(id, SEL))o441)(self, _cmd);
}
static void t442(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | isWindowedLive"); }
    ((void (*)(id, SEL))o442)(self, _cmd);
}
static void t443(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | paidContentOverlayElementRendererOptions"); }
    ((void (*)(id, SEL))o443)(self, _cmd);
}
static void t444(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | deferredPlayerTokenWithIdentifier:"); }
    ((void (*)(id, SEL, id a1))o444)(self, _cmd, a1);
}
static void t445(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | shouldCacheResponse"); }
    ((void (*)(id, SEL))o445)(self, _cmd);
}
static void t446(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | aspectRatio"); }
    ((void (*)(id, SEL))o446)(self, _cmd);
}
static void t447(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | duration"); }
    ((void (*)(id, SEL))o447)(self, _cmd);
}
static void t448(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | yt_formatStreamForPreferredVideoQuality:withCap:"); }
    ((void (*)(id, SEL, id a1, id a2))o448)(self, _cmd, a1, a2);
}
static void t449(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | adBreaksWithVMAPParser:error:"); }
    ((void (*)(id, SEL, id a1, id a2))o449)(self, _cmd, a1, a2);
}
static void t450(id self, SEL _cmd, id a1, id a2, id a3) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | adBreaksWithVMAPParser:VMAPXMLString:error:"); }
    ((void (*)(id, SEL, id a1, id a2, id a3))o450)(self, _cmd, a1, a2, a3);
}
static void t451(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | remoteAdURLsWithVMAPParser:error:"); }
    ((void (*)(id, SEL, id a1, id a2))o451)(self, _cmd, a1, a2);
}
static void t452(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | VMAPXMLString"); }
    ((void (*)(id, SEL))o452)(self, _cmd);
}
static void t453(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | fillHostVideoID:inVMAPAdBreaks:"); }
    ((void (*)(id, SEL, id a1, id a2))o453)(self, _cmd, a1, a2);
}
static void t454(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | adsAllowReuse"); }
    ((void (*)(id, SEL))o454)(self, _cmd);
}
static void t455(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | containsDiscoverySlotsOpportunity"); }
    ((void (*)(id, SEL))o455)(self, _cmd);
}
static void t456(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | hasVideoAdTrackingRenderer"); }
    ((void (*)(id, SEL))o456)(self, _cmd);
}
static void t457(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | yt_formatStreamForPreferredAudioQuality:"); }
    ((void (*)(id, SEL, id a1))o457)(self, _cmd, a1);
}
static void t458(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTIPlayerResponse | autoSpeedCueRangeSet"); }
    ((void (*)(id, SEL))o458)(self, _cmd);
}
static void t459(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | initWithPrerollAdSlotRendererLegacy:"); }
    ((void (*)(id, SEL, id a1))o459)(self, _cmd, a1);
}
static void t460(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | initWithAdSlotRenderer:"); }
    ((void (*)(id, SEL, id a1))o460)(self, _cmd, a1);
}
static void t461(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | isPreroll"); }
    ((void (*)(id, SEL))o461)(self, _cmd);
}
static void t462(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | isPostroll"); }
    ((void (*)(id, SEL))o462)(self, _cmd);
}
static void t463(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | type"); }
    ((void (*)(id, SEL))o463)(self, _cmd);
}
static void t464(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | adSlotLoggingData"); }
    ((void (*)(id, SEL))o464)(self, _cmd);
}
static void t465(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | absoluteOffsetWithVideoLength:"); }
    ((void (*)(id, SEL, id a1))o465)(self, _cmd, a1);
}
static void t466(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | timeOffsetMilliseconds"); }
    ((void (*)(id, SEL))o466)(self, _cmd);
}
static void t467(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | prefetchIntervalMs"); }
    ((void (*)(id, SEL))o467)(self, _cmd);
}
static void t468(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | timeOffset"); }
    ((void (*)(id, SEL))o468)(self, _cmd);
}
static void t469(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | ads"); }
    ((void (*)(id, SEL))o469)(self, _cmd);
}
static void t470(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | podRemainingTimeWithAd:"); }
    ((void (*)(id, SEL, id a1))o470)(self, _cmd, a1);
}
static void t471(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | midrollOffsetStartMilliseconds"); }
    ((void (*)(id, SEL))o471)(self, _cmd);
}
static void t472(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | sendYTClientError:"); }
    ((void (*)(id, SEL, id a1))o472)(self, _cmd, a1);
}
static void t473(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdSlotRendererAdapter | adSlotRenderer"); }
    ((void (*)(id, SEL))o473)(self, _cmd);
}
static void t474(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | initWithAdBreakRenderer:"); }
    ((void (*)(id, SEL, id a1))o474)(self, _cmd, a1);
}
static void t475(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | breakStartPings"); }
    ((void (*)(id, SEL))o475)(self, _cmd);
}
static void t476(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | breakEndPings"); }
    ((void (*)(id, SEL))o476)(self, _cmd);
}
static void t477(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | isPreroll"); }
    ((void (*)(id, SEL))o477)(self, _cmd);
}
static void t478(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | isPostroll"); }
    ((void (*)(id, SEL))o478)(self, _cmd);
}
static void t479(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | type"); }
    ((void (*)(id, SEL))o479)(self, _cmd);
}
static void t480(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | adSlotLoggingData"); }
    ((void (*)(id, SEL))o480)(self, _cmd);
}
static void t481(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | absoluteOffsetWithVideoLength:"); }
    ((void (*)(id, SEL, id a1))o481)(self, _cmd, a1);
}
static void t482(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | timeOffsetMilliseconds"); }
    ((void (*)(id, SEL))o482)(self, _cmd);
}
static void t483(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | prefetchIntervalMs"); }
    ((void (*)(id, SEL))o483)(self, _cmd);
}
static void t484(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | timeOffset"); }
    ((void (*)(id, SEL))o484)(self, _cmd);
}
static void t485(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | ads"); }
    ((void (*)(id, SEL))o485)(self, _cmd);
}
static void t486(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | podRemainingTimeWithAd:"); }
    ((void (*)(id, SEL, id a1))o486)(self, _cmd, a1);
}
static void t487(id self, SEL _cmd, id a1) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | copyWithZone:"); }
    ((void (*)(id, SEL, id a1))o487)(self, _cmd, a1);
}
static void t488(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | createAds"); }
    ((void (*)(id, SEL))o488)(self, _cmd);
}
static void t489(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdBreakRendererAdapter | adBreakRenderer"); }
    ((void (*)(id, SEL))o489)(self, _cmd);
}
static void t490(id self, SEL _cmd, id a1, id a2) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdClientOrganicMetadata | init:adSlotRenderers:"); }
    ((void (*)(id, SEL, id a1, id a2))o490)(self, _cmd, a1, a2);
}
static void t491(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdClientOrganicMetadata | adSlotRenderers"); }
    ((void (*)(id, SEL))o491)(self, _cmd);
}
static void t492(id self, SEL _cmd) {
    if (g_traceHits < g_traceMax) { g_traceHits++; YTModLog(@"trace YTAdClientOrganicMetadata | reelWatchEndpoint"); }
    ((void (*)(id, SEL))o492)(self, _cmd);
}

static YTMTraceEntry g_entries[] = {
    {"YTSlotFactoryImpl", "init", (IMP)t0, &o0},
    {"YTSlotFactoryImpl", "pauseAdBreakRequestSlotFromAdBreak:metadata:contentCPN:", (IMP)t1, &o1},
    {"YTSlotFactoryImpl", "pauseAdBreakRequestSlotFromAdBreak:slotID:metadata:contentCPN:", (IMP)t2, &o2},
    {"YTSlotFactoryImpl", "adBreakRequestSlotFromAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:isGapless:", (IMP)t3, &o3},
    {"YTSlotFactoryImpl", "adBreakRequestSlotFromAdThrottledSlot:", (IMP)t4, &o4},
    {"YTSlotFactoryImpl", "gaplessPlayerBytesSlotFromAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:", (IMP)t5, &o5},
    {"YTSlotFactoryImpl", "playerBytesSlotFromAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:", (IMP)t6, &o6},
    {"YTSlotFactoryImpl", "playerBytesSlotFromAdThrottledSlot:", (IMP)t7, &o7},
    {"YTSlotFactoryImpl", "playerBytesSlotFromAdBreakResponseForVod:forAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:adBreakRequestSlot:", (IMP)t8, &o8},
    {"YTSlotFactoryImpl", "forecastingSlotFromAdRenderer:adBreak:nextAdBreak:contentCPN:contentPlayerResponse:", (IMP)t9, &o9},
    {"YTSlotFactoryImpl", "forecastingSlotFromAd:playerBytesSlot:offlineAdBreak:", (IMP)t10, &o10},
    {"YTSlotFactoryImpl", "belowPlayerSlotFromWatchNextPromise:instreamAd:playerBytesLayoutID:contentCPN:", (IMP)t11, &o11},
    {"YTSlotFactoryImpl", "createBelowPlayerOrBelowPlayerImmersiveSlotFromAdSlotRenderer:contentCPN:", (IMP)t12, &o12},
    {"YTSlotFactoryImpl", "belowPlayerSlotFromWatchNextResponse:playerBytesLayoutID:contentCPN:", (IMP)t13, &o13},
    {"YTSlotFactoryImpl", "belowPlayerImmersiveSlotFromWatchNextPromise:instreamAd:playerBytesLayoutID:belowPlayerSlotID:contentCPN:", (IMP)t14, &o14},
    {"YTSlotFactoryImpl", "belowPlayerImmersiveSlotFromWatchNextResponse:playerBytesLayoutID:contentCPN:", (IMP)t15, &o15},
    {"YTSlotFactoryImpl", "fullscreenEngagementSlotFromAd:adBreakType:playerBytesLayoutID:contentCPN:", (IMP)t16, &o16},
    {"YTSlotFactoryImpl", "inPlayerSlotFromPlayerBytesLayoutID:adBreak:contentCPN:playerResponse:gaplessContext:", (IMP)t17, &o17},
    {"YTSlotFactoryImpl", "createInPlayerSlotFromAdSlotRenderer:adBreak:contentCPN:playerBytesLayoutID:playerResponse:gaplessContext:", (IMP)t18, &o18},
    {"YTSlotFactoryImpl", "externallyManagedInPlayerSlotFromAd:", (IMP)t19, &o19},
    {"YTSlotFactoryImpl", "slotFromAdSlotMetadata:controlFlowLayer:", (IMP)t20, &o20},
    {"YTSlotFactoryImpl", "externallyManagedSlotFromSlotLoggingData:controlFlowLayer:", (IMP)t21, &o21},
    {"YTSlotFactoryImpl", "belowPlayerDiscoverySlotFromPlayerResponse:contentCPN:", (IMP)t22, &o22},
    {"YTSlotFactoryImpl", "discoveryPlaybackTrackingSlotFromPlayerResponse:contentCPN:", (IMP)t23, &o23},
    {"YTSlotFactoryImpl", "DAIPlayerBytesSlotFromCuepoint:adBreak:adBreakIndex:contentCPN:contentPlayerResponse:", (IMP)t24, &o24},
    {"YTSlotFactoryImpl", "nonDAIPlayerBytesSlotFromCuepoint:adBreak:adBreakIndex:contentCPN:fulfillmentStartTime:contentPlayerResponse:", (IMP)t25, &o25},
    {"YTSlotFactoryImpl", "DAIAdBreakRequestSlotFromCuepoint:adBreak:adBreakIndex:contentCPN:contentPlayerResponse:", (IMP)t26, &o26},
    {"YTSlotFactoryImpl", "discoveryInPlayerSlotFromCTAOverlayRenderer:contentCPN:associatedDiscoveryLayoutID:", (IMP)t27, &o27},
    {"YTSlotFactoryImpl", "discoveryBelowPlayerImmersiveSlotFromRenderer:onUIReadyCommand:contentCPN:", (IMP)t28, &o28},
    {"YTSlotFactoryImpl", "playerBytesSequenceItemSlotFromReelWatchEndpoint:", (IMP)t29, &o29},
    {"YTSlotFactoryImpl", "sequenceItemInPlayerSlotFromPlayerBytesSlot:mediaLayout:reelWatchEndpoint:elementRenderer:adLayoutLoggingData:slotPhysicalPosition:", (IMP)t30, &o30},
    {"YTSlotFactoryImpl", "createBelowPlayerImmersiveSlotFromAdSlotRenderer:contentCPN:adBreak:adBreakResponse:adBreakRequestSlot:", (IMP)t31, &o31},
    {"YTSlotFactoryImpl", "createPlayerBytesSlotFromAdSlotRenderer:contentCPN:playerResponse:adBreak:fulfilledLayout:DAIMetadata:", (IMP)t32, &o32},
    {"YTSlotFactoryImpl", "sequenceItemPlayerUnderlaySlotFromPlayerBytesSlot:mediaLayout:reelWatchEndpoint:playerResponse:adSlotRenderer:", (IMP)t33, &o33},
    {"YTSlotFactoryImpl", "sequenceItemPlayerUnderlaySlotFromPlayerBytesSlot:mediaLayout:reelWatchEndpoint:adSlotRenderer:", (IMP)t34, &o34},
    {"YTSlotFactoryImpl", "sequenceItemPlayerSideSlotFromPlayerBytesSlot:mediaLayout:reelWatchEndpoint:adSlotRenderer:", (IMP)t35, &o35},
    {"YTSlotFactoryImpl", "sequenceItemPlayerOrganicOverlaySlotFromWatchEndpoint:adSlotRenderer:", (IMP)t36, &o36},
    {"YTSlotFactoryImpl", "lockscreenSlotFromInstreamAd:playerBytesLayoutID:", (IMP)t37, &o37},
    {"YTSlotFactoryImpl", "playerBytesSequenceItemSlotFromImageAdEndpoint:", (IMP)t38, &o38},
    {"YTSlotFactoryImpl", "sequenceItemInPlayerSlotFromSlot:mediaBreakLayout:imageAdEndpoint:slotPhysicalPosition:", (IMP)t39, &o39},
    {"YTSlotFactoryImpl", "HalftimePrerollPlayerBytesSlot:contentCPN:contentPlayerResponse:playbackData:cachedAdIntro:YTDAIMetadata:", (IMP)t40, &o40},
    {"YTSlotFactoryImpl", "gaplessPlayerBytesSlotFromAdSlotRenderer:contentCPN:contentPlayerResponse:adBreak:fulfilledLayout:", (IMP)t41, &o41},
    {"YTSlotFactoryImpl", "playbackIntervalEnd:videoLength:", (IMP)t42, &o42},
    {"YTSlotFactoryImpl", "stitchedDIBSInsertionTimeFromAdSlotRenderer:playbackStart:", (IMP)t43, &o43},
    {"YTSlotFactoryImpl", "createTriggerFromTrigger:slotID:", (IMP)t44, &o44},
    {"YTSlotFactoryImpl", "createExpirationTriggersForSlotID:contentCPN:", (IMP)t45, &o45},
    {"YTSlotFactoryImpl", "createExpirationTriggersForSlotIDForDAI:contentCPN:", (IMP)t46, &o46},
    {"YTSlotFactoryImpl", "metadataFromContentCPN:contentPlayerResponse:adBreak:cachedAdIntro:", (IMP)t47, &o47},
    {"YTSlotFactoryImpl", "metadataFromContentCPN:contentPlayerResponse:adBreak:cachedAdIntro:gaplessContext:", (IMP)t48, &o48},
    {"YTSlotFactoryImpl", "metadataFromContentCPN:contentPlayerResponse:adBreak:cachedAdIntro:gaplessContext:midrollCueRange:", (IMP)t49, &o49},
    {"YTSlotFactoryImpl", "forecastingMetadataFromContentCPN:forecastingAd:adBreak:", (IMP)t50, &o50},
    {"YTSlotFactoryImpl", "belowPlayerMetadataFromWatchNextPromise:playerBytesLayoutID:instreamAd:", (IMP)t51, &o51},
    {"YTSlotFactoryImpl", "belowPlayerImmersiverMetadataFromWatchNextPromise:playerBytesLayoutID:belowPlayerSlotID:instreamAd:", (IMP)t52, &o52},
    {"YTSlotFactoryImpl", "fullscreenEngagementMetadataFromAd:playerBytesLayoutID:", (IMP)t53, &o53},
    {"YTSlotFactoryImpl", "metadataFromPlayerResponse:contentCPN:", (IMP)t54, &o54},
    {"YTSlotFactoryImpl", "lockscreenMetadataFromAd:playerBytesLayoutID:", (IMP)t55, &o55},
    {"YTSlotFactoryImpl", "shouldEnableTimelineSlotForAdBreak:", (IMP)t56, &o56},
    {"YTSlotFactoryImpl", "forecastingSlotFromAd:adBreak:adBreakStartTime:adBreakEndTime:contentCPN:adSlotLoggingData:", (IMP)t57, &o57},
    {"YTSlotFactoryImpl", "externallyManagedSlotFromAdSlotRenderer:clientMetadata:fulfilledLayout:clientSlotID:", (IMP)t58, &o58},
    {"YTSlotFactoryImpl", "playerBytesSequenceItemTrackingSlotFromAdSlotRenderer:reelWatchEndpoint:fulfilledLayout:", (IMP)t59, &o59},
    {"YTPlayerBytesLayoutEnteredOpportunityAdapterImpl", "init", (IMP)t60, &o60},
    {"YTPlayerBytesLayoutEnteredOpportunityAdapterImpl", "didEnterLayout:forSlot:", (IMP)t61, &o61},
    {"YTPlayerBytesLayoutEnteredOpportunityAdapterImpl", "didEnterMediaLayout:forPlayerBytesSlot:", (IMP)t62, &o62},
    {"YTPlayerBytesLayoutEnteredOpportunityAdapterImpl", "maybeBuildAndScheduleInPlayerSlotsFromPlayerBytesSlot:layout:", (IMP)t63, &o63},
    {"YTPlayerBytesLayoutEnteredOpportunityAdapterImpl", "inPlayerSlotFromPlayerBytesSlot:adBreak:contentCPN:ad:playerResponse:gaplessContext:", (IMP)t64, &o64},
    {"YTPlayerBytesLayoutEnteredOpportunityAdapterImpl", "inPlayerAdSlotRendererMatchingTriggeringID:adSlotsArray:", (IMP)t65, &o65},
    {"YTPlayerBytesLayoutEnteredOpportunityAdapterImpl", "adSlotRendererList:", (IMP)t66, &o66},
    {"YTAdsRequestAndCacheService", "init", (IMP)t67, &o67},
    {"YTAdsRequestAndCacheService", "parseCachedAdsFromAdBreakResponse:adRequestID:serviceID:", (IMP)t68, &o68},
    {"YTAdsRequestAndCacheService", "onPrefetchInstructionUpdate:", (IMP)t69, &o69},
    {"YTAdsRequestAndCacheService", "onPrefetchServiceShouldExpire:", (IMP)t70, &o70},
    {"YTAdsRequestAndCacheService", "requestCacheSelection:selectionInstruction:", (IMP)t71, &o71},
    {"YTAdsRequestAndCacheService", "onAdRequestScheduled:adRequestID:", (IMP)t72, &o72},
    {"YTAdsRequestAndCacheService", "onAdRequestInFlight:adRequestID:", (IMP)t73, &o73},
    {"YTAdsRequestAndCacheService", "onAdResponseSucceeded:adRequestID:adBreakResponse:", (IMP)t74, &o74},
    {"YTAdsRequestAndCacheService", "onAdResponseFailed:adRequestID:error:", (IMP)t75, &o75},
    {"YTAdsRequestAndCacheService", "onAdRequestCancelled:adRequestID:", (IMP)t76, &o76},
    {"YTAdsRequestAndCacheService", "getAdRequestStateForServiceID:adRequestID:", (IMP)t77, &o77},
    {"YTAdsRequestAndCacheService", "onPrefetchServiceExpired:", (IMP)t78, &o78},
    {"YTAdsRequestAndCacheService", "onAdRequestScheduledLocked:adRequestID:", (IMP)t79, &o79},
    {"YTAdsRequestAndCacheService", "onAdRequestInFlightLocked:adRequestID:", (IMP)t80, &o80},
    {"YTAdsRequestAndCacheService", "ingestCachedAdLocked:intoServiceObjectID:logger:", (IMP)t81, &o81},
    {"YTAdsRequestAndCacheService", "onAdResponseSucceededLocked:adRequestID:adBreakResponse:", (IMP)t82, &o82},
    {"YTAdsRequestAndCacheService", "onAdResponseFailedLocked:adRequestID:error:", (IMP)t83, &o83},
    {"YTAdsRequestAndCacheService", "onAdRequestCancelledLocked:adRequestID:", (IMP)t84, &o84},
    {"YTAdsRequestAndCacheService", "onPrefetchServiceShouldExpireLocked:", (IMP)t85, &o85},
    {"YTAdsRequestAndCacheService", "clientAdSelectionInfoMacrosWithSourceAdRequestID:", (IMP)t86, &o86},
    {"YTAdsRequestAndCacheService", "tryPing:sourceAdRequestID:", (IMP)t87, &o87},
    {"YTAdsRequestAndCacheService", "logServiceEvent:fetchJobID:event:", (IMP)t88, &o88},
    {"YTAdsRequestAndCacheService", "logServiceEvent:fetchJobID:event:error:", (IMP)t89, &o89},
    {"YTAdsRequestAndCacheService", "disposeInternal", (IMP)t90, &o90},
    {"YTAdsRequestAndCacheService", "serviceRegistry", (IMP)t91, &o91},
    {"YTAdsRequestAndCacheService", "serialQueue", (IMP)t92, &o92},
    {"YTAdsRequestAndCacheService", "setSerialQueue:", (IMP)t93, &o93},
    {"YTAdsRequestAndCacheService", "pingService", (IMP)t94, &o94},
    {"YTAdsRequestAndCacheService", "setPingService:", (IMP)t95, &o95},
    {"YTAdsControlFlowPlaybackCoordinator", "initWithServiceRegistryScope:overlayManager:delegate:parentResponder:", (IMP)t96, &o96},
    {"YTAdsControlFlowPlaybackCoordinator", "initWithServiceRegistryScope:overlayFactory:delegate:parentResponder:", (IMP)t97, &o97},
    {"YTAdsControlFlowPlaybackCoordinator", "init", (IMP)t98, &o98},
    {"YTAdsControlFlowPlaybackCoordinator", "setSinglePlayerBytesEventListener:", (IMP)t99, &o99},
    {"YTAdsControlFlowPlaybackCoordinator", "adsCuepointObserver", (IMP)t100, &o100},
    {"YTAdsControlFlowPlaybackCoordinator", "supportsPlaybackForContentPlayerResponse:", (IMP)t101, &o101},
    {"YTAdsControlFlowPlaybackCoordinator", "playbackControllerWillActivatePrebufferingAdTransitionWithBufferedMediaTime:", (IMP)t102, &o102},
    {"YTAdsControlFlowPlaybackCoordinator", "acquireOverlay", (IMP)t103, &o103},
    {"YTAdsControlFlowPlaybackCoordinator", "startOverlayForAd:", (IMP)t104, &o104},
    {"YTAdsControlFlowPlaybackCoordinator", "prepareOverlays", (IMP)t105, &o105},
    {"YTAdsControlFlowPlaybackCoordinator", "setOverlayFactory:", (IMP)t106, &o106},
    {"YTAdsControlFlowPlaybackCoordinator", "getPrerollMode", (IMP)t107, &o107},
    {"YTAdsControlFlowPlaybackCoordinator", "startPrerollAdBreak", (IMP)t108, &o108},
    {"YTAdsControlFlowPlaybackCoordinator", "startPostrollAdBreak", (IMP)t109, &o109},
    {"YTAdsControlFlowPlaybackCoordinator", "setContentSingleVideo:playbackTimeline:", (IMP)t110, &o110},
    {"YTAdsControlFlowPlaybackCoordinator", "didStopPlayingAd", (IMP)t111, &o111},
    {"YTAdsControlFlowPlaybackCoordinator", "didSkipOrCompleteAd:", (IMP)t112, &o112},
    {"YTAdsControlFlowPlaybackCoordinator", "didFailToPlayAdWithPlaybackError:", (IMP)t113, &o113},
    {"YTAdsControlFlowPlaybackCoordinator", "didPressSkipAdWithTouchPoint:", (IMP)t114, &o114},
    {"YTAdsControlFlowPlaybackCoordinator", "willPlayNewVideoWithAutoplay:", (IMP)t115, &o115},
    {"YTAdsControlFlowPlaybackCoordinator", "doneWithCurrentAd", (IMP)t116, &o116},
    {"YTAdsControlFlowPlaybackCoordinator", "reset", (IMP)t117, &o117},
    {"YTAdsControlFlowPlaybackCoordinator", "currentAd", (IMP)t118, &o118},
    {"YTAdsControlFlowPlaybackCoordinator", "lastAdTotalMediaTime", (IMP)t119, &o119},
    {"YTAdsControlFlowPlaybackCoordinator", "lastAdVideoID", (IMP)t120, &o120},
    {"YTAdsControlFlowPlaybackCoordinator", "instreamForcedAdParameters", (IMP)t121, &o121},
    {"YTAdsControlFlowPlaybackCoordinator", "setPlayerViewLayout:", (IMP)t122, &o122},
    {"YTAdsControlFlowPlaybackCoordinator", "externalPlaybackActiveDidChange:", (IMP)t123, &o123},
    {"YTAdsControlFlowPlaybackCoordinator", "debugParameters", (IMP)t124, &o124},
    {"YTAdsControlFlowPlaybackCoordinator", "supportsSkippingToUpcomingPlayback", (IMP)t125, &o125},
    {"YTAdsControlFlowPlaybackCoordinator", "supportsOverlaysManagementByAds", (IMP)t126, &o126},
    {"YTAdsControlFlowPlaybackCoordinator", "setAdsManageOverlayLifecycleEnabled:", (IMP)t127, &o127},
    {"YTAdsControlFlowPlaybackCoordinator", "playbackContextForAd", (IMP)t128, &o128},
    {"YTAdsControlFlowPlaybackCoordinator", "autoplayEnabled", (IMP)t129, &o129},
    {"YTAdsControlFlowPlaybackCoordinator", "isOfflinePlayback", (IMP)t130, &o130},
    {"YTAdsControlFlowPlaybackCoordinator", "isPodcastPlayback", (IMP)t131, &o131},
    {"YTAdsControlFlowPlaybackCoordinator", "playerViewLayout", (IMP)t132, &o132},
    {"YTAdsControlFlowPlaybackCoordinator", "contentPlaybackInfoAvailable", (IMP)t133, &o133},
    {"YTAdsControlFlowPlaybackCoordinator", "serviceAvailableForPlayerBytes", (IMP)t134, &o134},
    {"YTAdsControlFlowPlaybackCoordinator", "overlayInAdInterruptIsDisabled", (IMP)t135, &o135},
    {"YTAdsControlFlowPlaybackCoordinator", "setPrerollModeWithMode:", (IMP)t136, &o136},
    {"YTAdsControlFlowPlaybackCoordinator", "singlePlayerBytesLayoutRenderingAdapter:didRequestPlayAnAdInterrupt:forSlot:", (IMP)t137, &o137},
    {"YTAdsControlFlowPlaybackCoordinator", "registerContentVideoPrerollSlot:postrollSlot:midrollSlots:contentCPN:", (IMP)t138, &o138},
    {"YTAdsControlFlowPlaybackCoordinator", "registerContentVideoAdBreakRequestSlot:contentCPN:", (IMP)t139, &o139},
    {"YTAdsControlFlowPlaybackCoordinator", "addNewMidrollSlotDueToThrottling:contentCPN:", (IMP)t140, &o140},
    {"YTAdsControlFlowPlaybackCoordinator", "isAirPlayActive", (IMP)t141, &o141},
    {"YTAdsControlFlowPlaybackCoordinator", "playerVisibility", (IMP)t142, &o142},
    {"YTAdsControlFlowPlaybackCoordinator", "midrollIndex", (IMP)t143, &o143},
    {"YTAdsControlFlowPlaybackCoordinator", "contentVideo", (IMP)t144, &o144},
    {"YTAdsControlFlowPlaybackCoordinator", "isStartUpState", (IMP)t145, &o145},
    {"YTAdsControlFlowPlaybackCoordinator", "CPNForCurrentPlayback", (IMP)t146, &o146},
    {"YTAdsControlFlowPlaybackCoordinator", "addContentPlaybackEventListener:", (IMP)t147, &o147},
    {"YTAdsControlFlowPlaybackCoordinator", "removeContentPlaybackEventListener:", (IMP)t148, &o148},
    {"YTAdsControlFlowPlaybackCoordinator", "addAPIListener:", (IMP)t149, &o149},
    {"YTAdsControlFlowPlaybackCoordinator", "removeAPIListener:", (IMP)t150, &o150},
    {"YTAdsControlFlowPlaybackCoordinator", "addLiveMidrollStatusFromSlot:", (IMP)t151, &o151},
    {"YTAdsControlFlowPlaybackCoordinator", "prebufferAdInterrupt:atMediaTime:", (IMP)t152, &o152},
    {"YTAdsControlFlowPlaybackCoordinator", "cancelPrebufferingAdInterrupt:", (IMP)t153, &o153},
    {"YTAdsControlFlowPlaybackCoordinator", "makeCompletionRequestWithAd:completeType:", (IMP)t154, &o154},
    {"YTAdsControlFlowPlaybackCoordinator", "adBreakTrackingControllerFromAdBreak:slot:layout:", (IMP)t155, &o155},
    {"YTAdsControlFlowPlaybackCoordinator", "adTrackingControllerFromAd:adBreak:slot:layout:", (IMP)t156, &o156},
    {"YTAdsControlFlowPlaybackCoordinator", "discoveryAdPingControllerFromPlayerResponse:videoAdTracking:progressCommands:slot:layout:", (IMP)t157, &o157},
    {"YTAdsControlFlowPlaybackCoordinator", "responder", (IMP)t158, &o158},
    {"YTAdsControlFlowPlaybackCoordinator", "didUnscheduleSlot:", (IMP)t159, &o159},
    {"YTAdsControlFlowPlaybackCoordinator", "singleVideo:currentVideoTimeDidChange:", (IMP)t160, &o160},
    {"YTAdsControlFlowPlaybackCoordinator", "singleVideo:didFailWithError:", (IMP)t161, &o161},
    {"YTAdsControlFlowPlaybackCoordinator", "singleVideo:mediaStateDidChangeFromState:toState:", (IMP)t162, &o162},
    {"YTAdsControlFlowPlaybackCoordinator", "singleVideo:mediaStateDidChangeFromState:toState:stoppageReason:", (IMP)t163, &o163},
    {"YTAdsControlFlowPlaybackCoordinator", "potentiallyMutatedSingleVideo:mediaStateDidChangeFromState:toState:stoppageReason:", (IMP)t164, &o164},
    {"YTAdsControlFlowPlaybackCoordinator", "singleVideo:lifecycleStateDidChangeFromState:toState:", (IMP)t165, &o165},
    {"YTAdsControlFlowPlaybackCoordinator", "adDidShowSkip", (IMP)t166, &o166},
    {"YTAdsControlFlowPlaybackCoordinator", "adDidSkipWithTouchPoint:", (IMP)t167, &o167},
    {"YTAdsControlFlowPlaybackCoordinator", "adDidMuteWithTouchPoint:", (IMP)t168, &o168},
    {"YTAdsControlFlowPlaybackCoordinator", "adDidTapthroughWithTouchPoint:", (IMP)t169, &o169},
    {"YTAdsControlFlowPlaybackCoordinator", "adSlotDidComplete", (IMP)t170, &o170},
    {"YTAdsControlFlowPlaybackCoordinator", "contentVideoThumbnails", (IMP)t171, &o171},
    {"YTAdsControlFlowPlaybackCoordinator", "contentVideoTitle", (IMP)t172, &o172},
    {"YTAdsControlFlowPlaybackCoordinator", "newActiveViewVideoMonitorWithContentPlayerResponse:trafficType:", (IMP)t173, &o173},
    {"YTAdsControlFlowPlaybackCoordinator", "videoAdTrackingControllerWithAd:adBreak:slot:layout:activeViewVideoMonitor:", (IMP)t174, &o174},
    {"YTAdsControlFlowPlaybackCoordinator", "seekToVideoTime:", (IMP)t175, &o175},
    {"YTAdsControlFlowPlaybackCoordinator", "seekToLiveHead", (IMP)t176, &o176},
    {"YTAdsControlFlowPlaybackCoordinator", "createVirtualVideoWithCPNs:", (IMP)t177, &o177},
    {"YTAdsControlFlowPlaybackCoordinator", "prerollAdBreakStatus", (IMP)t178, &o178},
    {"YTAdsControlFlowPlaybackCoordinator", "postrollAdBreakStatus", (IMP)t179, &o179},
    {"YTAdsControlFlowPlaybackCoordinator", "inPlayerExternallyManagedSlotAdapter", (IMP)t180, &o180},
    {"YTAdsControlFlowPlaybackCoordinator", "prepareAdInterrupt:", (IMP)t181, &o181},
    {"YTAdsControlFlowPlaybackCoordinator", "currentContentCPN", (IMP)t182, &o182},
    {"YTAdsControlFlowPlaybackCoordinator", "checkAdBreakStatus:andMaybeFinishAdBreakWithBreakType:", (IMP)t183, &o183},
    {"YTAdsControlFlowPlaybackCoordinator", "slotDidUnscheduleForAdBreakStatus:andMaybeEndWithBreakType:", (IMP)t184, &o184},
    {"YTAdsControlFlowPlaybackCoordinator", "adBreakRequestSlotDidUnscheduleForAdBreakStatus:andMaybeEndWithBreakType:", (IMP)t185, &o185},
    {"YTAdsControlFlowPlaybackCoordinator", "doneWithPlayerBytesSlotWithBreakType:", (IMP)t186, &o186},
    {"YTAdsControlFlowPlaybackCoordinator", "breakTypeStringForBreakType:", (IMP)t187, &o187},
    {"YTAdsControlFlowPlaybackCoordinator", "startObservingAdSingleVideo:", (IMP)t188, &o188},
    {"YTAdsControlFlowPlaybackCoordinator", "updateStateForNewActiveAdSingleVideo:", (IMP)t189, &o189},
    {"YTAdsControlFlowPlaybackCoordinator", "activateOverlayCoordinator", (IMP)t190, &o190},
    {"YTAdsControlFlowPlaybackCoordinator", "currentAdRequestConfig", (IMP)t191, &o191},
    {"YTAdsControlFlowPlaybackCoordinator", "newActiveViewVideoMonitorWithTrafficType:", (IMP)t192, &o192},
    {"YTAdsControlFlowPlaybackCoordinator", "isInlineMutedPlaybackWithOverlayFactory:", (IMP)t193, &o193},
    {"YTAdsControlFlowPlaybackCoordinator", "retrieveMidrollStatusForSlot:", (IMP)t194, &o194},
    {"YTAdsControlFlowPlaybackCoordinator", "activeContentSingleVideo:mediaStateDidChangeToState:", (IMP)t195, &o195},
    {"YTAdsControlFlowPlaybackCoordinator", "activeAdSingleVideo:mediaStateDidChangeToState:", (IMP)t196, &o196},
    {"YTAdsControlFlowPlaybackCoordinator", "deactivateOverlayCoordinator", (IMP)t197, &o197},
    {"YTAdsControlFlowPlaybackCoordinator", "logOverlayErrorWithDescription:", (IMP)t198, &o198},
    {"YTAdsControlFlowPlaybackCoordinator", "lastAdsState", (IMP)t199, &o199},
    {"YTAdsControlFlowPlaybackCoordinator", "currentAdsState", (IMP)t200, &o200},
    {"YTAdsControlFlowPlaybackCoordinator", "parentResponder", (IMP)t201, &o201},
    {"YTAdsControlFlowManagerImpl", "init", (IMP)t202, &o202},
    {"YTAdsControlFlowManagerImpl", "fulfillmentAdapter:didFillSlot:withLayout:", (IMP)t203, &o203},
    {"YTAdsControlFlowManagerImpl", "fulfillmentAdapter:didFailForSlot:errorMessage:", (IMP)t204, &o204},
    {"YTAdsControlFlowManagerImpl", "fulfillmentAdapter:didCancelFulfillmentForSlot:", (IMP)t205, &o205},
    {"YTAdsControlFlowManagerImpl", "layoutRenderingAdapter:didEnterLayoutForSlot:layout:", (IMP)t206, &o206},
    {"YTAdsControlFlowManagerImpl", "layoutRenderingAdapter:didExitLayoutForSlot:layout:layoutExitReason:", (IMP)t207, &o207},
    {"YTAdsControlFlowManagerImpl", "layoutRenderingAdapter:didFailForSlot:layout:errorType:errorMessage:", (IMP)t208, &o208},
    {"YTAdsControlFlowManagerImpl", "layoutRenderingAdapter:message:slot:layout:errorType:externalContext:", (IMP)t209, &o209},
    {"YTAdsControlFlowManagerImpl", "externalContextForSlot:", (IMP)t210, &o210},
    {"YTAdsControlFlowManagerImpl", "onSlotEntered:", (IMP)t211, &o211},
    {"YTAdsControlFlowManagerImpl", "onSlotExited:", (IMP)t212, &o212},
    {"YTAdsControlFlowManagerImpl", "onLayoutEntered:layout:", (IMP)t213, &o213},
    {"YTAdsControlFlowManagerImpl", "onLayoutExitedWithSlot:layout:layoutExitReason:", (IMP)t214, &o214},
    {"YTAdsControlFlowManagerImpl", "onLayoutErrorWithSlot:layout:exception:type:", (IMP)t215, &o215},
    {"YTAdsControlFlowManagerImpl", "slotAdapter:didEnterSlot:", (IMP)t216, &o216},
    {"YTAdsControlFlowManagerImpl", "slotAdapter:didExitSlot:", (IMP)t217, &o217},
    {"YTAdsControlFlowManagerImpl", "slotAdapter:didFailForSlot:errorType:errorMessage:", (IMP)t218, &o218},
    {"YTAdsControlFlowManagerImpl", "slotOpportunityAdapter:didReceiveOpportunity:externalContext:fromSlot:", (IMP)t219, &o219},
    {"YTAdsControlFlowManagerImpl", "slotOpportunityAdapter:didProcessOpportunity:withSlots:externalContext:", (IMP)t220, &o220},
    {"YTAdsControlFlowManagerImpl", "lifecycleDidStartForAdSlots:context:", (IMP)t221, &o221},
    {"YTAdsControlFlowManagerImpl", "registerAndScheduleV2Slot:adOpportunityContext:", (IMP)t222, &o222},
    {"YTAdsControlFlowManagerImpl", "registerAndScheduleV2Layout:adOpportunityContext:", (IMP)t223, &o223},
    {"YTAdsControlFlowManagerImpl", "triggerAdapter:didActivateTriggers:", (IMP)t224, &o224},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didReceiveExternallyManagedSlot:externalContext:", (IMP)t225, &o225},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didScheduleExternallyManagedSlot:externalContext:", (IMP)t226, &o226},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didUnscheduleExternallyManagedSlot:externalContext:", (IMP)t227, &o227},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didEnterExternallyManagedSlot:externalContext:", (IMP)t228, &o228},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didExitExternallyManagedSlot:externalContext:", (IMP)t229, &o229},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didReceiveExternallyManagedLayout:forSlot:externalContext:", (IMP)t230, &o230},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didScheduleExternallyManagedLayout:forSlot:externalContext:", (IMP)t231, &o231},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didUnscheduleExternallyManagedLayout:forSlot:", (IMP)t232, &o232},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didEnterExternallyManagedLayout:forSlot:externalContext:", (IMP)t233, &o233},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:didExitExternallyManagedLayout:forSlot:exitReason:externalContext:", (IMP)t234, &o234},
    {"YTAdsControlFlowManagerImpl", "externallyManagedSlotAdapter:message:slot:layout:errorType:externalContext:", (IMP)t235, &o235},
    {"YTAdsControlFlowManagerImpl", "appWillResignActive", (IMP)t236, &o236},
    {"YTAdsControlFlowManagerImpl", "maybeUnscheduleSlot:isDueToError:", (IMP)t237, &o237},
    {"YTAdsControlFlowManagerImpl", "retrieveRenderingEventThrottlingTrackerForSlot:tier:", (IMP)t238, &o238},
    {"YTAdsControlFlowManagerImpl", "renderingEventThrottlingStatusWithSlot:tier:", (IMP)t239, &o239},
    {"YTAdsControlFlowManagerImpl", "incrementRenderingEventCountWithSlot:tier:", (IMP)t240, &o240},
    {"YTAdsControlFlowManagerImpl", "setThrottlingCapacity:forSlotType:", (IMP)t241, &o241},
    {"YTAdsControlFlowManagerImpl", "resetThrottlingCapacityForSlotType:", (IMP)t242, &o242},
    {"YTAdsControlFlowManagerImpl", "getThrottlingCapacityForSlot:", (IMP)t243, &o243},
    {"YTAdsControlFlowManagerImpl", "performSlotEnteredActions:", (IMP)t244, &o244},
    {"YTAdsControlFlowManagerImpl", "performSlotExitedActions:", (IMP)t245, &o245},
    {"YTAdsControlFlowManagerImpl", "performLayoutExitedActionsForSlot:layout:exitReason:", (IMP)t246, &o246},
    {"YTAdsControlFlowManagerImpl", "performLayoutEnteredActionsForSlot:layout:", (IMP)t247, &o247},
    {"YTAdsControlFlowManagerImpl", "unblockTriggerReceptionForSlot:dueToError:", (IMP)t248, &o248},
    {"YTAdsControlFlowManagerImpl", "handleActivationForTriggerBundles:", (IMP)t249, &o249},
    {"YTAdsControlFlowManagerImpl", "onServerTriggersActivated:", (IMP)t250, &o250},
    {"YTAdsControlFlowManagerImpl", "scheduleSlot:externalContext:", (IMP)t251, &o251},
    {"YTAdsControlFlowManagerImpl", "unscheduleSlot:isDueToError:", (IMP)t252, &o252},
    {"YTAdsControlFlowManagerImpl", "onLayoutUnscheduled:layout:externalContext:", (IMP)t253, &o253},
    {"YTAdsControlFlowManagerImpl", "maybeStartRenderingLayoutForSlot:", (IMP)t254, &o254},
    {"YTAdsControlFlowManagerImpl", "processLayoutExitTriggersWithTriggerCategory:inTriggerBundles:dueToLayoutExitReason:", (IMP)t255, &o255},
    {"YTAdsControlFlowManagerImpl", "processLayoutExitServerTriggersWithTriggerCategory:inTriggerBundles:dueToLayoutExitReason:", (IMP)t256, &o256},
    {"YTAdsControlFlowManagerImpl", "processExpirationTriggersInTriggerBundles:", (IMP)t257, &o257},
    {"YTAdsControlFlowManagerImpl", "processExpirationServerTriggersInTriggerBundles:", (IMP)t258, &o258},
    {"YTAdsControlFlowManagerImpl", "processFulfillmentTriggersInTriggerBundles:", (IMP)t259, &o259},
    {"YTAdsControlFlowManagerImpl", "processEntryTriggersInTriggerBundles:", (IMP)t260, &o260},
    {"YTAdsControlFlowManagerImpl", "processEntryServerTriggersInTriggerBundles:", (IMP)t261, &o261},
    {"YTAdsControlFlowManagerImpl", "stopRenderingLayoutWithSlot:layout:layoutExitReason:isDueToError:", (IMP)t262, &o262},
    {"YTAdsControlFlowManagerImpl", "exitSlot:isDueToError:", (IMP)t263, &o263},
    {"YTAdsControlFlowManagerImpl", "logLayoutExitReason:slot:layout:externalContext:", (IMP)t264, &o264},
    {"YTAdsControlFlowManagerImpl", "buildErrorHandlingBlockWithErrorType:slot:externalContext:", (IMP)t265, &o265},
    {"YTAdsControlFlowManagerImpl", "buildErrorHandlingBlockWithErrorType:slot:layout:externalContext:", (IMP)t266, &o266},
    {"YTAdsControlFlowManagerImpl", "pingDispatchDelegate:forSlot:forLayout:", (IMP)t267, &o267},
    {"YTAdsControlFlowManagerImpl", "retrieveThrottlingCapacityForSlot:", (IMP)t268, &o268},
    {"YTAdsControlFlowManagerImpl", "eventCenter", (IMP)t269, &o269},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "init", (IMP)t270, &o270},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "buildAndRegisterSlotsFromPlaybackData:", (IMP)t271, &o271},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "gaplessBuildAndRegisterSlotsFromPlaybackData:", (IMP)t272, &o272},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "setInstreamAdBreakLifecycleAPI:", (IMP)t273, &o273},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "handleDiscoverySlotsFromPlayerResponse:contentCPN:", (IMP)t274, &o274},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "addPlayerBytesAndForecastingSlotsFromPlayerResponse:intoSlotArray:contentCPN:cachedAdIntro:isIosEnableAdBreakRequestSlot:", (IMP)t275, &o275},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "playerBytesSlotsFromOfflinePlayerResponse:contentCPN:cachedAdIntro:", (IMP)t276, &o276},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "playerBytesAndForecastingSlotsFromOnlinePlayerResponse:adsSupportedRenderers:contentCPN:cachedAdIntro:isIosEnableAdBreakRequestSlot:", (IMP)t277, &o277},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "createPlayerBytesSlotFromAdSlot:contentCPN:adSlot:adBreaks:isGapless:DAIMetadata:", (IMP)t278, &o278},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "adArrayFromPlayerBytesAdLayoutRenderer:adBreaks:", (IMP)t279, &o279},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "maybeAddVideoAdRendererFromRenderingContent:toArray:", (IMP)t280, &o280},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "maybeAddSurveyAdRendererFromRenderingContent:toArray:", (IMP)t281, &o281},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "maybeAddSurveyTextInterstitialRendererFromRenderingContent:toArray:", (IMP)t282, &o282},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "gaplessPlayerBytesSlotsFromPlayerResponse:adBreaks:contentCPN:cachedAdIntro:containsPrerollInAdSlotRenderer:enableAdBreakRequestSlot:", (IMP)t283, &o283},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "prerollPlayerBytesSlotFromOnlinePlayerResponse:adsSupportedRenderers:contentCPN:cachedAdIntro:", (IMP)t284, &o284},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "adBreakRequestSlotsFromOnlinePlayerResponse:adsSupportedRenderers:slots:contentCPN:cachedAdIntro:isIosEnableAdBreakRequestSlot:", (IMP)t285, &o285},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "gaplessAdBreakRequestSlotsFromOnlinePlayerResponse:sortedAdBreaks:contentCPN:cachedAdIntro:", (IMP)t286, &o286},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "slotForAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:", (IMP)t287, &o287},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "slotForAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:isGapless:", (IMP)t288, &o288},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "containsForecastingAdRendererInAdBreak:", (IMP)t289, &o289},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "adBreakRequestSlotForAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:isGapless:", (IMP)t290, &o290},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "adBreakRequestSlotForAdBreak:nextAdBreak:contentCPN:contentPlayerResponse:cachedAdIntro:", (IMP)t291, &o291},
    {"YTContentVideoPlayerResponseSlotOpportunityAdapterImpl", "getMediaLayoutIdsFromPlayerBytesAdLayoutRenderer:", (IMP)t292, &o292},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "init", (IMP)t293, &o293},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "hasPlayerBytesSlotInAdSlotsArray:", (IMP)t294, &o294},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "processThrottledAdBreakResponse:contentCPN:contentPlayerResponse:", (IMP)t295, &o295},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "onAdBreakResponseReceivedWithAdSlotRenderers:contentCPN:contentPlayerResponse:adBreak:adBreakResponse:", (IMP)t296, &o296},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "containsPlayerBytesSlot:", (IMP)t297, &o297},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "slotRendererFromAdSlotRenderer:", (IMP)t298, &o298},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "legacyAdBreakResponseAndProcessAdBreak:", (IMP)t299, &o299},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "adArrayFromPlayerBytesAdLayoutRenderer:adBreaks:", (IMP)t300, &o300},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "maybeAddVideoAdRendererFromRenderingContent:toArray:", (IMP)t301, &o301},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "maybeAddSurveyAdRendererFromRenderingContent:toArray:", (IMP)t302, &o302},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "maybeAddSurveyTextInterstitialRendererFromRenderingContent:toArray:", (IMP)t303, &o303},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "getMediaLayoutsIds:", (IMP)t304, &o304},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "playerAdsFromAdBreakResponse:", (IMP)t305, &o305},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "containsBelowPlayerImmersiveSlot:", (IMP)t306, &o306},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "eligibleAdsFromThrottledAdBreakResponse:", (IMP)t307, &o307},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "makeWatchNextRequestWithInstreamAdsForDAILegacy:", (IMP)t308, &o308},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "makeWatchNextRequestWithInstreamAdsForDAI:mediaLayoutIds:contentCPN:playerResponse:", (IMP)t309, &o309},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "playableAdsFromAds:", (IMP)t310, &o310},
    {"YTAdBreakResponseReceivedOpportunityAdapterImpl", "scheduleNewPauseAdBreakRequestSlotFromSlot:adBreak:contentCPN:externalContext:", (IMP)t311, &o311},
    {"YTAdBreakResponseReceivedOpportunityAdapterV2", "initWithAdsControlFlowManagerV2Handling:", (IMP)t312, &o312},
    {"YTAdBreakResponseReceivedOpportunityAdapterV2", "didReceiveAdBreakResponse:fromAdBreakSlot:", (IMP)t313, &o313},
    {"YTCommandDrivenExternallyManagedSlotOpportunityAdapter", "init", (IMP)t314, &o314},
    {"YTCommandDrivenExternallyManagedSlotOpportunityAdapter", "didReceiveCommand:fromSender:", (IMP)t315, &o315},
    {"YTCommandDrivenExternallyManagedSlotOpportunityAdapter", "slotsFromCommand:", (IMP)t316, &o316},
    {"YTAdsControlFlowOpportunityReceivedCommandHandlerImpl", "executeWithCommand:entry:fromView:sender:", (IMP)t317, &o317},
    {"YTBaseOpportunityAdapter", "initWithOpportunityType:adsControlFlowManagerV2Handling:", (IMP)t318, &o318},
    {"YTBaseOpportunityAdapter", "didReceiveAdSlots:adOpportunityContext:", (IMP)t319, &o319},
    {"YTBaseOpportunityAdapter", "opportunityType", (IMP)t320, &o320},
    {"YTBaseOpportunityAdapter", "getClientSlots:adOpportunityContext:", (IMP)t321, &o321},
    {"YTBaseOpportunityAdapter", "buildServerSlots:adOpportunityContext:", (IMP)t322, &o322},
    {"YTBaseOpportunityAdapter", "createSlotFromAdSlotRenderer:", (IMP)t323, &o323},
    {"YTAdBreakServiceImpl", "initWithAccountID:", (IMP)t324, &o324},
    {"YTAdBreakServiceImpl", "makeAdBreakRequest:responseBlock:errorBlock:", (IMP)t325, &o325},
    {"YTAdBreakServiceImpl", "makeAdBreakRequest:responseBlock:errorBlock:retryEnabled:", (IMP)t326, &o326},
    {"YTAdBreakRendererFetcher", "makeWatchNextRequestWithInstreamAdsLegacy:CSILoggingResponder:", (IMP)t327, &o327},
    {"YTAdBreakRendererFetcher", "makeWatchNextRequestWithInstreamAds:playerResponse:contentCPN:layout:slot:", (IMP)t328, &o328},
    {"YTAdBreakRendererFetcher", "matchingMediaLayoutIdFromLayout:slot:ad:", (IMP)t329, &o329},
    {"YTAdBreakRendererFetcher", "makeWatchNextRequestWithInstreamAd:CSILoggingResponder:playerBytesLayoutID:contentCPN:playerResponse:iosSdfCompanionPrecursor:", (IMP)t330, &o330},
    {"YTAdInterrupt", "initWithAd:adBreak:timingData:", (IMP)t331, &o331},
    {"YTAdInterrupt", "initWithAd:adBreak:timingData:adPlaybackData:", (IMP)t332, &o332},
    {"YTAdInterrupt", "init", (IMP)t333, &o333},
    {"YTAdInterrupt", "isEqual:", (IMP)t334, &o334},
    {"YTAdInterrupt", "hash", (IMP)t335, &o335},
    {"YTAdInterrupt", "rootExitFadeOut", (IMP)t336, &o336},
    {"YTAdInterrupt", "rootEnterFadeIn", (IMP)t337, &o337},
    {"YTAdInterrupt", "ad", (IMP)t338, &o338},
    {"YTAdInterrupt", "adBreak", (IMP)t339, &o339},
    {"YTAdInterrupt", "initialMediaTime", (IMP)t340, &o340},
    {"YTAdInterrupt", "setInitialMediaTime:", (IMP)t341, &o341},
    {"YTAdInterrupt", "adPlaybackData", (IMP)t342, &o342},
    {"YTAdInterrupt", "adOverlay", (IMP)t343, &o343},
    {"YTAdInterrupt", "setAdOverlay:", (IMP)t344, &o344},
    {"YTAdInterrupt", "timingData", (IMP)t345, &o345},
    {"YTAdInterrupt", "holdingAdBreak", (IMP)t346, &o346},
    {"YTAdInterrupt", "setHoldingAdBreak:", (IMP)t347, &o347},
    {"YTAdInterrupt", "upcomingContentRewindOffset", (IMP)t348, &o348},
    {"YTAdInterrupt", "setUpcomingContentRewindOffset:", (IMP)t349, &o349},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "initWithSlot:", (IMP)t350, &o350},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "cancelFillingSlot", (IMP)t351, &o351},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "fillSlot", (IMP)t352, &o352},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "adCuepointAPI:didReceiveCuepoint:", (IMP)t353, &o353},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "adCuepointAPI:noCuepointReceivedSinceTime:", (IMP)t354, &o354},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "playbackTimelinePlaceholderSegmentStatus", (IMP)t355, &o355},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "playableAdsFromAds:", (IMP)t356, &o356},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "insertPlaceholderSegmentAndMaybeMakeAdBreakRequestWithCuepoint:", (IMP)t357, &o357},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "processAdBreakResponse:originalAdBreak:playerResponse:contentCPN:", (IMP)t358, &o358},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "updatePlaceholderSegmentWithCuepoint:", (IMP)t359, &o359},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "removePlaceholderSegmentFromPlaybackTimeline", (IMP)t360, &o360},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "playerAdsFromAdBreakResponse:", (IMP)t361, &o361},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "eligibleAdsFromThrottledAdBreakResponse:", (IMP)t362, &o362},
    {"YTPlayerBytesDAISlotFulfillmentAdapter", "matchingCueIdentifier", (IMP)t363, &o363},
    {"YTPlayerBytesSlotFulfillmentAdapter", "initWithSlot:", (IMP)t364, &o364},
    {"YTPlayerBytesSlotFulfillmentAdapter", "cancelFillingSlot", (IMP)t365, &o365},
    {"YTPlayerBytesSlotFulfillmentAdapter", "fillSlot", (IMP)t366, &o366},
    {"YTPlayerBytesSlotFulfillmentAdapter", "hasFulfilledLayout:", (IMP)t367, &o367},
    {"YTPlayerBytesSlotFulfillmentAdapter", "processAdRenderers:adBreakResponse:originalAdBreak:playerResponse:adWatchNextParams:isGapless:", (IMP)t368, &o368},
    {"YTPlayerBytesSlotFulfillmentAdapter", "firstPrerollAdBreakInArray:", (IMP)t369, &o369},
    {"YTPlayerBytesSlotFulfillmentAdapter", "makeOfflineAdRequestWithAdBreak:andFulfillSlot:", (IMP)t370, &o370},
    {"YTPlayerBytesSlotFulfillmentAdapter", "firstForecastingAdInAds:", (IMP)t371, &o371},
    {"YTPlayerBytesSlotFulfillmentAdapter", "sendCSILogWhenWillRequestAdBreak", (IMP)t372, &o372},
    {"YTPlayerBytesSlotFulfillmentAdapter", "sendCSILogWhenAdBreakResponseReceived", (IMP)t373, &o373},
    {"YTPlayerBytesSlotFulfillmentAdapter", "playerAdsFromAdBreakResponse:", (IMP)t374, &o374},
    {"YTPlayerBytesSlotFulfillmentAdapter", "currentMediaTimeFromContentVideo", (IMP)t375, &o375},
    {"YTPlayerBytesSlotFulfillmentAdapter", "enableAdBreakRequestSlotWithGaplessEnabled:breakType:", (IMP)t376, &o376},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "initWithSlot:", (IMP)t377, &o377},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "cancelFillingSlot", (IMP)t378, &o378},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "fillSlot", (IMP)t379, &o379},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "adCuepointAPI:didReceiveCuepoint:", (IMP)t380, &o380},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "adCuepointAPI:noCuepointReceivedSinceTime:", (IMP)t381, &o381},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "playbackTimelinePlaceholderSegmentStatus", (IMP)t382, &o382},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "sendCSILogWhenWillRequestAdBreak", (IMP)t383, &o383},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "sendCSILogWhenAdBreakResponseReceived", (IMP)t384, &o384},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "processAdBreakResponse:", (IMP)t385, &o385},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "currentMediaTimeFromContentVideo", (IMP)t386, &o386},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "updatePlaceholderSegmentWithCuepoint:", (IMP)t387, &o387},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "insertPlaceholderSegmentAndMaybeMakeAdBreakRequestForDAI", (IMP)t388, &o388},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "removePlaceholderSegmentFromPlaybackTimeline", (IMP)t389, &o389},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "maybeMakeAdBreakRequestForNonDAI", (IMP)t390, &o390},
    {"YTAdBreakRequestSlotFulfillmentAdapter", "matchingCueIdentifier", (IMP)t391, &o391},
    {"YTPlayerResponse", "initWithPlayerData:responseDate:offlineStateDate:mutableState:trailer:", (IMP)t392, &o392},
    {"YTPlayerResponse", "initWithPlayerData:responseDate:offlineStateDate:mutableState:trailer:offlineRentalActivated:", (IMP)t393, &o393},
    {"YTPlayerResponse", "adPlayerResponse", (IMP)t394, &o394},
    {"YTPlayerResponse", "trailerPlayerResponse", (IMP)t395, &o395},
    {"YTPlayerResponse", "isDAICompatible", (IMP)t396, &o396},
    {"YTPlayerResponse", "videoID", (IMP)t397, &o397},
    {"YTPlayerResponse", "timeUntilStreamingDataExpirySeconds", (IMP)t398, &o398},
    {"YTPlayerResponse", "areStreamsCloseToExpiringIfPlaybackStartsNow", (IMP)t399, &o399},
    {"YTPlayerResponse", "isExpiredByMaxAgeSeconds", (IMP)t400, &o400},
    {"YTPlayerResponse", "isValid", (IMP)t401, &o401},
    {"YTPlayerResponse", "setCacheContext:", (IMP)t402, &o402},
    {"YTPlayerResponse", "setReuse:", (IMP)t403, &o403},
    {"YTPlayerResponse", "setLatencyLogger:", (IMP)t404, &o404},
    {"YTPlayerResponse", "setPlayerCompatibility:", (IMP)t405, &o405},
    {"YTPlayerResponse", "isPlayableInPictureInPicture", (IMP)t406, &o406},
    {"YTPlayerResponse", "isPipOffByDefault", (IMP)t407, &o407},
    {"YTPlayerResponse", "shouldPipResumeOnHead", (IMP)t408, &o408},
    {"YTPlayerResponse", "setServerStitchedDisabled:", (IMP)t409, &o409},
    {"YTPlayerResponse", "serverStitchedEventCenter", (IMP)t410, &o410},
    {"YTPlayerResponse", "playerData", (IMP)t411, &o411},
    {"YTPlayerResponse", "responseDate", (IMP)t412, &o412},
    {"YTPlayerResponse", "offlineStateDate", (IMP)t413, &o413},
    {"YTPlayerResponse", "mutableState", (IMP)t414, &o414},
    {"YTPlayerResponse", "isTrailer", (IMP)t415, &o415},
    {"YTPlayerResponse", "QOEController", (IMP)t416, &o416},
    {"YTPlayerResponse", "setQOEController:", (IMP)t417, &o417},
    {"YTPlayerResponse", "cacheContext", (IMP)t418, &o418},
    {"YTPlayerResponse", "isReuse", (IMP)t419, &o419},
    {"YTPlayerResponse", "isOfflineRentalActivated", (IMP)t420, &o420},
    {"YTPlayerResponse", "latencyLogger", (IMP)t421, &o421},
    {"YTPlayerResponse", "playerCompatibility", (IMP)t422, &o422},
    {"YTPlayerResponse", "isDAIDisabled", (IMP)t423, &o423},
    {"YTPlayerResponse", "setDAIDisabled:", (IMP)t424, &o424},
    {"YTPlayerResponse", "cacheKey", (IMP)t425, &o425},
    {"YTIPlayerResponse", "offlineUpsell", (IMP)t426, &o426},
    {"YTIPlayerResponse", "backgroundUpsell", (IMP)t427, &o427},
    {"YTIPlayerResponse", "isMonetized", (IMP)t428, &o428},
    {"YTIPlayerResponse", "isLivePlayback", (IMP)t429, &o429},
    {"YTIPlayerResponse", "storyboardSpec", (IMP)t430, &o430},
    {"YTIPlayerResponse", "liveStoryboardSpec", (IMP)t431, &o431},
    {"YTIPlayerResponse", "hasTracklistCaptionTracks", (IMP)t432, &o432},
    {"YTIPlayerResponse", "adIntroRenderer", (IMP)t433, &o433},
    {"YTIPlayerResponse", "canBeEnqueuedGaplessly", (IMP)t434, &o434},
    {"YTIPlayerResponse", "canEnqueueUpcomingPlaybacks", (IMP)t435, &o435},
    {"YTIPlayerResponse", "isDAIEnabledPlayback", (IMP)t436, &o436},
    {"YTIPlayerResponse", "isCuepointAdsEnabled", (IMP)t437, &o437},
    {"YTIPlayerResponse", "hasPrerollAds", (IMP)t438, &o438},
    {"YTIPlayerResponse", "mutedAtStart", (IMP)t439, &o439},
    {"YTIPlayerResponse", "isAudioOnlyAvailabilityBlocked", (IMP)t440, &o440},
    {"YTIPlayerResponse", "audioOnlyPlayabilityRenderer", (IMP)t441, &o441},
    {"YTIPlayerResponse", "isWindowedLive", (IMP)t442, &o442},
    {"YTIPlayerResponse", "paidContentOverlayElementRendererOptions", (IMP)t443, &o443},
    {"YTIPlayerResponse", "deferredPlayerTokenWithIdentifier:", (IMP)t444, &o444},
    {"YTIPlayerResponse", "shouldCacheResponse", (IMP)t445, &o445},
    {"YTIPlayerResponse", "aspectRatio", (IMP)t446, &o446},
    {"YTIPlayerResponse", "duration", (IMP)t447, &o447},
    {"YTIPlayerResponse", "yt_formatStreamForPreferredVideoQuality:withCap:", (IMP)t448, &o448},
    {"YTIPlayerResponse", "adBreaksWithVMAPParser:error:", (IMP)t449, &o449},
    {"YTIPlayerResponse", "adBreaksWithVMAPParser:VMAPXMLString:error:", (IMP)t450, &o450},
    {"YTIPlayerResponse", "remoteAdURLsWithVMAPParser:error:", (IMP)t451, &o451},
    {"YTIPlayerResponse", "VMAPXMLString", (IMP)t452, &o452},
    {"YTIPlayerResponse", "fillHostVideoID:inVMAPAdBreaks:", (IMP)t453, &o453},
    {"YTIPlayerResponse", "adsAllowReuse", (IMP)t454, &o454},
    {"YTIPlayerResponse", "containsDiscoverySlotsOpportunity", (IMP)t455, &o455},
    {"YTIPlayerResponse", "hasVideoAdTrackingRenderer", (IMP)t456, &o456},
    {"YTIPlayerResponse", "yt_formatStreamForPreferredAudioQuality:", (IMP)t457, &o457},
    {"YTIPlayerResponse", "autoSpeedCueRangeSet", (IMP)t458, &o458},
    {"YTAdSlotRendererAdapter", "initWithPrerollAdSlotRendererLegacy:", (IMP)t459, &o459},
    {"YTAdSlotRendererAdapter", "initWithAdSlotRenderer:", (IMP)t460, &o460},
    {"YTAdSlotRendererAdapter", "isPreroll", (IMP)t461, &o461},
    {"YTAdSlotRendererAdapter", "isPostroll", (IMP)t462, &o462},
    {"YTAdSlotRendererAdapter", "type", (IMP)t463, &o463},
    {"YTAdSlotRendererAdapter", "adSlotLoggingData", (IMP)t464, &o464},
    {"YTAdSlotRendererAdapter", "absoluteOffsetWithVideoLength:", (IMP)t465, &o465},
    {"YTAdSlotRendererAdapter", "timeOffsetMilliseconds", (IMP)t466, &o466},
    {"YTAdSlotRendererAdapter", "prefetchIntervalMs", (IMP)t467, &o467},
    {"YTAdSlotRendererAdapter", "timeOffset", (IMP)t468, &o468},
    {"YTAdSlotRendererAdapter", "ads", (IMP)t469, &o469},
    {"YTAdSlotRendererAdapter", "podRemainingTimeWithAd:", (IMP)t470, &o470},
    {"YTAdSlotRendererAdapter", "midrollOffsetStartMilliseconds", (IMP)t471, &o471},
    {"YTAdSlotRendererAdapter", "sendYTClientError:", (IMP)t472, &o472},
    {"YTAdSlotRendererAdapter", "adSlotRenderer", (IMP)t473, &o473},
    {"YTAdBreakRendererAdapter", "initWithAdBreakRenderer:", (IMP)t474, &o474},
    {"YTAdBreakRendererAdapter", "breakStartPings", (IMP)t475, &o475},
    {"YTAdBreakRendererAdapter", "breakEndPings", (IMP)t476, &o476},
    {"YTAdBreakRendererAdapter", "isPreroll", (IMP)t477, &o477},
    {"YTAdBreakRendererAdapter", "isPostroll", (IMP)t478, &o478},
    {"YTAdBreakRendererAdapter", "type", (IMP)t479, &o479},
    {"YTAdBreakRendererAdapter", "adSlotLoggingData", (IMP)t480, &o480},
    {"YTAdBreakRendererAdapter", "absoluteOffsetWithVideoLength:", (IMP)t481, &o481},
    {"YTAdBreakRendererAdapter", "timeOffsetMilliseconds", (IMP)t482, &o482},
    {"YTAdBreakRendererAdapter", "prefetchIntervalMs", (IMP)t483, &o483},
    {"YTAdBreakRendererAdapter", "timeOffset", (IMP)t484, &o484},
    {"YTAdBreakRendererAdapter", "ads", (IMP)t485, &o485},
    {"YTAdBreakRendererAdapter", "podRemainingTimeWithAd:", (IMP)t486, &o486},
    {"YTAdBreakRendererAdapter", "copyWithZone:", (IMP)t487, &o487},
    {"YTAdBreakRendererAdapter", "createAds", (IMP)t488, &o488},
    {"YTAdBreakRendererAdapter", "adBreakRenderer", (IMP)t489, &o489},
    {"YTAdClientOrganicMetadata", "init:adSlotRenderers:", (IMP)t490, &o490},
    {"YTAdClientOrganicMetadata", "adSlotRenderers", (IMP)t491, &o491},
    {"YTAdClientOrganicMetadata", "reelWatchEndpoint", (IMP)t492, &o492},
};

void YTTraceInstall(void) {
    if (!YTModBool(@"ad_trace", YES)) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        int n = 0;
        for (int i = 0; i < (int)(sizeof(g_entries)/sizeof(g_entries[0])); i++) {
            Class c = objc_getClass(g_entries[i].cls);
            if (!c) continue;
            Method m = class_getInstanceMethod(c, sel_registerName(g_entries[i].sel));
            if (!m) continue;
            *g_entries[i].orig = method_getImplementation(m);
            class_replaceMethod(c, sel_registerName(g_entries[i].sel), g_entries[i].hook, method_getTypeEncoding(m));
            n++;
        }
        YTModLog(@"trace: %d/%d method gắn", n, (int)(sizeof(g_entries)/sizeof(g_entries[0])));
    });
}
