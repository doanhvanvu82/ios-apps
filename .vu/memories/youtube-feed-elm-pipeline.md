---
description: "YouTube 21.44.4 feed ad: lọc section ở tầng model (3.33), bẫy tầng cell"
evidence:
  - path: "mods/youtube/src/feedfilter.mm"
    quote: "        && ytm_has(ytm_get(element, \"compatibilityOptions\"), \"hasAdLoggingData\")) {"
  - path: "mods/youtube/src/feedfilter.mm"
    quote: "        ytm_feed_hook(cls, \"addSectionsFromArray:\", (IMP)h_addSections, &_o_addSections);"
---
Chặn quảng cáo feed YouTube 21.44.4 KHÔNG để khoảng trống (xác nhận trên máy 3.33): bỏ section/item quảng cáo khỏi model của YTInnerTubeCollectionViewController TRƯỚC khi dựng section controller — hook displaySectionsWithReloadingSectionControllerByRenderer: (lọc ivar _sectionRenderers tại chỗ) và addSectionsFromArray: (cuộn thêm). Nhận diện theo item: elementRenderer.compatibilityOptions.hasAdLoggingData (cờ có cấu trúc) hoặc layout chỉ dành cho ads; section lẫn nội dung thường thì chỉ xoá item ads trong contentsArray. Bẫy đã gặp (2.x–3.32, đã xoá code): tìm chuỗi ad_logging_data trong description của CẢ section → xoá oan section thường, trống feed (2.7); ẩn cell / frame 0 / cellSizeWithSize: CGSizeZero / elementData rỗng (YTGhostCardCell) / ép layout attributes → luôn còn khoảng trống vì danh sách vẫn báo có mục; hook tầng ELM (elm/tab/node) + promo cell/trigger làm TRỐNG trang cá nhân (chia đôi 3.31: chỉ bản tắt section+promo hết lỗi). Bài học: xem tweak đang chạy (YouTube-X/YTLite) chặn ở đâu trước khi dò theo log.
