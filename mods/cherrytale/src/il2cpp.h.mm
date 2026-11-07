// Resolve class/method theo TÊN qua il2cpp API (không hard-code RVA).
// Domain chưa sẵn sàng lúc dylib vừa load -> chạy thread nền, retry có giới hạn.
#import "common.h"

#include <dlfcn.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <vector>
#include <string>

typedef void Il2CppDomain;
typedef void Il2CppAssembly;
typedef void Il2CppImage;
typedef void Il2CppClass;
typedef void Il2CppType;
typedef void Il2CppMethod;

static Il2CppDomain *(*p_domain_get)(void);
static Il2CppAssembly **(*p_domain_get_assemblies)(Il2CppDomain *, size_t *);
static Il2CppImage *(*p_assembly_get_image)(Il2CppAssembly *);
static const char *(*p_image_get_name)(Il2CppImage *);
static Il2CppClass *(*p_class_from_name)(Il2CppImage *, const char *, const char *);
static Il2CppMethod *(*p_class_get_method_from_name)(Il2CppClass *, const char *, int);
static void *(*p_class_get_methods)(Il2CppClass *, void **);
static Il2CppClass *(*p_class_get_nested_types)(Il2CppClass *, void **);
static Il2CppClass *(*p_class_get_declaring_type)(Il2CppClass *);
static size_t (*p_image_get_class_count)(Il2CppImage *);
static Il2CppClass *(*p_image_get_class)(Il2CppImage *, size_t);
static const char *(*p_class_get_name)(Il2CppClass *);
static const char *(*p_method_get_name)(Il2CppMethod *);
static int (*p_method_get_param_count)(Il2CppMethod *);
static Il2CppType *(*p_method_get_param)(Il2CppMethod *, unsigned int);
static Il2CppType *(*p_method_get_return_type)(Il2CppMethod *);
static char *(*p_type_get_name)(Il2CppType *);
static void *(*p_thread_attach)(Il2CppDomain *);
static void (*p_free)(void *);
static Il2CppClass *(*p_object_get_class)(void *);
static size_t (*p_array_length)(void *);
static int32_t (*p_string_length)(void *);
static uint16_t *(*p_string_chars)(void *);
static Il2CppType *(*p_class_get_type)(void *);
static void *(*p_type_get_object)(void *);
static void *(*p_object_get_virtual_method)(void *, void *);
static void *(*p_runtime_invoke)(void *, void *, void **, void **);
static void *(*p_object_new)(void *);
static void *(*p_class_from_type)(void *);
static void *(*p_object_unbox)(void *);

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static Il2CppDomain *g_domain = NULL;
static Il2CppImage *g_image = NULL;
static BOOL g_ready = NO;
static BOOL g_apiLoaded = NO;

static void *sym(const char *name) { return dlsym(RTLD_DEFAULT, name); }

