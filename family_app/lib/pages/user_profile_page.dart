import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/post_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/community_sheets.dart';
import '../widgets/user_avatar.dart';
import 'chat_room_page.dart';
import 'feed_page.dart';

// =======================================================
// โปรไฟล์ในชุมชน (กดชื่อ/รูปในโพสต์หรือความคิดเห็นชุมชน)
// - รูป ชื่อ วันที่เข้าร่วม และตัวเลข
// - โพสต์ชุมชนของคนนี้ (ถูกใจ/แสดงความคิดเห็นได้เหมือนฟีด)
// - รายงาน / บล็อก / เลิกบล็อก
// ไม่แสดงอีเมลหรือครอบครัวของเขา
// =======================================================

class UserProfilePage extends StatefulWidget {
  final int userId;

  // ชื่อที่รู้อยู่แล้ว แสดงระหว่างโหลด
  final String? name;

  // บล็อก (true) / เลิกบล็อก (false) จากหน้านี้
  // หน้าที่เปิดมา (ฟีด) ใช้ซ่อน/โหลดโพสต์ของคนนี้ใหม่
  final ValueChanged<bool>? onBlockChanged;

  const UserProfilePage({
    super.key,
    required this.userId,
    this.name,
    this.onBlockChanged,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  static const Color likeColor = Color(0xFFE5486B);

  Map<String, dynamic>? profile;

  bool isLoading = true;

  String? loadError;

  // กำลังรายงาน / บล็อก / เลิกบล็อก
  bool isBusy = false;

  // เพิ่มค่าหลังเลิกบล็อก → โหลดโพสต์ใหม่
  int feedVersion = 0;

  @override
  void initState() {
    super.initState();

    loadProfile();
  }

  // =====================================================
  // โหลดข้อมูล
  // =====================================================

  Future<void> loadProfile() async {
    try {
      final result = await ProfileService.getPublicProfile(widget.userId);

      if (!mounted) return;

      final dynamic raw = result['profile'];

      if (result['status'] == true && raw is Map) {
        setState(() {
          profile = Map<String, dynamic>.from(raw);
          loadError = null;
        });
      } else {
        setState(() {
          loadError = result['message']?.toString() ?? 'ไม่พบผู้ใช้นี้';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loadError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> retryLoad() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    await loadProfile();
  }

  String get name =>
      profile?['name']?.toString() ?? widget.name ?? 'ผู้ใช้ในชุมชน';

  bool get isMe => profile?['is_me'] == true;

  bool get isBlocked => profile?['blocked'] == true;

  int countOf(String key) {
    final dynamic value = profile?[key];

    return value is num ? value.toInt() : 0;
  }

  // บทบาทในครอบครัวเดียวกัน (null = คนนอกครอบครัว)
  String? get familyRoleText {
    switch (profile?['family_role']) {
      case 'owner':
        return 'เจ้าของครอบครัว';
      case 'member':
        return 'สมาชิกครอบครัว';
    }

    return null;
  }

  String? get joinedText {
    final DateTime? date = DateTime.tryParse(
      profile?['joined_at']?.toString() ?? '',
    )?.toLocal();

    if (date == null) return null;

    const months = [
      '',
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];

    return 'เข้าร่วม ${months[date.month]} ${date.year}';
  }

  // =====================================================
  // รายงาน / บล็อก
  // =====================================================

  Future<void> reportUser() async {
    final String? reason = await showReportReasonSheet(
      context,
      title: 'รายงาน $name',
      reasons: userReportReasons,
      note: 'ผู้ใช้นี้จะไม่รู้ว่าใครเป็นคนรายงาน',
    );

    if (reason == null || !mounted) return;

    setState(() => isBusy = true);

    try {
      final result = await ProfileService.reportUser(
        userId: widget.userId,
        reason: reason,
      );

      if (!mounted) return;

      showMessage(
        result['message']?.toString() ??
            (result['status'] == true ? 'ขอบคุณที่รายงาน' : 'รายงานไม่สำเร็จ'),
      );
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  Future<void> blockUser() async {
    final bool confirmed = await showBlockUserDialog(context, name);

    if (!confirmed || !mounted) return;

    setState(() => isBusy = true);

    try {
      final result = await PostService.blockUser(widget.userId);

      if (!mounted) return;

      if (result['status'] == true) {
        markBlocked();
      }

      showMessage(
        result['message']?.toString() ??
            (result['status'] == true ? 'บล็อก $name แล้ว' : 'บล็อกไม่สำเร็จ'),
      );
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  Future<void> unblockUser() async {
    setState(() => isBusy = true);

    try {
      final result = await PostService.unblockUser(widget.userId);

      if (!mounted) return;

      if (result['status'] == true) {
        // โหลดตัวเลขใหม่ แล้วแสดงโพสต์ของเขาอีกครั้ง
        await loadProfile();

        if (!mounted) return;

        setState(() => feedVersion++);

        widget.onBlockChanged?.call(false);
      }

      showMessage(
        result['message']?.toString() ??
            (result['status'] == true ? 'เลิกบล็อกแล้ว' : 'เลิกบล็อกไม่สำเร็จ'),
      );
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  // บล็อกจากหน้านี้ หรือจากเมนูของโพสต์ในหน้านี้
  void markBlocked() {
    setState(() {
      profile = {...?profile, 'blocked': true};
    });

    widget.onBlockChanged?.call(true);
  }

  // แชทส่วนตัว (เฉพาะคนในครอบครัวเดียวกัน)
  bool get canChat =>
      profile?['is_family'] == true && !isMe && !isBlocked;

  Future<void> openChat() async {
    setState(() => isBusy = true);

    try {
      final result = await ChatService.openChat(widget.userId);

      if (!mounted) return;

      final dynamic room = result['conversation'];

      if (result['status'] == true && room is Map && room['id'] is num) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatRoomPage(
              conversationId: (room['id'] as num).toInt(),
              user: room['user'] is Map
                  ? Map<String, dynamic>.from(room['user'])
                  : null,
            ),
          ),
        );
      } else {
        showMessage(result['message']?.toString() ?? 'เปิดแชทไม่สำเร็จ');
      }
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // UI
  // =====================================================

  Widget buildMenu() {
    return PopupMenuButton<String>(
      tooltip: 'ตัวเลือก',
      enabled: !isBusy,
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) {
        switch (value) {
          case 'report':
            reportUser();
          case 'block':
            blockUser();
          case 'unblock':
            unblockUser();
        }
      },
      itemBuilder: (context) => [
        buildMenuItem(
          'report',
          Icons.flag_outlined,
          'รายงานผู้ใช้',
          AppColors.navy,
        ),
        if (isBlocked)
          buildMenuItem(
            'unblock',
            Icons.lock_open_rounded,
            'เลิกบล็อก',
            AppColors.navy,
          )
        else
          buildMenuItem(
            'block',
            Icons.block_rounded,
            'บล็อก',
            AppColors.danger,
          ),
      ],
    );
  }

  PopupMenuItem<String> buildMenuItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget buildChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildStat({
    required IconData icon,
    required Color color,
    required int value,
    required String label,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 5),
            Text(
              '$value',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget buildHeader() {
    final String? joined = joinedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: AppDecorations.cardBorder,
            boxShadow: AppDecorations.cardShadow,
          ),
          child: Column(
            children: [
              UserAvatar(
                user: {
                  'name': name,
                  'profile_photo_url': profile?['profile_image_url'],
                },
                radius: 42,
                showBorder: true,
              ),
              const SizedBox(height: 12),
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isMe)
                    buildChip(
                      Icons.visibility_outlined,
                      'คนอื่นเห็นโปรไฟล์ของคุณแบบนี้',
                      AppColors.primary,
                    ),
                  if (profile?['is_family'] == true)
                    buildChip(
                      Icons.family_restroom_rounded,
                      familyRoleText == null
                          ? 'ครอบครัวเดียวกัน'
                          : 'ครอบครัวเดียวกัน · $familyRoleText',
                      AppColors.success,
                    ),
                  if (joined != null)
                    buildChip(
                      Icons.calendar_month_outlined,
                      joined,
                      AppColors.muted,
                    ),
                ],
              ),
              if (canChat) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: isBusy ? null : openChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('ส่งข้อความ'),
                ),
              ],
              if (!isBlocked) ...[
                const SizedBox(height: 16),
                Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: buildStat(
                        icon: Icons.article_outlined,
                        color: AppColors.primary,
                        value: profile?['posts'] is num
                            ? countOf('posts')
                            : countOf('community_posts'),
                        label: 'โพสต์',
                      ),
                    ),
                    Container(width: 1, height: 36, color: AppColors.border),
                    Expanded(
                      child: buildStat(
                        icon: Icons.favorite_rounded,
                        color: likeColor,
                        value: countOf('likes_received'),
                        label: 'ถูกใจที่ได้รับ',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (!isBlocked) ...[
          const SizedBox(height: 20),
          Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'โพสต์',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget buildBlockedCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: AppDecorations.cardBorder,
        boxShadow: AppDecorations.cardShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.block_rounded, size: 36, color: AppColors.danger),
          const SizedBox(height: 12),
          Text(
            'คุณบล็อก $name อยู่',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'คุณจะไม่เห็นโพสต์และความคิดเห็นของผู้ใช้นี้ในชุมชน',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: isBusy ? null : unblockUser,
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('เลิกบล็อก'),
          ),
        ],
      ),
    );
  }

  Widget buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 44,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            Text(
              loadError ?? 'ไม่พบผู้ใช้นี้',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.navy, fontSize: 15),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: retryLoad,
              child: const Text('ลองอีกครั้ง'),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (profile == null) {
      return buildError();
    }

    if (isBlocked) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          buildHeader(),
          const SizedBox(height: 14),
          buildBlockedCard(),
        ],
      );
    }

    return FeedPage(
      key: ValueKey('user-${widget.userId}-$feedVersion'),
      scope: FeedScope.community,
      authorId: widget.userId,
      header: buildHeader(),
      onUserBlocked: (_) => markBlocked(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [if (profile != null && !isMe) buildMenu()],
      ),
      body: buildBody(),
    );
  }
}
