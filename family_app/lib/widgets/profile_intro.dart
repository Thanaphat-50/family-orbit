import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// =======================================================
// ข้อมูลแนะนำตัวบนหน้าโปรไฟล์
// - ความยาวแต่ละช่องตรงกับ Laravel (ProfileController::update)
// - คนในชุมชนเห็นได้ทุกช่อง ไม่บังคับกรอก
// =======================================================

const int introBioMaxLength = 300;

class IntroField {
  final String key;
  final String label;
  final IconData icon;
  final int maxLength;
  final String hint;

  const IntroField(this.key, this.label, this.icon, this.maxLength, this.hint);
}

// จังหวัดเลือกจากรายการ (ไม่ได้พิมพ์เอง)
const String introProvinceKey = 'province';

const List<IntroField> introDetailFields = [
  IntroField(
    'occupation',
    'งาน/อาชีพ',
    Icons.work_outline_rounded,
    80,
    'เช่น ครู ค้าขาย นักศึกษา',
  ),
  IntroField(
    'education',
    'การศึกษา',
    Icons.school_outlined,
    80,
    'เช่น ม.6 โรงเรียนบ้านสวน',
  ),
  IntroField(
    introProvinceKey,
    'อาศัยอยู่ที่',
    Icons.location_city_outlined,
    60,
    'เลือกจังหวัด',
  ),
  IntroField(
    'interests',
    'ความสนใจ',
    Icons.interests_outlined,
    150,
    'เช่น ทำอาหาร ปลูกต้นไม้ ฟุตบอล',
  ),
];

// ข้อมูลจาก API → เฉพาะช่องที่กรอกแล้ว
Map<String, String> introFrom(dynamic raw) {
  if (raw is! Map) return {};

  final Map<String, String> intro = {};

  for (final key in ['bio', ...introDetailFields.map((field) => field.key)]) {
    final String value = raw[key]?.toString().trim() ?? '';

    if (value.isNotEmpty) intro[key] = value;
  }

  return intro;
}

class ProfileIntroCard extends StatelessWidget {
  final Map<String, String> intro;

  // โปรไฟล์ของเราเอง: มีปุ่มแก้ไข และชวนกรอกเมื่อยังว่าง
  final VoidCallback? onEdit;

  const ProfileIntroCard({super.key, required this.intro, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final String? bio = intro['bio'];

    final List<IntroField> details = introDetailFields
        .where((field) => intro[field.key] != null)
        .toList();

    if (bio == null && details.isEmpty && onEdit == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
      decoration: AppDecorations.card(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.waving_hand_rounded, size: 18, color: AppColors.warm),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'แนะนำตัว',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onEdit != null)
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('แก้ไข'),
                )
              else
                const SizedBox(height: 40),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bio != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    bio,
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
                for (final field in details) ...[
                  const SizedBox(height: 10),
                  buildDetail(field, intro[field.key]!),
                ],
                if (bio == null && details.isEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'เล่าเรื่องของคุณสั้น ๆ เช่น งาน ความสนใจ หรือจังหวัดที่อยู่ ให้คนในชุมชนรู้จักคุณมากขึ้น',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('เพิ่มข้อมูลแนะนำตัว'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDetail(IntroField field, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(field.icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${field.label}  ',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