static BOOL load_api(void) {
    if (g_apiLoaded) return YES;
    p_domain_get = (Il2CppDomain * (*)(void)) sym("il2cpp_domain_get");
    p_domain_get_assemblies = (Il2CppAssembly * *(*)(Il2CppDomain *, size_t *)) sym("il2cpp_domain_get_assemblies");
    p_assembly_get_image = (Il2CppImage * (*)(Il2CppAssembly *)) sym("il2cpp_assembly_get_image");
    p_image_get_name = (const char *(*)(Il2CppImage *)) sym("il2cpp_image_get_name");
    p_class_from_name = (Il2CppClass * (*)(Il2CppImage *, const char *, const char *)) sym("il2cpp_class_from_name");
    p_class_get_method_from_name = (Il2CppMethod * (*)(Il2CppClass *, const char *, int)) sym("il2cpp_class_get_method_from_name");
    p_class_get_methods = (void *(*)(Il2CppClass *, void **)) sym("il2cpp_class_get_methods");
    p_class_get_nested_types = (Il2CppClass * (*)(Il2CppClass *, void **)) sym("il2cpp_class_get_nested_types");
    p_class_get_declaring_type = (Il2CppClass * (*)(Il2CppClass *)) sym("il2cpp_class_get_declaring_type");
    p_image_get_class_count = (size_t (*)(Il2CppImage *)) sym("il2cpp_image_get_class_count");
    p_image_get_class = (Il2CppClass * (*)(Il2CppImage *, size_t)) sym("il2cpp_image_get_class");
    p_class_get_name = (const char *(*)(Il2CppClass *)) sym("il2cpp_class_get_name");
    p_method_get_name = (const char *(*)(Il2CppMethod *)) sym("il2cpp_method_get_name");
    p_method_get_param_count = (int (*)(Il2CppMethod *)) sym("il2cpp_method_get_param_count");
    p_method_get_param = (Il2CppType * (*)(Il2CppMethod *, unsigned int)) sym("il2cpp_method_get_param");
    p_method_get_return_type = (Il2CppType * (*)(Il2CppMethod *)) sym("il2cpp_method_get_return_type");
    p_type_get_name = (char *(*)(Il2CppType *)) sym("il2cpp_type_get_name");
    p_thread_attach = (void *(*)(Il2CppDomain *)) sym("il2cpp_thread_attach");
    p_free = (void (*)(void *)) sym("il2cpp_free");
    p_object_get_class = (Il2CppClass * (*)(void *)) sym("il2cpp_object_get_class");
    p_array_length = (size_t (*)(void *)) sym("il2cpp_array_length");
    p_string_length = (int32_t (*)(void *)) sym("il2cpp_string_length");
    p_string_chars = (uint16_t *(*)(void *)) sym("il2cpp_string_chars");
    p_class_get_type = (Il2CppType * (*)(void *)) sym("il2cpp_class_get_type");
    p_type_get_object = (void *(*)(void *)) sym("il2cpp_type_get_object");
    p_object_get_virtual_method = (void *(*)(void *, void *)) sym("il2cpp_object_get_virtual_method");
    p_runtime_invoke = (void *(*)(void *, void *, void **, void **)) sym("il2cpp_runtime_invoke");
    p_object_new = (void *(*)(void *)) sym("il2cpp_object_new");
    p_class_from_type = (void *(*)(void *)) sym("il2cpp_class_from_type");
    p_object_unbox = (void *(*)(void *)) sym("il2cpp_object_unbox");
    g_apiLoaded = p_domain_get && p_domain_get_assemblies && p_assembly_get_image &&
                  p_image_get_name && p_class_from_name && p_class_get_method_from_name &&
                  p_class_get_methods && p_method_get_name && p_method_get_param_count &&
                  p_method_get_param && p_method_get_return_type && p_type_get_name &&
                  p_thread_attach && p_free;
    return g_apiLoaded;
}

static Il2CppImage *find_image_locked(const char *fileName) {
    size_t count = 0;
    Il2CppAssembly **asms = p_domain_get_assemblies(g_domain, &count);
    if (!asms) return NULL;
    for (size_t i = 0; i < count; i++) {
        Il2CppImage *img = p_assembly_get_image(asms[i]);
        if (!img) continue;
        const char *n = p_image_get_name(img);
        if (n && strcmp(n, fileName) == 0) return img;
    }
    return NULL;
}

// KHÔNG tạo thread riêng: il2cpp_thread_attach từ pthread ngoài làm Boehm GC
// của Unity abort (GC_register_my_thread). Mọi resolve chạy trên main thread.
BOOL CTIL2CPPTryInit(void) {
    if (g_ready) return YES;
    if (!load_api()) return NO;
    Il2CppDomain *d = p_domain_get();
    if (!d) return NO;
    // main thread đã được Unity attach; gọi lại là idempotent và an toàn.
    p_thread_attach(d);
    Il2CppImage *img = find_image_locked("Assembly-CSharp.dll");
    if (!img) return NO;
    const char *imgName = p_image_get_name(img);
    pthread_mutex_lock(&g_lock);
    g_domain = d;
    g_image = img;
    g_ready = YES;
    pthread_mutex_unlock(&g_lock);
    CTLog(@"il2cpp: image=%s", imgName ? imgName : "?");
    return YES;
}

