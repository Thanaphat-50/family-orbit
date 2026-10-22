import 'package:flutter/material.dart';

import '../data/market_data.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

// =======================================================
// เมนูบัญชี (เลื่อนออกมาจากด้านซ้าย เมื่อกดรูปโปรไฟล์มุมซ้ายบน)
// - หัวเมนู: รูป ชื่อ ครอบครัว และตัวเลข (กดแล้วเปิดหน้าโปรไฟล์)
// - ทางลัดไปหน้าที่เกี่ยวกับบัญชีของเรา
// หน้าหลักเป็นคนเปิดหน้าต่าง ๆ (onSelected)
// =======================================================

enum AccountMenuItem {
  profile,
  myPosts,
  communityProfile,
  family,
  notifications,
  shop,
  settings,
  logout,
}

class AccountDrawer extends StatelessWidget {
  // ผลจาก GET /api/profile (user, family, role, stats) — ยังไม่โหลดก็ได้
  final Map<String, dynamic>? profile;

  // ชื่อที่รู้อยู่แล้ว ใช้ระหว่างรอโหลดโปรไฟล์
  final String fallbackName;

  final int unreadNotifications;

  final ValueChanged<AccountMenuItem> onSelected;

  const AccountDrawer({
    super.key,
    required this.profile,
    required this.fallbackName,
    required this.unreadNotifications,
    required this.onSelected,
  });

  static const Color communityColor = Color(0xFF0B7FA6);

  Map<String, dynamic> get user {
    final dynamic value = profile?['user'];

    return value is Map
        ? Map<String, dynamic>.from(value)
        : {'name': fallbackName};
  }

  String get name {
    final String text = user['name']?.toString().trim() ?? '';

    return text.isEmpty ? fallbackName : text;
  }

  String? get familyLine {
    final dynamic family = profile?['family'];

    if (family is! Map) return null;

    final String role = profile?['role'] == 'owner'
        ? 'เจ้าของครอบครัว'
        : 'สมาชิก';

    return '${family['name']} · $role';
  }

  bool get hasFamily => profile?['family'] is Map;

  int stat(String key) {
    final dynamic stats = profile?['stats'];

    final dynamic value = stats is Map ? stats[key] : null;

    return value is num ? value.toInt() : 0;
  }

  // ปิดเมนูก่อน แล้วค่อยให้หน้าหลักเปิดหน้าที่เลือก
  void select(BuildContext context, AccountMenuItem item) {
    Navigator.of(context).pop();

    onSelected(item);
  }

  // =====================================================
  // UI
  // =====================================================

  Widget buildHeader(BuildContext context) {
    final String? family = familyLine;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => select(context, AccountMenuItem.profile),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).padding.top + 22,
            20,
            20,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF172554), Color(0xFF4650D8), Color(0xFF666CFF)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(user: user, radius: 32, showBorder: true),
              const SizedBox(height: 12),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (family != null) ...[
                const SizedBox(height: 3),
                Text(
                  family,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.80),
                    fontSize: 12.5,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  buildHeaderStat('${stat('posts')}', 'โพสต์'),
                  const SizedBox(width: 18),
                  buildHeaderStat(
                    '${stat('likes_received')}',
                    'ถูกใจที่ได้รับ',
                  ),
                  const Spacer(),
                  Text(
                    'ดูโปรไฟล์',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildHeaderStat(String value, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget buildItem(
    BuildContext context, {
    required AccountMenuItem item,
    required IconData icon,
    required String title,
    String? subtitle,
    Color color = AppColors.primary,
    int badge = 0,
    bool danger = false,
  }) {
    return ListTile(
      onTap: () => select(context, item),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: danger ? AppColors.danger : AppColors.navy,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
      trailing: badge > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : null,
    );
  }

  Widget buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          buildHeader(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                buildSectionLabel('ของฉัน'),
                buildItem(
                  context,
                  item: AccountMenuItem.profile,
                  icon: Icons.person_outline_rounded,
                  title: 'โปรไฟล์',
                  subtitle: 'รูป ชื่อที่แสดง และบัญชีผู้ขาย',
                ),
                buildItem(
                  context,
                  item: AccountMenuItem.myPosts,
                  icon: Icons.article_outlined,
                  title: 'โพสต์ของฉัน',
                  subtitle: 'ทั้งในครอบครัวและชุมชน',
                ),
                if (hasFamily)
                  buildItem(
                    context,
                    item: AccountMenuItem.communityProfile,
                    icon: Icons.public_rounded,
                    title: 'โปรไฟล์ในชุมชน',
                    subtitle: 'ดูว่าคนในชุมชนเห็นคุณแบบไหน',
                    color: communityColor,
                  ),
                buildItem(
                  context,
                  item: AccountMenuItem.family,
                  icon: Icons.family_restroom_rounded,
                  title: 'ครอบครัวของฉัน',
                  subtitle: hasFamily
                      ? 'สมาชิกและรหัสเชิญ'
                      : 'สร้างหรือเข้าร่วมครอบครัว',
                  color: AppColors.sky,
                ),
                buildItem(
                  context,
                  item: AccountMenuItem.notifications,
                  icon: Icons.notifications_none_rounded,
                  title: 'การแจ้งเตือน',
                  badge: unreadNotifications,
                ),
                buildItem(
                  context,
                  item: AccountMenuItem.shop,
                  icon: Icons.storefront_outlined,
                  title: 'ร้านค้าของฉัน',
                  subtitle: 'เปิดร้าน จัดการสินค้า และดูสถานะร้าน',
                  color: marketColor,
                ),
                const Divider(height: 24, indent: 20, endIndent: 20),
                buildItem(
                  context,
                  item: AccountMenuItem.settings,
                  icon: Icons.settings_outlined,
                  title: 'ตั้งค่า',
                  subtitle: 'แจ้งเตือน ตำแหน่ง ความเป็นส่วนตัว บัญชี',
                  color: AppColors.muted,
                ),
                buildItem(
                  context,
                  item: AccountMenuItem.logout,
                  icon: Icons.logout_rounded,
                  title: 'ออกจากระบบ',
                  color: AppColors.danger,
                  danger: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
