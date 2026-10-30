import 'package:flutter/material.dart';

import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/market_sheets.dart';
import '../widgets/profile_intro.dart';

// =======================================================
// แก้ไขโปรไฟล์: ชื่อที่แสดง + ข้อมูลแนะนำตัว
// บันทึกสำเร็จ → pop(true) ให้หน้าที่เปิดมาโหลดใหม่
// =======================================================

class EditProfilePage extends StatefulWidget {
  final String name;

  final Map<String, String> intro;

  const EditProfilePage({super.key, required this.name, required this.intro});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController nameController = TextEditingController(
    text: widget.name,
  );

  late final TextEditingController bioController = TextEditingController(
    text: widget.intro['bio'] ?? '',
  );

  // ช่องที่พิมพ์เอง (ยกเว้นจังหวัด)
  late final Map<String, TextEditingController> detailControllers = {
    for (final field in introDetailFields)
      if (field.key != introProvinceKey)
        field.key: TextEditingController(text: widget.intro[field.key] ?? ''),
  };

  late String? province = widget.intro[introProvinceKey];

  bool isSaving = false;

  String? errorText;

  Map<String, String> get currentIntro => {
    'bio': bioController.text.trim(),
    for (final entry in detailControllers.entries)
      entry.key: entry.value.text.trim(),
    introProvinceKey: province ?? '',
  };

  bool get hasChanges {
    if (nameController.text.trim() != widget.name.trim()) return true;

    return currentIntro.entries.any(
      (entry) => entry.value != (widget.intro[entry.key] ?? ''),
    );
  }

  Future<void> pickProvince() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final String? picked = await showProvincePicker(
      context,
      selected: province,
    );

    if (picked != null && mounted) {
      setState(() => province = picked);
    }
  }

  Future<void> save() async {
    final String name = nameController.text.trim();

    if (name.isEmpty) {
      setState(() => errorText = 'กรุณาใส่ชื่อที่แสดง');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      isSaving = true;
      errorText = null;
    });

    try {
      final result = await ProfileService.updateProfile(
        name: name,
        intro: currentIntro,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(result['message']?.toString() ?? 'บันทึกแล้ว'),
            ),
          );

        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        errorText = result['message']?.toString() ?? 'บันทึกไม่สำเร็จ';
      });
    } catch (e) {
      if (mounted) setState(() => errorText = e.toString());
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // กดย้อนกลับขณะยังไม่บันทึก → ถามก่อนทิ้ง
  Future<void> confirmDiscard() async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ทิ้งการแก้ไข?'),
        content: const Text('ข้อมูลที่แก้ไว้จะไม่ถูกบันทึก'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('แก้ต่อ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ทิ้ง'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Widget buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
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

  Widget buildDetailField(IntroField field) {
    if (field.key == introProvinceKey) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isSaving ? null : pickProvince,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: field.label,
            prefixIcon: Icon(field.icon),
            suffixIcon: province == null
                ? const Icon(Icons.expand_more_rounded)
                : IconButton(
                    tooltip: 'ไม่ระบุ',
                    onPressed: isSaving
                        ? null
                        : () => setState(() => province = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          child: Text(
            province ?? field.hint,
            style: TextStyle(
              color: province == null ? AppColors.muted : AppColors.navy,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return TextField(
      controller: detailControllers[field.key],
      enabled: !isSaving,
      maxLength: field.maxLength,
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        prefixIcon: Icon(field.icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !hasChanges || isSaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('แก้ไขโปรไฟล์'),
          actions: [
            TextButton(
              onPressed: isSaving ? null : save,
              child: const Text('บันทึก'),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            buildLabel('ชื่อที่แสดง'),
            TextField(
              controller: nameController,
              enabled: !isSaving,
              maxLength: 100,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'ชื่อ',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 10),
            buildLabel('แนะนำตัว'),
            TextField(
              controller: bioController,
              enabled: !isSaving,
              maxLength: introBioMaxLength,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'เล่าเรื่องของคุณสั้น ๆ เช่น ชอบอะไร ทำอะไรอยู่',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            buildLabel('ข้อมูลเพิ่มเติม'),
            for (final field in introDetailFields) ...[
              buildDetailField(field),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.softSky,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.public_rounded, size: 18, color: AppColors.sky),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'คนในชุมชนเห็นข้อมูลนี้ทุกช่อง ไม่ต้องกรอกครบ และไม่ควรใส่เบอร์โทร ที่อยู่บ้าน หรือเลขบัญชี',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 14),
              Text(
                errorText!,
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: isSaving ? null : save,
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    bioController.dispose();

    for (final controller in detailControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }
}
