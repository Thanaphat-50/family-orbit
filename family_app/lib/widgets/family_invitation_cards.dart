import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'user_avatar.dart';

// =======================================================
// การ์ดคำเชิญ / คำขอเข้าครอบครัว
// - InvitationCard: คำเชิญถึงเรา / คำขอเข้าครอบครัวเรา (มีปุ่มรับ + ปฏิเสธ)
// - PendingInvitationTile: รอตอบรับ (มีปุ่มยกเลิก)
// =======================================================

String _nameOf(dynamic user) {
  return user is Map ? (user['name']?.toString() ?? 'สมาชิก') : 'สมาชิก';
}

Map<String, dynamic> _avatarUser(dynamic user) {
  return {
    'name': _nameOf(user),
    'profile_photo_url': user is Map ? user['profile_image_url'] : null,
  };
}

class FamilyInvitationSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const FamilyInvitationSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 10),
        for (final child in children) ...[child, const SizedBox(height: 10)],
      ],
    );
  }
}

// incoming = true → คำเชิญถึงเรา (แสดงครอบครัว + คนชวน)
// incoming = false → คำขอเข้าครอบครัวเรา (แสดงคนที่ขอ)
class InvitationCard extends StatelessWidget {
  final Map<String, dynamic> invitation;
  final bool incoming;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const InvitationCard({
    super.key,
    required this.invitation,
    required this.incoming,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final dynamic family = invitation['family'];

    final String familyName = family is Map
        ? (family['name']?.toString() ?? 'ครอบครัว')
        : 'ครอบครัว';

    final int members = family is Map && family['members_count'] is num
        ? (family['members_count'] as num).toInt()
        : 0;

    final dynamic face = incoming ? invitation['creator'] : invitation['user'];

    final String title = incoming
        ? 'ครอบครัว $familyName'
        : '${_nameOf(invitation['user'])} ขอเข้าร่วม';

    final String detail = incoming
        ? '${_nameOf(invitation['creator'])} ชวนคุณ · สมาชิก $members คน'
        : 'ต้องการเข้าร่วมครอบครัวของคุณ';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: AppDecorations.card(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(user: _avatarUser(face), radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  child: const Text('ปฏิเสธ'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  child: Text(incoming ? 'เข้าร่วม' : 'อนุมัติ'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// รอตอบรับ: คำขอของเรา (แสดงครอบครัว) / คนที่ครอบครัวเราชวนไว้ (แสดงคน)
class PendingInvitationTile extends StatelessWidget {
  final Map<String, dynamic> invitation;
  final bool busy;
  final VoidCallback? onCancel;

  const PendingInvitationTile({
    super.key,
    required this.invitation,
    required this.busy,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final bool myRequest = invitation['type'] == 'request';

    final dynamic family = invitation['family'];

    final dynamic owner = family is Map ? family['owner'] : null;

    final String familyName = family is Map
        ? (family['name']?.toString() ?? 'ครอบครัว')
        : 'ครอบครัว';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: AppDecorations.card(radius: 18),
      child: Row(
        children: [
          UserAvatar(
            user: _avatarUser(myRequest ? owner : invitation['user']),
            radius: 19,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  myRequest
                      ? 'ครอบครัว $familyName'
                      : _nameOf(invitation['user']),
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  myRequest
                      ? 'รอ ${_nameOf(owner)} อนุมัติ'
                      : 'ชวนแล้ว · รอตอบรับ',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onCancel != null)
            TextButton(
              onPressed: busy ? null : onCancel,
              child: Text('ยกเลิก', style: TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}

// ถามอีเมลคนที่จะชวน (null = ยกเลิก)
Future<String?> askInviteEmail(BuildContext context) async {
  final TextEditingController controller = TextEditingController();

  final String? email = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('ชวนเข้าครอบครัว'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ใส่อีเมลที่เขาใช้สมัครแอปใกล้กัน เขาจะได้รับคำเชิญในแอป',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'อีเมล',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('ส่งคำเชิญ'),
        ),
      ],
    ),
  );

  Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);

  final String value = email?.trim() ?? '';

  return value.isEmpty ? null : value;
}
