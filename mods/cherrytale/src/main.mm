// Điểm vào của dylib. Dylib nạp như dependency của UnityFramework nên hàm
// constructor chạy rất sớm — mọi việc UI phải đẩy về main queue.
#import "common.h"

#ifndef CT_RECON_PHASE
#define CT_RECON_PHASE 0
#endif
#ifndef CT_SAFE_BUILD
#define CT_SAFE_BUILD 0
#endif

static dispatch_source_t g_pollTimer = NULL;
static int g_pollTicks = 0;
static BOOL g_reconDone = NO;

static void ct_on_il2cpp_ready(void) {
    CTLog(@"il2cpp sẵn sàng sau %d lần chờ", g_pollTicks);

    if (CT_RECON_PHASE || CT_SAFE_BUILD) {
        if (!g_reconDone) {
            g_reconDone = YES;
            // chờ thêm 2 giây cho metadata ổn định rồi mới tra class
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                CTReconRun();
                CTLog(@"recon xong");
            });
        }
    }

    if (CT_RECON_PHASE) {
        CTHooksMarkUnavailable("bản recon: không cài hook");
        CTLog(@"phase=recon: bỏ qua cài hook");
        CTUIRefresh();
        return;
    }

    if (CT_SAFE_BUILD) {
        CTHooksMarkUnavailable("bản _safe: không cài hook");
        CTLog(@"phase=safe: bỏ qua cài hook");
        CTUIRefresh();
        return;
    }

    if (CTEmergencyDisabled()) {
        CTHooksMarkUnavailable("đã tắt khẩn cấp ở lần chạy trước");
        CTLog(@"hooks: đang ở chế độ tắt khẩn cấp");
        CTUIRefresh();
        return;
    }

    // Cài muộn: chờ scene đầu tiên ổn định rồi mới hook.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CTLog(@"hooks: bắt đầu cài (muộn)");
        CTHooksInstallAll();
        CTUIRefresh();
    });
}

static void ct_poll(void) {
    g_pollTicks++;
    // Chờ ~2 giây đầu cho runtime ổn định rồi mới resolve trên main thread.
    BOOL ready = (g_pollTicks > 4) ? CTIL2CPPTryInit() : CTIL2CPPReady();
    if (ready) {
        if (g_pollTimer) { dispatch_source_cancel(g_pollTimer); g_pollTimer = NULL; }
        ct_on_il2cpp_ready();
        return;
    }
    if (g_pollTicks > 240) { // ~120 giây
        CTLog(@"il2cpp: quá thời gian chờ, dừng poll");
        if (g_pollTimer) { dispatch_source_cancel(g_pollTimer); g_pollTimer = NULL; }
        CTHooksMarkUnavailable("il2cpp không khởi tạo");
        CTUIRefresh();
    }
}

static void ct_start_poll(void) {
    g_pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(g_pollTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(0.5 * NSEC_PER_SEC), (uint64_t)(0.05 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(g_pollTimer, ^{ ct_poll(); });
    dispatch_resume(g_pollTimer);
}

__attribute__((constructor)) static void ct_dylib_init(void) {
    @autoreleasepool {
        CTLog(@"dylib nạp: recon=%d safe=%d", CT_RECON_PHASE, CT_SAFE_BUILD);
        CTStaticSetup();   // phải chạy trước khi UnityFramework thực thi code
        CTHooksLoadConfig();
        CTIL2CPPStart();

        dispatch_async(dispatch_get_main_queue(), ^{
            CTUIStart();
            ct_start_poll();
        });
    }
}
