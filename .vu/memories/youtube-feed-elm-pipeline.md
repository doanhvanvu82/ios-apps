---
description: "YouTube 21.44.4 feed ad pipeline: cổng chặn đúng và bẫy đã gặp"
evidence:
  - path: "mods/youtube/src/sectionfilter.mm"
    quote: "// 2.7 BỎ: entry của hàm này là SECTION/entry lớn chứa element con — mô tả của\n// nó có thể chứa ad_logging_data của element con → trả nil làm TRỐNG CẢ FEED"
  - path: "mods/youtube/src/probe.mm"
    quote: "// CHỈ hook nơi cellSizeWithSize: được ĐỊNH NGHĨA TRỰC TIẾP — không dùng\n// class_getInstanceMethod vì nó tìm theo chuỗi kế thừa: cài hook trên\n// lớp con trước rồi cài trên lớp cha sẽ khiến method_getImplementation\n// trả về HOOK vừa cài → _o_cellSize = h_cellSize → đệ quy (crash 2.9,"
  - path: "mods/youtube/src/sectionfilter.mm"
    quote: "// 2.5 crash: trả YTIElementRenderer (sai class, khác kiểu với data)\n// → caller gọi selector của data lên nó → doesNotRecognizeSelector."
  - path: "mods/youtube/src/uisweep.mm"
    quote: "// Vấn đề 3.13: cell.hidden chỉ ẩn nội dung, cell VẪN chiếm chỗ trong layout —\n// khi scroll/reload, UICollectionView đặt lại frame cell theo layoutAttributes\n// → khoảng trống quay lại."
  - path: "mods/youtube/src/uisweep.mm"
    quote: "SEL anSel = sel_registerName(\"asyncdisplaykit_node\");\nif ([sub respondsToSelector:anSel]) {\n    node = ((id (*)(id, SEL))objc_msgSend)(sub, anSel);\n}"
---
Quảng cáo feed YouTube 21.44.4 là element (ELM) mang ad_logging_data, render qua cell controller video thường (use_video_cell_controller_on_ios) — không có class "Promoted*" để chặn tên. Thứ tự chặn hiệu quả: (1) YTIElementRenderer.elementData trả data rỗng CÙNG KIỂU (tạo renderer blank rồi gọi IMP gốc trên nó — trả YTIElementRenderer trần gây crash doesNotRecognizeSelector), (2) YTAdElementsCellAPIImpl.didLoadRenderer: skip, (3) UI sweep ẩn cell có node con "ActiveView" (YTActiveViewDisplayContainerNode — node ad-tracking độc quyền của cell quảng cáo; cell video dùng YTVideoWithContextNode không có). KHÔNG chặn createCellControllerForEntry: (entry là cả section → trả nil làm trống feed skeleton vĩnh viễn) và KHÔNG hook cellSizeWithSize: trên lớp chỉ kế thừa (class_getInstanceMethod trả method lớp cha đã bị replace → orig=hook → đệ quy crash). Node của cell lấy bằng selector 'asyncdisplaykit_node' (KVC 'node' không có trên _ASDisplayView). Ẩn cell ad phải đặt frame=0 VÀ giữ lại mỗi tick sweep 0.5s bằng weak list — layout đặt lại frame khi scroll/reload nên chỉ ẩn+frame 0 một lần vẫn còn lỗ.
