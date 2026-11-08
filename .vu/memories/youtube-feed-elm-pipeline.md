---
description: "YouTube 21.44.4 feed ad pipeline: cổng chặn đúng và bẫy đã gặp"
evidence:
  - path: "mods/youtube/src/sectionfilter.mm"
    quote: "// 2.7 BỎ: entry của hàm này là SECTION/entry lớn chứa element con — mô tả của\n// nó có thể chứa ad_logging_data của element con → trả nil làm TRỐNG CẢ FEED"
  - path: "mods/youtube/src/probe.mm"
    quote: "// CHỈ hook nơi cellSizeWithSize: được ĐỊNH NGHĨA TRỰC TIẾP — không dùng\n// class_getInstanceMethod vì nó tìm theo chuỗi kế thừa: cài hook trên\n// lớp con trước rồi cài trên lớp cha sẽ khiến method_getImplementation\n// trả về HOOK vừa cài → _o_cellSize = h_cellSize → đệ quy (crash 2.9,"
  - path: "mods/youtube/src/sectionfilter.mm"
    quote: "// 2.5 crash: trả YTIElementRenderer (sai class, khác kiểu với data)\n// → caller gọi selector của data lên nó → doesNotRecognizeSelector."
  - path: "mods/youtube/src/sectionfilter.mm"
    quote: "{\"ELMControllerFactory\", \"controllerWithElement:context:treeLocalContext:\", (IMP)h_elmCtl, &_o_elmCtl, \"elmctl\"},"
---
Quảng cáo feed YouTube 21.44.4 là element (ELM) mang ad_logging_data, render qua cell controller video thường (use_video_cell_controller_on_ios) — không có class "Promoted*" để chặn tên. Thứ tự chặn hiệu quả: (1) YTIElementRenderer.elementData trả data rỗng CÙNG KIỂU (tạo renderer blank rồi gọi IMP gốc trên nó — trả YTIElementRenderer trần gây crash doesNotRecognizeSelector), (2) YTAdElementsCellAPIImpl.didLoadRenderer: skip. KHÔNG chặn createCellControllerForEntry: (entry là cả section, mô tả chứa ad_logging_data của element con → trả nil làm trống feed, skeleton vĩnh viễn) và KHÔNG hook cellSizeWithSize: trên lớp chỉ kế thừa (class_getInstanceMethod trả method lớp cha đã bị replace → orig=hook → đệ quy crash). ELMControllerFactory.controllerWithElement: elmctl cài OK nhưng 0 lượt — element tới factory bằng đường khác. adview/simgad vẫn tải sau XÓA do prefetch của pipeline ad trước lúc chặn kịp.