void CTIL2CPPStart(void) {
    // chỉ nạp bảng symbol; việc init do CTIL2CPPTryInit() trên main thread.
    load_api();
}

BOOL CTIL2CPPReady(void) { return g_ready; }

// Ghép tên đầy đủ của class (kể cả class lồng nhau) để so khớp khi phải quét.
static BOOL class_full_name_equals(Il2CppClass *k, const char *name) {
    if (!k || !name || !p_class_get_name) return NO;
    const char *segs[16];
    int n = 0;
    Il2CppClass *cur = k;
    while (cur && n < 16) {
        const char *cn = p_class_get_name(cur);
        if (!cn) return NO;
        segs[n++] = cn;
        cur = p_class_get_declaring_type ? p_class_get_declaring_type(cur) : NULL;
    }
    char buf[256];
    size_t pos = 0;
    for (int i = n - 1; i >= 0; i--) {
        size_t l = strlen(segs[i]);
        if (pos + l + 2 >= sizeof(buf)) return NO;
        if (pos) buf[pos++] = '.';
        memcpy(buf + pos, segs[i], l);
        pos += l;
    }
    buf[pos] = 0;
    return strcmp(buf, name) == 0;
}

// Quét toàn bộ class của image. Chậm nhưng an toàn, chỉ dùng khi tra nhanh thất bại.
static Il2CppClass *scan_image_for_class_locked(Il2CppImage *img, const char *name) {
    if (!img || !name || !p_image_get_class_count || !p_image_get_class) return NULL;
    size_t total = p_image_get_class_count(img);
    for (size_t i = 0; i < total; i++) {
        Il2CppClass *k = p_image_get_class(img, i);
        if (k && class_full_name_equals(k, name)) return k;
    }
    return NULL;
}

// Tra class trong 1 image. Tên lồng nhau dùng dấu chấm: "SecretModule.HCG".
// TUYỆT ĐỐI không truyền namespace NULL cho il2cpp_class_from_name: il2cpp sẽ
// strlen(NULL) và crash (đã gặp thực tế trên máy).
static Il2CppClass *find_in_image_locked(Il2CppImage *img, const char *name, int depth) {
    if (!img || !name || !*name || depth > 8) return NULL;

    const char *dot = strrchr(name, '.');
    if (dot) {
        size_t outerLen = (size_t)(dot - name);
        if (outerLen == 0 || outerLen >= 200) return NULL;
        char outer[200];
        memcpy(outer, name, outerLen);
        outer[outerLen] = 0;

        Il2CppClass *outerCls = find_in_image_locked(img, outer, depth + 1);
        if (outerCls && p_class_get_nested_types && p_class_get_name) {
            void *iter = NULL;
            Il2CppClass *nested = NULL;
            while ((nested = p_class_get_nested_types(outerCls, &iter)) != NULL) {
                const char *cn = p_class_get_name(nested);
                if (cn && strcmp(cn, dot + 1) == 0) return nested;
            }
        }
        return scan_image_for_class_locked(img, name);
    }
    Il2CppClass *fast = p_class_from_name ? p_class_from_name(img, "", name) : NULL;
    if (fast) return fast;
    return scan_image_for_class_locked(img, name); // "" — KHÔNG BAO GIỜ NULL namespace
}

void *CTFindClass(const char *name) {
    if (!g_ready || !name) return NULL;
    pthread_mutex_lock(&g_lock);
    Il2CppClass *k = find_in_image_locked(g_image, name, 0);
    if (!k) {
        // Dự phòng: quét mọi assembly (UnityEngine.*, Assembly-CSharp-firstpass, ...)
        size_t count = 0;
        Il2CppAssembly **asms = p_domain_get_assemblies(g_domain, &count);
        for (size_t i = 0; asms && i < count && !k; i++) {
            Il2CppImage *img = p_assembly_get_image(asms[i]);
            if (img && img != g_image) k = find_in_image_locked(img, name, 0);
        }
    }
    pthread_mutex_unlock(&g_lock);
    return k;
}

