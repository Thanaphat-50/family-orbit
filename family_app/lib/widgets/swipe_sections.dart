import 'package:flutter/material.dart';

// =======================================================
// หน้าย่อยที่ปัดซ้าย-ขวาสลับกันได้ (เฉพาะในหน้าเดียวกัน)
// - index: หน้าย่อยที่เลือกอยู่ (หน้าแม่เป็นคนเก็บ)
// - กดแท็บ/ปุ่มสลับในหน้าแม่ → index เปลี่ยน → เลื่อนไปให้
// - ปัดจนเปลี่ยนหน้า → onChanged
// สุดขอบแล้วปัดต่อไม่ได้ (ไม่ข้ามไปหน้าอื่นบนแถบล่าง)
// =======================================================

class SwipeSections extends StatefulWidget {
  final int index;

  final ValueChanged<int> onChanged;

  final List<Widget> children;

  const SwipeSections({
    super.key,
    required this.index,
    required this.onChanged,
    required this.children,
  });

  @override
  State<SwipeSections> createState() => _SwipeSectionsState();
}

class _SwipeSectionsState extends State<SwipeSections> {
  late final PageController controller = PageController(
    initialPage: widget.index,
  );

  @override
  void didUpdateWidget(SwipeSections oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!controller.hasClients) return;

    final double? page = controller.page;

    // ปัดเลยครึ่งทางแล้ว (หน้าแม่รู้แล้ว) → ไม่ต้องเลื่อนซ้ำ
    if (page == null || page.round() == widget.index) return;

    controller.animateToPage(
      widget.index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: controller,
      onPageChanged: (index) {
        if (index != widget.index) widget.onChanged(index);
      },
      children: widget.children,
    );
  }

  @override
  void dispose() {
    controller.dispose();

    super.dispose();
  }
}
