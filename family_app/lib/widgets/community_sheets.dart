import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

// =======================================================
// เหตุผลการรายงาน (ตรงกับ Laravel: reason)
// =======================================================

const Map<String, String> reportReasons = {
  'spam': 'สแปม / โฆษณา',
  'inappropriate': 'เนื้อหาไม่เหมาะสม',
  'harassment': 'ด่าทอ / คุกคาม',
  'scam': 'หลอกลวง / ข้อมูลเท็จ',
  'other': 'อื่น ๆ',
};

// เหตุผลการรายงานผู้ใช้ (ตรงกับ Laravel: UserReport::REASONS)
const Map<String, String> userReportReasons = {
  'spam': 'สแปม / โฆษณา',
  'harassment': 'ด่าทอ / คุกคาม',
  'inappropriate': 'เนื้อหาไม่เหมาะสม',
  'scam': 'หลอกลวง / ข้อมูลเท็จ',
  'impersonation': 'แอบอ้างเป็นคนอื่น',
  'other': 'อื่น ๆ',
};

// =======================================================
// กฎชุมชน
// คืนค่า true เมื่อผู้ใช้กด "ยอมรับ"
// =======================================================

Future<bool> showCommunityRulesDialog(BuildContext context) async {
  final bool? accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.softSky,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.public_rounded,
            color: Color(0xFF0B7FA6),
            size: 28,
          ),
        ),
        title: const Text('กฎชุมชน'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'โพสต์ชุมชนจะเห็นได้โดยผู้ใช้ทุกคนในแอป '
                'ไม่ใช่แค่ครอบครัวของคุณ',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              _RuleRow(
                icon: Icons.favorite_outline_rounded,
                text: 'สุภาพ ให้เกียรติกัน ไม่ด่าทอหรือคุกคาม',
              ),
              _RuleRow(
                icon: Icons.block_rounded,
                text: 'ไม่โพสต์เนื้อหาลามก รุนแรง หรือผิดกฎหมาย',
              ),
              _RuleRow(
                icon: Icons.campaign_outlined,
                text: 'ไม่สแปม ไม่หลอกลวง',
              ),
              _RuleRow(
                icon: Icons.lock_outline_rounded,
                text: 'อย่าโพสต์ที่อยู่ เบอร์โทร หรือตำแหน่งของครอบครัว',
              ),
              SizedBox(height: 10),
              Text(
                'โพสต์ที่ถูกรายงานจะถูกตรวจสอบ และอาจถูกซ่อน',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: AppColors.navy,
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('ยกเลิก'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('ยอมรับ'),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  return accepted == true;
}

class _RuleRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RuleRow({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// เมนูบนความคิดเห็นของคนอื่น (ฟีดชุมชน)
// คืนค่า 'report' / 'block' หรือ null ถ้ายกเลิก
// =======================================================

Future<String?> showCommentActionsSheet(
  BuildContext context, {
  required String authorName,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ความคิดเห็นของ $authorName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.flag_outlined,
                  color: AppColors.navy,
                ),
                title: Text(
                  'รายงานความคิดเห็น',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop('report');
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.block_rounded,
                  color: AppColors.danger,
                ),
                title: Text(
                  'บล็อก $authorName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop('block');
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

// =======================================================
// เลือกเหตุผลการรายงาน
// คืนค่า key ของเหตุผล หรือ null ถ้ายกเลิก
// =======================================================

// reasons: เหตุผลให้เลือก (ตลาด/ผู้ใช้ใช้ชุดของตัวเอง)
// note:    ข้อความใต้หัวข้อ
Future<String?> showReportReasonSheet(
  BuildContext context, {
  String title = 'รายงานโพสต์นี้',
  Map<String, String> reasons = reportReasons,
  String note = 'เจ้าของจะไม่รู้ว่าใครเป็นคนรายงาน',
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                note,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              ...reasons.entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.flag_outlined,
                    color: AppColors.danger,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop(entry.key);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// =======================================================
// ยืนยันการบล็อก
// =======================================================

Future<bool> showBlockUserDialog(
  BuildContext context,
  String name,
) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.block_rounded,
            color: AppColors.danger,
            size: 28,
          ),
        ),
        title: Text('บล็อก $name?'),
        content: const Text(
          'จะไม่เห็นโพสต์และความคิดเห็นของคนนี้ในชุมชน\n'
          'เลิกบล็อกได้ภายหลัง',
          textAlign: TextAlign.center,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: AppColors.navy,
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('ยกเลิก'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('บล็อก'),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  return confirmed == true;
}

// =======================================================
// รายชื่อผู้ใช้ที่บล็อก (เลิกบล็อกได้)
// onChanged ถูกเรียกเมื่อมีการเลิกบล็อก
// =======================================================

Future<void> showBlockedUsersSheet(
  BuildContext context, {
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _BlockedUsersSheet(onChanged: onChanged);
    },
  );
}

class _BlockedUsersSheet extends StatefulWidget {
  final VoidCallback onChanged;

  const _BlockedUsersSheet({
    required this.onChanged,
  });

  @override
  State<_BlockedUsersSheet> createState() => _BlockedUsersSheetState();
}

class _BlockedUsersSheetState extends State<_BlockedUsersSheet> {
  bool isLoading = true;
  String? error;

  List<Map<String, dynamic>> users = [];

  final Set<int> unblockingIds = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await PostService.getBlockedUsers();

      if (!mounted) return;

      final dynamic rawUsers = result['users'];

      setState(() {
        users = rawUsers is List
            ? rawUsers
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];

        error = result['status'] == true
            ? null
            : (result['message']?.toString() ?? 'โหลดรายชื่อไม่สำเร็จ');
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> unblock(Map<String, dynamic> user) async {
    final dynamic rawId = user['id'];

    if (rawId is! num) return;

    final int userId = rawId.toInt();

    setState(() {
      unblockingIds.add(userId);
    });

    try {
      final result = await PostService.unblockUser(userId);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          users.removeWhere((item) => item['id'] == rawId);
        });

        widget.onChanged();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message']?.toString() ?? 'เลิกบล็อกไม่สำเร็จ',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          unblockingIds.remove(userId);
        });
      }
    }
  }

  Widget buildBody() {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text(
            error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }

    if (users.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            'ยังไม่ได้บล็อกใคร',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: users.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = users[index];

        final dynamic rawId = user['id'];

        final bool busy =
            rawId is num && unblockingIds.contains(rawId.toInt());

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: UserAvatar(
            radius: 20,
            user: {
              'name': user['name'],
              'profile_photo_url': user['profile_image_url'],
            },
          ),
          title: Text(
            user['name']?.toString() ?? 'สมาชิก',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    unblock(user);
                  },
                  child: const Text('เลิกบล็อก'),
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ผู้ใช้ที่บล็อก',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'โพสต์และความคิดเห็นของคนเหล่านี้จะไม่แสดงในชุมชน',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(child: buildBody()),
            ],
          ),
        ),
      ),
    );
  }
}