void *CTFindMethod(void *klass, const char *name, int paramCount) {
    if (!g_ready || !klass) return NULL;
    pthread_mutex_lock(&g_lock);
    void *m = p_class_get_method_from_name((Il2CppClass *)klass, name, paramCount);
    pthread_mutex_unlock(&g_lock);
    return m;
}

void *CTFindAnyMethod(void *klass, const char *name) {
    if (!g_ready || !klass) return NULL;
    pthread_mutex_lock(&g_lock);
    void *iter = NULL;
    void *found = NULL;
    void *m = NULL;
    while ((m = p_class_get_methods((Il2CppClass *)klass, &iter)) != NULL) {
        const char *n = p_method_get_name((Il2CppMethod *)m);
        if (n && strcmp(n, name) == 0) { found = m; break; }
    }
    pthread_mutex_unlock(&g_lock);
    return found;
}

BOOL CTFindFieldOffset(void *klass, const char *name, size_t *outOffset) {
    if (outOffset) *outOffset = 0;
    if (!g_ready || !klass) return NO;
    void *(*p_class_get_field_from_name)(void *, const char *) =
        (void *(*)(void *, const char *)) sym("il2cpp_class_get_field_from_name");
    size_t (*p_field_get_offset)(void *) = (size_t (*)(void *)) sym("il2cpp_field_get_offset");
    if (!p_class_get_field_from_name || !p_field_get_offset) return NO;
    pthread_mutex_lock(&g_lock);
    void *f = p_class_get_field_from_name(klass, name);
    size_t off = f ? p_field_get_offset(f) : 0;
    pthread_mutex_unlock(&g_lock);
    if (!f) return NO;
    if (outOffset) *outOffset = off;
    return YES;
}

NSString *CTMethodSignature(void *method) {
    if (!method) return @"?";
    pthread_mutex_lock(&g_lock);
    char *ret = NULL;
    Il2CppType *rt = p_method_get_return_type((Il2CppMethod *)method);
    if (rt) ret = p_type_get_name(rt);
    NSMutableString *s = [NSMutableString stringWithFormat:@"%s %s(", ret ? ret : "?", p_method_get_name((Il2CppMethod *)method)];
    int n = p_method_get_param_count((Il2CppMethod *)method);
    for (int i = 0; i < n; i++) {
        char *pt = p_type_get_name(p_method_get_param((Il2CppMethod *)method, (unsigned)i));
        if (i) [s appendString:@", "];
        [s appendFormat:@"%s", pt ? pt : "?"];
        if (pt) p_free(pt);
    }
    [s appendString:@")"];
    if (ret) p_free(ret);
    pthread_mutex_unlock(&g_lock);
    return s;
}

// Chỉ gọi method của NumericActor khi object đúng là NumericActor.
// Get_Final_HP(IActor) có thể nhận implementation khác -> gọi bừa sẽ crash.
BOOL CTObjectIsClass(void *obj, const char *name) {
    if (!obj || !name || !g_ready || !p_object_get_class) return NO;
    Il2CppClass *k = p_object_get_class(obj);
    return k && class_full_name_equals(k, name);
}

BOOL CTObjectIsNumericActor(void *obj) {
    static Il2CppClass *cls = NULL;
    if (!obj || !p_object_get_class) return NO;
    if (!cls) cls = (Il2CppClass *) CTFindClass("NumericActor");
    return cls && p_object_get_class(obj) == cls;
}

// Gọi managed method qua runtime_invoke: exception được trả về thay vì ném,
// tránh abort khi handler của game ném NullReferenceException.
void *CTSafeInvoke(void *method, void *obj, void **args) {
    if (!method || !p_runtime_invoke) return NULL;
    void *exc = NULL;
    void *res = p_runtime_invoke(method, obj, args, &exc);
    return exc ? NULL : res;
}

