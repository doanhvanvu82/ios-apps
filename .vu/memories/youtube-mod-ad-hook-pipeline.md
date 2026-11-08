---
description: "YouTube mod: cách chặn ads từ gốc"
evidence:
  - path: "mods/youtube/src/adblock.mm"
    quote: "// CÁCH CHÍNH (học từ YTLite, tweak còn bảo trì cho bản YouTube hiện tại):"
  - path: "mods/youtube/src/adblock.mm"
    quote: "ADHOOK(\"YTAdsInnerTubeContextDecoratorImpl\", \"decorateContext:serviceType:\","
  - path: "mods/youtube/src/adblock.mm"
    quote: "ADHOOK(\"YTAccountScopedAdsInnerTubeContextDecorator\", \"decorateContext:serviceType:\","
  - path: "mods/youtube/src/adblock.mm"
    quote: "//  - TUYỆT ĐỐI không trả nil từ hàm init/create/slotFrom… trả object: caller"
---
Mod YouTube 21.44.4 chặn ads hiệu quả nhất bằng cách học YTLite: bỏ decorate context quảng cáo khi gửi InnerTube (YTAdsInnerTubeContextDecoratorImpl, YTAccountScopedAdsInnerTubeContextDecorator: decorateContext:serviceType:, decorateContextWithAdShieldSignals:, decorateContextWithIDFA:) để server không trả ad slot/preroll. Không trả nil từ hàm trả object của pipeline ad (slot factory/init) vì caller dùng ngay → EXC_BAD_ACCESS; chỉ bỏ thân hàm void hoặc getter trả @[]/nil.
