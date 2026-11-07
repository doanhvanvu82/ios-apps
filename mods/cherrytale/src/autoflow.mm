// Liệt kê các phần tử bấm được đang active (BtnClickEvent + UnityEngine.UI.Button)
// kèm nhãn, trạng thái callback và ước lượng hiển thị. Chỉ để chẩn đoán.
#import "common.h"

#include <string.h>

static BOOL g_ready = NO;
static void *clsButton = NULL, *clsTMP = NULL, *clsText = NULL, *clsObject = NULL, *clsComp = NULL;
static void *clsBtnClick = NULL, *clsGraphic = NULL;
static void *typeButton = NULL, *typeTMP = NULL, *typeText = NULL;
static void *typeBtnClick = NULL, *typeGraphic = NULL;
static void *mFind = NULL, *mGetName = NULL, *mGetComp = NULL, *mGetTextTMP = NULL, *mGetTextUI = NULL;
static void *mGetCanvasRenderer = NULL, *mGetCull = NULL;
static size_t offOnBtnCall = 0, offOnBtnCustom = 0;
static BOOL btnClickOK = NO;

static void dump_setup(void) {
    if (g_ready) return;
    clsButton = CTFindClassNS("UnityEngine.UI", "Button");
    clsTMP    = CTFindClassNS("TMPro", "TMP_Text");
    clsText   = CTFindClassNS("UnityEngine.UI", "Text");
    clsObject = CTFindClassNS("UnityEngine", "Object");
    clsComp   = CTFindClassNS("UnityEngine", "Component");
    clsBtnClick = CTFindClass("BtnClickEvent");
    clsGraphic = CTFindClassNS("UnityEngine.UI", "Graphic");

    if (!clsObject || !clsComp) return;
    mFind     = CTFindMethod(clsObject, "FindObjectsOfType", 1);
    mGetName  = CTFindMethod(clsObject, "get_name", 0);
    mGetComp  = CTFindMethod(clsComp, "GetComponentInChildren", 2);
    if (clsButton) {
        typeButton = CTTypeObject(clsButton);
    }
    if (clsTMP) {
        mGetTextTMP = CTFindMethod(clsTMP, "get_text", 0);
        typeTMP = CTTypeObject(clsTMP);
    }
    if (clsText) {
        mGetTextUI = CTFindMethod(clsText, "get_text", 0);
        typeText = CTTypeObject(clsText);
    }
    if (clsGraphic) {
        typeGraphic = CTTypeObject(clsGraphic);
        mGetCanvasRenderer = CTFindMethod(clsGraphic, "get_canvasRenderer", 0);
        void *clsCR = CTFindClassNS("UnityEngine", "CanvasRenderer");
        if (clsCR) mGetCull = CTFindMethod(clsCR, "get_cull", 0);
    }
    if (clsBtnClick && clsComp) {
        typeBtnClick = CTTypeObject(clsBtnClick);
        BOOL a = CTFindFieldOffset(clsBtnClick, "OnBtnClickCall", &offOnBtnCall);
        BOOL b = CTFindFieldOffset(clsBtnClick, "m_OnBtnClickCallWithCustomObj", &offOnBtnCustom);
        btnClickOK = (typeBtnClick && (a || b));
    }
    g_ready = mFind && mGetName && mGetComp;
}

static void *find_all(void *type) {
    if (!type || !mFind) return NULL;
    void *(*fn)(void *) = (void *(*)(void *)) CTMethodPtr(mFind);
    return fn(type);
}

static NSString *obj_name(void *obj) {
    if (!obj || !mGetName) return nil;
    void *(*fn)(void *) = (void *(*)(void *)) CTMethodPtr(mGetName);
    return CTString(fn(obj));
}

static NSString *component_label(void *comp) {
    if (!comp || !mGetComp) return nil;
    void *(*fn)(void *, void *, bool) = (void *(*)(void *, void *, bool)) CTMethodPtr(mGetComp);
    if (typeTMP && mGetTextTMP) {
        void *g = fn(comp, typeTMP, true);
        if (g) {
            void *m = CTVirtualMethod(g, mGetTextTMP);
            if (m) return CTString(((void *(*)(void *)) CTMethodPtr(m))(g));
        }
    }
    if (typeText && mGetTextUI) {
        void *g = fn(comp, typeText, true);
        if (g) {
            void *m = CTVirtualMethod(g, mGetTextUI);
            if (m) return CTString(((void *(*)(void *)) CTMethodPtr(m))(g));
        }
    }
    return nil;
}

// Ước lượng hiển thị: CanvasGroup cha alpha>0 và Graphic không bị cull.
static BOOL component_visible(void *comp) {
    if (mGetComp && typeGraphic && mGetCanvasRenderer && mGetCull) {
        void *(*fn)(void *, void *, bool) = (void *(*)(void *, void *, bool)) CTMethodPtr(mGetComp);
        void *g = fn(comp, typeGraphic, true);
        if (g) {
            void *cr = ((void *(*)(void *)) CTMethodPtr(mGetCanvasRenderer))(g);
            if (cr && ((bool (*)(void *)) CTMethodPtr(mGetCull))(cr)) return NO;
        }
    }
    return YES;
}

static BOOL btnclick_has_callback(void *comp) {
    if (!comp) return NO;
    if (offOnBtnCall && *(void **)((char *)comp + offOnBtnCall)) return YES;
    if (offOnBtnCustom && *(void **)((char *)comp + offOnBtnCustom)) return YES;
    return NO;
}

NSString *CTAutoDumpButtons(void) {
    dump_setup();
    NSMutableString *out = [NSMutableString string];
    if (!g_ready) {
        [out appendString:@"Không resolve được API Unity.\n"];
    } else {
        [out appendString:@"== BtnClickEvent ==\nTÊN\tNHÃN\tCALLBACK\tVIS\n"];
        if (btnClickOK) {
            void *arr = find_all(typeBtnClick);
            int n = CTArrayLength(arr);
            [out appendFormat:@"Tổng: %d\n", n];
            for (int i = 0; i < n && i < 600; i++) {
                void *comp = CTArrayElem(arr, i);
                if (!comp) continue;
                [out appendFormat:@"%@\t%@\t%@\t%@\n", obj_name(comp) ?: @"?",
                 component_label(comp) ?: @"(không có nhãn)",
                 btnclick_has_callback(comp) ? @"yes" : @"null",
                 component_visible(comp) ? @"1" : @"0"];
            }
        } else {
            [out appendString:@"(không resolve được BtnClickEvent)\n"];
        }
        [out appendString:@"\n== UnityEngine.UI.Button ==\nTÊN\tNHÃN\n"];
        if (clsButton && typeButton) {
            void *arr = find_all(typeButton);
            int n = CTArrayLength(arr);
            [out appendFormat:@"Tổng: %d\n", n];
            for (int i = 0; i < n && i < 600; i++) {
                void *btn = CTArrayElem(arr, i);
                if (!btn) continue;
                [out appendFormat:@"%@\t%@\n", obj_name(btn) ?: @"?", component_label(btn) ?: @"(không có nhãn)"];
            }
        }
    }
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [docs stringByAppendingPathComponent:@"cherrytale_buttons.txt"];
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    CTLog(@"dump ui: %@", path);
    return [NSString stringWithFormat:@"%@\n\nĐã ghi: %@", out, path];
}
