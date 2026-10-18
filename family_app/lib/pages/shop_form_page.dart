import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/market_data.dart';
import '../services/market_service.dart';
import '../theme/app_theme.dart';
import '../widgets/market_sheets.dart';
import '../widgets/post_categories.dart';

// =======================================================
// สมัครเปิดร้าน / แก้ไขข้อมูลร้าน
// shop = null → สมัครใหม่
// สำเร็จแล้ว pop กลับพร้อมข้อมูลร้านล่าสุด
// =======================================================

class ShopFormPage extends StatefulWidget {
  final Map<String, dynamic>? shop;

  const ShopFormPage({super.key, this.shop});

  @override
  State<ShopFormPage> createState() => _ShopFormPageState();
}

class _ShopFormPageState extends State<ShopFormPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  late final TextEditingController nameController = TextEditingController(
    text: initialText('name'),
  );
  late final TextEditingController descriptionController =
      TextEditingController(text: initialText('description'));
  late final TextEditingController phoneController = TextEditingController(
    text: initialText('phone'),
  );
  late final TextEditingController lineController = TextEditingController(
    text: initialText('line_id'),
  );
  late final TextEditingController districtController = TextEditingController(
    text: initialText('district'),
  );

  late String? category = widget.shop?['category']?.toString();
  late String? province = widget.shop?['province']?.toString();

  // โลโก้: รูปใหม่ที่เลือก / ลิงก์รูปเดิม / กดลบรูปเดิม
  XFile? pickedLogo;
  late String? currentLogoUrl = widget.shop?['logo_url']?.toString();
  bool removeLogo = false;

  bool acceptedRules = false;
  bool isSaving = false;

  // ข้อความ Error จาก Laravel แยกตามช่อง
  Map<String, String> serverErrors = {};

  bool get isNew => widget.shop == null;

  bool get isRejected => widget.shop?['status'] == 'rejected';

  String initialText(String key) {
    final dynamic value = widget.shop?[key];

    return value == null ? '' : value.toString();
  }

  // =====================================================
  // โลโก้
  // =====================================================

  // ปิดคีย์บอร์ดก่อนเปิดหน้าต่างอื่น
  // ใช้ primaryFocus.unfocus() เพื่อไม่ให้ Flutter คืนโฟกัส
  // กลับไปที่ช่องพิมพ์เดิมหลังปิดหน้าต่าง
  void dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> pickLogo() async {
    dismissKeyboard();

    try {
      final XFile? image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );

      if (image == null || !mounted) return;

      setState(() {
        pickedLogo = image;
        removeLogo = false;
      });
    } catch (_) {
      showMessage('เลือกรูปไม่สำเร็จ กรุณาลองอีกครั้ง');
    }
  }

  void clearLogo() {
    setState(() {
      pickedLogo = null;
      currentLogoUrl = null;
      removeLogo = true;
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

    if (category == null) {
      showMessage('กรุณาเลือกหมวดของร้าน');
      return;
    }

    if (isNew && !acceptedRules) {
      showMessage('กรุณายอมรับกฎผู้ขายก่อนเปิดร้าน');
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final result = await MarketService.saveShop(
        isNew: isNew,
        fields: {
          'name': nameController.text.trim(),
          'description': descriptionController.text.trim(),
          'category': category!,
          'phone': phoneController.text.trim(),
          'line_id': lineController.text.trim(),
          'province': province ?? '',
          'district': districtController.text.trim(),
        },
        logoPath: pickedLogo?.path,
        removeLogo: removeLogo && pickedLogo == null,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        showMessage(result['message']?.toString() ?? 'บันทึกแล้ว');

        Navigator.of(context).pop(result['shop']);
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

      showMessage(result['message']?.toString() ?? 'บันทึกไม่สำเร็จ');
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

  Widget buildLogoPicker() {
    final bool hasLogo = pickedLogo != null || currentLogoUrl != null;

    final ImageProvider? image = pickedLogo != null
        ? FileImage(File(pickedLogo!.path))
        : currentLogoUrl != null
        ? NetworkImage(currentLogoUrl!)
        : null;

    return Column(
      children: [
        GestureDetector(
          onTap: isSaving ? null : pickLogo,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: marketColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  image: image != null
                      ? DecorationImage(image: image, fit: BoxFit.cover)
                      : null,
                ),
                child: image == null
                    ? const Icon(
                        Icons.storefront_rounded,
                        color: marketColor,
                        size: 40,
                      )
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: marketColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(
                    Icons.photo_camera_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (hasLogo)
          TextButton(
            onPressed: isSaving ? null : clearLogo,
            child: const Text('เอาโลโก้ออก'),
          )
        else
          const Text(
            'โลโก้ร้าน (ไม่บังคับ)',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        if (serverErrors['logo'] != null)
          Text(
            serverErrors['logo']!,
            style: const TextStyle(color: AppColors.danger, fontSize: 12),
          ),
      ],
    );
  }

  Widget buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget buildCategoryChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (serverErrors['category'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              serverErrors['category']!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget buildProvinceField() {
    return FormField<String>(
      initialValue: province,
      validator: (_) => province == null ? 'กรุณาเลือกจังหวัด' : null,
      builder: (field) {
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isSaving
              ? null
              : () async {
                  dismissKeyboard();

                  final String? picked = await showProvincePicker(
                    context,
                    selected: province,
                  );

                  if (picked == null || !mounted) return;

                  setState(() {
                    province = picked;
                  });

                  field.didChange(picked);
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'จังหวัด',
              prefixIcon: const Icon(Icons.location_city_outlined),
              suffixIcon: const Icon(Icons.expand_more_rounded),
              errorText: field.errorText ?? serverErrors['province'],
            ),
            isEmpty: province == null,
            child: Text(
              province ?? '',
              style: const TextStyle(color: AppColors.navy, fontSize: 15),
            ),
          ),
        );
      },
    );
  }

  Widget buildRulesAgreement() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: marketColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Checkbox(
            value: acceptedRules,
            activeColor: marketColor,
            onChanged: isSaving
                ? null
                : (value) {
                    setState(() {
                      acceptedRules = value ?? false;
                    });
                  },
          ),
          const Expanded(
            child: Text(
              'ฉันยอมรับกฎผู้ขาย',
              style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: marketColor),
            onPressed: () {
              dismissKeyboard();

              showSellerRulesDialog(context);
            },
            child: const Text('อ่านกฎ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String submitLabel = isNew
        ? 'ส่งคำขอเปิดร้าน'
        : isRejected
        ? 'แก้ไขแล้วส่งตรวจอีกครั้ง'
        : 'บันทึกข้อมูลร้าน';

    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'เปิดร้านใหม่' : 'แก้ไขข้อมูลร้าน')),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              if (isNew)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.softWarm,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'เปิดร้านฟรีช่วงเปิดตัว ลงสินค้าได้ 30 ชิ้น '
                    'ผู้ดูแลจะตรวจสอบร้านก่อนแสดงในตลาด',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              Center(child: buildLogoPicker()),
              const SizedBox(height: 20),
              buildSectionLabel('ข้อมูลร้าน'),
              TextFormField(
                controller: nameController,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'ชื่อร้าน',
                  prefixIcon: const Icon(Icons.storefront_outlined),
                  errorText: serverErrors['name'],
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'กรุณาใส่ชื่อร้าน' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: descriptionController,
                maxLength: 1000,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: 'ขายอะไร / จุดเด่นของร้าน (ไม่บังคับ)',
                  alignLabelWithHint: true,
                  errorText: serverErrors['description'],
                ),
              ),
              const SizedBox(height: 12),
              buildSectionLabel('หมวดของร้าน'),
              buildCategoryChips(),
              const SizedBox(height: 24),
              buildSectionLabel('ช่องทางติดต่อ'),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'เบอร์โทร',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  errorText: serverErrors['phone'],
                ),
                validator: (value) {
                  final String digits = (value ?? '').replaceAll(
                    RegExp(r'[\s\-]'),
                    '',
                  );

                  if (digits.isEmpty) return 'กรุณาใส่เบอร์โทร';

                  if (!RegExp(r'^\+?[0-9]{8,19}$').hasMatch(digits)) {
                    return 'เบอร์โทรไม่ถูกต้อง';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: lineController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'LINE ID (ไม่บังคับ)',
                  prefixIcon: const Icon(Icons.chat_outlined),
                  errorText: serverErrors['line_id'],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ผู้ซื้อจะเห็นเบอร์โทรและ LINE เมื่อร้านเปิดขาย',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 24),
              buildSectionLabel('พื้นที่ขาย'),
              buildProvinceField(),
              const SizedBox(height: 14),
              TextFormField(
                controller: districtController,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: 'อำเภอ / เขต (ไม่บังคับ)',
                  prefixIcon: const Icon(Icons.map_outlined),
                  errorText: serverErrors['district'],
                ),
              ),
              if (isNew) ...[const SizedBox(height: 12), buildRulesAgreement()],
              const SizedBox(height: 24),
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
                label: Text(isSaving ? 'กำลังบันทึก' : submitLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    phoneController.dispose();
    lineController.dispose();
    districtController.dispose();

    super.dispose();
  }
}