BOOL CTSafeInvokeR(void *method, void *obj, void **args, void **outResult) {
    if (outResult) *outResult = NULL;
    if (!method || !p_runtime_invoke) return NO;
    void *exc = NULL;
    void *res = p_runtime_invoke(method, obj, args, &exc);
    if (exc) return NO;
    if (outResult) *outResult = res;
    return YES;
}

void *CTObjectClass(void *obj) {
    return (obj && p_object_get_class) ? p_object_get_class(obj) : NULL;
}

void *CTFindClassNS(const char *ns, const char *name) {
    if (!g_ready || !name) return NULL;
    pthread_mutex_lock(&g_lock);
    size_t count = 0;
    Il2CppAssembly **asms = p_domain_get_assemblies(g_domain, &count);
    Il2CppClass *k = NULL;
    for (size_t i = 0; asms && i < count && !k; i++) {
        Il2CppImage *img = p_assembly_get_image(asms[i]);
        if (img) k = p_class_from_name(img, ns ? ns : "", name);
    }
    pthread_mutex_unlock(&g_lock);
    return k;
}

void *CTTypeObject(void *klass) {
    if (!klass || !p_class_get_type || !p_type_get_object) return NULL;
    Il2CppType *t = p_class_get_type(klass);
    return t ? p_type_get_object(t) : NULL;
}

int CTArrayLength(void *arr) {
    return (arr && p_array_length) ? (int)p_array_length(arr) : 0;
}

// Phần tử của mảng tham chiếu: dữ liệu bắt đầu ở offset 0x20 (arm64).
void *CTArrayElem(void *arr, int index) {
    if (!arr || index < 0) return NULL;
    return ((void **)((char *)arr + 0x20))[index];
}

NSString *CTString(void *s) {
    if (!s || !p_string_length || !p_string_chars) return nil;
    int32_t len = p_string_length(s);
    const uint16_t *ch = p_string_chars(s);
    if (!ch || len <= 0) return @"";
    return [NSString stringWithCharacters:ch length:(NSUInteger)len];
}

void *CTVirtualMethod(void *obj, void *method) {
    if (!obj || !method || !p_object_get_virtual_method) return method;
    return p_object_get_virtual_method(obj, method);
}

void *CTMethodPtr(void *method) {
    if (!method) return NULL;
    return *(void **)method; // MethodInfo.methodPointer ở offset 0
}

void *CTObjectNew(void *klass) {
    return (klass && p_object_new) ? p_object_new(klass) : NULL;
}

void *CTClassFromType(void *type) {
    return (type && p_class_from_type) ? p_class_from_type(type) : NULL;
}

// Trả về con trỏ dữ liệu của struct bên trong object đã box (arm64: +0x10).
void *CTObjectUnbox(void *boxed) {
    return (boxed && p_object_unbox) ? p_object_unbox(boxed) : NULL;
}

void *CTMethodParam(void *method, int index) {
    if (!method || !p_method_get_param) return NULL;
    return p_method_get_param((Il2CppMethod *)method, (unsigned)index);
}

void *CTNewInstance(void *klass, void **args) {
    if (!klass || !p_object_new) return NULL;
    void *obj = p_object_new(klass);
    if (!obj) return NULL;
    void *ctor = p_class_get_method_from_name
        ? p_class_get_method_from_name((Il2CppClass *)klass, ".ctor", args ? 1 : 0)
        : NULL;
    // .ctor của PointerEventData có 1 tham số; nếu không tìm thấy thì trả object chưa init.
    if (ctor && p_runtime_invoke) {
        void *exc = NULL;
        p_runtime_invoke(ctor, obj, args, &exc);
        if (exc) return NULL;
    }
    return obj;
}

BOOL CTInvokeVirtual(void *obj, void *method, void **args) {
    if (!obj || !method || !p_runtime_invoke) return NO;
    void *m = p_object_get_virtual_method ? p_object_get_virtual_method(obj, method) : method;
    void *exc = NULL;
    p_runtime_invoke(m ? m : method, obj, args, &exc);
    return exc == NULL;
}
