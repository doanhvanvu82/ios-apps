---
description: "YouTube mod: đường ads feed và bẫy type encoding"
evidence:
  - path: "mods/youtube/src/adblock.mm"
    quote: "//  - TUYỆT ĐỐI không trả nil từ hàm init/create/slotFrom… có kiểu trả object:"
  - path: "mods/youtube/src/adblock.mm"
    quote: "//    caller dùng kết quả ngay → EXC_BAD_ACCESS tại objc_retain"
  - path: "mods/youtube/src/adblock.mm"
    quote: "ADHOOK(\"YTAdElementsCellAPIImpl\", \"didLoadRenderer:\", YTMAdSkip, 1,"
  - path: "mods/youtube/src/adblock.mm"
    quote: "ADHOOK(\"YTAdElementsCellExternallyManagedSlotAdapterImpl\",\n           \"didBindSlotData:layoutData:\", YTMAdSkip, 2,"
---
Mod YouTube 21.44.4 không chặn được ads bằng cờ YTIPlayerResponse; ads feed đi qua YTAdElementsCellAPIImpl.didLoadRenderer: → YTAdElementsCellExternallyManagedSlotAdapterImpl.didBindSlotData:layoutData:. Tuyệt đối không trả nil từ hàm trả object của pipeline ad (slot factory/init/create) vì caller dùng ngay → EXC_BAD_ACCESS tại objc_retain; chỉ bỏ thân hàm void hoặc cho getter trả @[]/nil. Luôn đối chiếu type encoding thật trong binary trước khi hook (hàm naive void-ify có thể làm mất giá trị trả về).
