import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/market_data.dart';
import '../services/market_service.dart';
import '../theme/app_theme.dart';
import '../widgets/post_categories.dart';

// =======================================================
// เพิ่ม / แก้ไขสินค้า
// product = null → เพิ่มใหม่
// สำเร็จแล้ว pop กลับพร้อมข้อมูลสินค้าล่าสุด
// =======================================================

class ProductFormPage extends StatefulWidget {
  final Map<String, dynamic>? product;

  // หมวดเริ่มต้นของสินค้าใหม่ (ใช้หมวดของร้าน)
  final String? defaultCategory;

  const ProductFormPage({super.key, this.product, this.defaultCategory});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  // ตรงกับ Laravel: ชิ้นละไม่เกิน 5 รูป
  static const int maxImages = 5;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  late final TextEditingController titleController = TextEditingController(
    text: initialText('title'),
  );
  late final TextEditingController priceController = TextEditingController(
    text: initialPrice(),
  );
  late final TextEditingController descriptionController =
      TextEditingController(text: initialText('description'));

  late String? category =
      widget.product?['category']?.toString() ?? widget.defaultCategory;

  // รูปเดิมที่ยังเก็บไว้ ({id, url}) และรูปใหม่ที่เลือก
  late final List<Map<String, dynamic>> keptImages = [
    for (final image in (widget.product?['images'] as List?) ?? const [])
      if (image is Map) Map<String, dynamic>.from(image),
  ];
  final List<int> removedImageIds = [];
  final List<XFile> newImages = [];

  bool isSaving = false;

  Map<String, String> serverErrors = {};

  bool get isNew => widget.product == null;

  int get imageCount => keptImages.length + newImages.length;

  String initialText(String key) {
    final dynamic value = widget.product?[key];

    return value == null ? '' : value.toString();
  }

  // "35.00" → "35", "35.50" → "35.50"
  String initialPrice() {
    final double? value = double.tryParse(initialText('price'));

    if (value == null) return '';

    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  void dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // =====================================================
  // รูปสินค้า
  // =====================================================

  Future<void> pickImages() async {
    dismissKeyboard();

    final int remaining = maxImages - imageCount;

    if (remaining <= 0) {
      showMessage('สินค้าแต่ละชิ้นมีรูปได้สูงสุด $maxImages รูป');
      return;
    }

    try {
      final List<XFile> images = await ImagePicker().pickMultiImage(
        limit: remaining,
        maxWidth: 1600,
        imageQuality: 80,
      );

      if (!mounted || images.isEmpty) return;

      setState(() {
        newImages.addAll(images.take(remaining));
      });
    } catch (_) {
      showMessage('เลือกรูปไม่สำเร็จ กรุณาลองอีกครั้ง');
    }
  }

  void removeKeptImage(Map<String, dynamic> image) {
    final dynamic id = image['id'];

    setState(() {
      keptImages.remove(image);

      if (id is num) removedImageIds.add(id.toInt());
    });
  }

  // =====================================================
  // บันทึก
  // =====================================================

  Future<void> submit() async {
    dismissKeyboard();

    setState(() {
      serverErrors = {};
    });

    final bool valid = formKey.currentState?.validate() ?? false;

    if (!valid) return;

    if (imageCount == 0) {
      showMessage('กรุณาเพิ่มรูปสินค้าอย่างน้อย 1 รูป');
      return;
    }

    if (category == null) {
      showMessage('กรุณาเลือกหมวดสินค้า');
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final dynamic id = widget.product?['id'];

      final result = await MarketService.saveProduct(
        productId: id is num ? id.toInt() : null,
        fields: {
          'title': titleController.text.trim(),
          'price': priceController.text.trim().replaceAll(',', ''),
          'description': descriptionController.text.trim(),
          'category': category!,
        },
        newImagePaths: newImages.map((image) => image.path).toList(),
        removeImageIds: removedImageIds,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        showMessage(result['message']?.toString() ?? 'บันทึกสินค้าแล้ว');

        Navigator.of(context).pop(result['product']);
        return;
      }

      final dynamic errors = result['errors'];

      if (errors is Map) {
        setState(() {
          serverErrors = {
            for (final entry in errors.entries)
              entry.key.toString(): entry.value is List
                  ? (entry.value as List).first.toString()
                  : entry.value.toString(),
          };
        });
      }

      showMessage(result['message']?.toString() ?? 'บันทึกสินค้าไม่สำเร็จ');
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // UI
  // =====================================================

  Widget buildImageTile({
    required Widget image,
    required VoidCallback onRemove,
  }) {
    const double size = 92;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(width: size, height: size, child: image),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: isSaving ? null : onRemove,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildImages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final image in keptImages)
              buildImageTile(
                image: Image.network(
                  image['url']?.toString() ?? '',
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  errorBuilder: (context, error, stackTrace) {
                    return ColoredBox(
                      color: AppColors.fill,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.muted,
                      ),
                    );
                  },
                ),
                onRemove: () => removeKeptImage(image),
              ),
            for (final image in newImages)
              buildImageTile(
                image: Image.file(
                  File(image.path),
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                ),
                onRemove: () {
                  setState(() {
                    newImages.remove(image);
                  });
                },
              ),
            if (imageCount < maxImages)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: isSaving ? null : pickImages,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: marketColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: marketColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: marketColor,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$imageCount/$maxImages',
                        style: const TextStyle(
                          color: marketColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (serverErrors.keys.any((key) => key.startsWith('images')))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              serverErrors.entries
                  .firstWhere((entry) => entry.key.startsWith('images'))
                  .value,
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'เพิ่มสินค้า' : 'แก้ไขสินค้า')),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              buildSectionLabel('รูปสินค้า (1–5 รูป)'),
              buildImages(),
              const SizedBox(height: 24),
              buildSectionLabel('ข้อมูลสินค้า'),
              TextFormField(
                controller: titleController,
                maxLength: 120,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'ชื่อสินค้า',
                  prefixIcon: const Icon(Icons.sell_outlined),
                  errorText: serverErrors['title'],
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'กรุณาใส่ชื่อสินค้า' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'ราคา (บาท)',
                  helperText: 'เว้นว่างไว้ = สอบถามราคา',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  errorText: serverErrors['price'],
                ),
                validator: (value) {
                  final String text = (value ?? '').trim().replaceAll(',', '');

                  if (text.isEmpty) return null;

                  final double? price = double.tryParse(text);

                  if (price == null || price < 0 || price > 9999999) {
                    return 'ราคาต้องเป็นตัวเลข 0 – 9,999,999 บาท';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              buildSectionLabel('หมวดสินค้า'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in marketCategories)
                    CategoryChoiceChip(
                      label: item.label,
                      icon: item.icon,
                      color: marketColor,
                      selected: category == item.key,
                      onTap: () {
                        setState(() {
                          category = item.key;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: descriptionController,
                maxLength: 2000,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: 'รายละเอียด (ไม่บังคับ)',
                  hintText: 'ขนาด สี วิธีรับของ หรือรายละเอียดอื่น ๆ',
                  alignLabelWithHint: true,
                  errorText: serverErrors['description'],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: marketColor,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: isSaving ? null : submit,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  isSaving
                      ? 'กำลังบันทึก'
                      : isNew
                      ? 'เพิ่มสินค้า'
                      : 'บันทึกสินค้า',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    priceController.dispose();
    descriptionController.dispose();

    super.dispose();
  }
}
