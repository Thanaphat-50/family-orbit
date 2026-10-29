import 'package:flutter/material.dart';

import '../services/social_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'post_detail_page.dart';
import 'user_profile_page.dart';

// =======================================================
// ประวัติการใช้งาน: ถูกใจ / ความคิดเห็น / แชร์ / ติดตาม
// เห็นได้เฉพาะเรา ใช้จัดฟีด "สำหรับคุณ" และแนะนำคนที่ชอบคล้ายกัน
// =======================================================

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final List<Map<String, dynamic>> items = [];

  final ScrollController scrollController = ScrollController();

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = false;
  int page = 1;
  String? loadError;

  @override
  void initState() {
    super.initState();

    scrollController.addListener(() {
      if (scrollController.position.extentAfter < 400) load(more: true);
    });

    load();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (more && (isLoading || isLoadingMore || !hasMore)) return;

    final int next = more ? page + 1 : 1;

    if (more) setState(() => isLoadingMore = true);

    try {
      final result = await SocialService.history(page: next);

      if (!mounted) return;

      final dynamic raw = result['items'];

      if (result['status'] == true && raw is List) {
        setState(() {
          if (!more) items.clear();

          items.addAll(
            raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)),
          );

          page = next;
          hasMore = result['has_more'] == true;
          loadError = null;
        });
      } else if (!more) {
        setState(
          () => loadError = result['message']?.toString() ?? 'โหลดไม่สำเร็จ',
        );
      }
    } catch (e) {
      if (mounted && !more) setState(() => loadError = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isLoadingMore = false;
        });
      }
    }
  }

  Future<void> clearHistory() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ล้างประวัติการใช้งาน?'),
        content: const Text(
          'ฟีด "สำหรับคุณ" และคนที่แนะนำจะเริ่มเรียนรู้ความสนใจของคุณใหม่ '
          '(การถูกใจ ความคิดเห็น และการติดตามจริงยังอยู่)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ล้างประวัติ'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final result = await SocialService.clearHistory();

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          items.clear();
          hasMore = false;
        });
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? 'ล้างประวัติแล้ว'),
          ),
        );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // =====================================================
  // ข้อความของแต่ละรายการ
  // =====================================================

  static String nameOf(dynamic user) {
    return user is Map ? (user['name']?.toString() ?? 'สมาชิก') : 'สมาชิก';
  }

  ({IconData icon, Color color, String title}) describe(
    Map<String, dynamic> item,
  ) {
    final dynamic post = item['post'];

    final String owner = nameOf(post is Map ? post['user'] : null);

    switch (item['type']) {
      case 'like':
        return (
          icon: Icons.favorite_rounded,
          color: const Color(0xFFE5486B),
          title: 'ถูกใจโพสต์ของ $owner',
        );
      case 'comment':
        return (
          icon: Icons.chat_bubble_rounded,
          color: AppColors.primary,
          title: 'แสดงความคิดเห็นในโพสต์ของ $owner',
        );
      case 'share':
        const Map<String, String> where = {
          'external': 'ส่งต่อไปแอปอื่น',
          'community': 'แชร์ในชุมชน',
          'family': 'ส่งให้ครอบครัว',
        };

        return (
          icon: Icons.share_rounded,
          color: AppColors.success,
          title: '${where[item['channel']] ?? 'แชร์'}: โพสต์ของ $owner',
        );
      case 'follow':
        return (
          icon: Icons.person_add_alt_1_rounded,
          color: AppColors.sky,
          title: 'ติดตาม ${nameOf(item['target_user'])}',
        );
      default:
        return (
          icon: Icons.history_rounded,
          color: AppColors.muted,
          title: 'ใช้งาน',
        );
    }
  }

  static String formatTime(dynamic value) {
    final DateTime? date = DateTime.tryParse(value?.toString() ?? '')
        ?.toLocal();

    if (date == null) return '';

    final Duration ago = DateTime.now().difference(date);

    if (ago.inMinutes < 1) return 'เมื่อสักครู่';
    if (ago.inMinutes < 60) return '${ago.inMinutes} นาทีที่แล้ว';
    if (ago.inHours < 24) return '${ago.inHours} ชั่วโมงที่แล้ว';
    if (ago.inDays < 7) return '${ago.inDays} วันที่แล้ว';

    return '${date.day}/${date.month}/${date.year}';
  }

  void openItem(Map<String, dynamic> item) {
    final dynamic post = item['post'];

    final dynamic target = item['target_user'];

    if (item['type'] == 'follow' && target is Map && target['id'] is num) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserProfilePage(
            userId: (target['id'] as num).toInt(),
            name: nameOf(target),
          ),
        ),
      );
    } else if (post is Map && post['id'] is num) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostDetailPage(postId: (post['id'] as num).toInt()),
        ),
      );
    }
  }

  Widget buildItem(Map<String, dynamic> item) {
    final info = describe(item);

    final dynamic post = item['post'];

    final String detail = item['type'] == 'comment'
        ? '"${item['excerpt'] ?? ''}"'
        : post is Map
        ? (post['content']?.toString() ?? '')
        : '';

    final dynamic face = item['type'] == 'follow'
        ? item['target_user']
        : (post is Map ? post['user'] : null);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openItem(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    user: face is Map
                        ? {
                            'name': nameOf(face),
                            'profile_photo_url': face['profile_image_url'],
                          }
                        : {'name': '?'},
                    radius: 22,
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: info.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                      child: Icon(info.icon, size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    if (detail.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      formatTime(item['created_at']),
                      style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildBody() {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    if (loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() => isLoading = true);
                  load();
                },
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.history_rounded, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            'ยังไม่มีประวัติ\nกดถูกใจ แสดงความคิดเห็น แชร์ หรือติดตามแล้วจะขึ้นที่นี่',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: items.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return buildItem(items[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติการใช้งาน'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: clearHistory,
              child: Text(
                'ล้างประวัติ',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(onRefresh: load, child: buildBody()),
    );
  }
}
