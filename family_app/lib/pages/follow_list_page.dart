import 'package:flutter/material.dart';

import '../services/social_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'user_profile_page.dart';

// =======================================================
// รายชื่อผู้ติดตาม / กำลังติดตาม ของเราเอง (กดตัวเลขในหน้าโปรไฟล์)
// ติดตามกลับ / เลิกติดตามได้จากหน้านี้
// pop(true) เมื่อมีการเปลี่ยน → หน้าโปรไฟล์โหลดตัวเลขใหม่
// =======================================================

class FollowListPage extends StatefulWidget {
  // true = ผู้ติดตาม / false = กำลังติดตาม
  final bool followers;

  const FollowListPage({super.key, required this.followers});

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> {
  final List<Map<String, dynamic>> users = [];

  int page = 1;
  bool hasMore = false;
  bool isLoading = true;
  bool isLoadingMore = false;
  String? loadError;

  final Set<int> busyIds = {};

  bool changed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (more && (isLoading || isLoadingMore || !hasMore)) return;

    setState(() {
      if (more) {
        isLoadingMore = true;
      } else {
        loadError = null;
      }
    });

    final int nextPage = more ? page + 1 : 1;

    try {
      final result = await SocialService.getFollowList(
        followers: widget.followers,
        page: nextPage,
      );

      if (!mounted) return;

      if (result['status'] != true) {
        showError(result['message']?.toString() ?? 'โหลดรายชื่อไม่สำเร็จ');
        return;
      }

      final dynamic raw = result['users'];

      setState(() {
        if (!more) users.clear();

        if (raw is List) {
          users.addAll(
            raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)),
          );
        }

        page = nextPage;
        hasMore = result['has_more'] == true;
      });
    } catch (_) {
      if (mounted) {
        showError('เชื่อมต่อไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง');
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isLoadingMore = false;
        });
      }
    }
  }

  // ยังไม่มีรายชื่อในจอ → แสดงหน้าลองอีกครั้ง / มีอยู่แล้ว → แจ้งแล้วคงรายชื่อเดิม
  void showError(String message) {
    if (users.isEmpty) {
      setState(() => loadError = message);
    } else {
      showMessage(message);
    }
  }

  Future<void> toggleFollow(Map<String, dynamic> user) async {
    final int? id = (user['id'] as num?)?.toInt();

    if (id == null || busyIds.contains(id)) return;

    final bool follow = user['is_following'] != true;

    setState(() => busyIds.add(id));

    try {
      final result = await SocialService.setFollowing(id, follow);

      if (!mounted) return;

      if (result['status'] == true) {
        changed = true;

        setState(() => user['is_following'] = result['is_following'] == true);
      } else {
        showMessage(result['message']?.toString() ?? 'ทำรายการไม่สำเร็จ');
      }
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => busyIds.remove(id));
    }
  }

  Future<void> openProfile(Map<String, dynamic> user) async {
    final int? id = (user['id'] as num?)?.toInt();

    if (id == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            UserProfilePage(userId: id, name: user['name']?.toString()),
      ),
    );

    // อาจติดตาม/เลิกติดตามจากหน้าโปรไฟล์ของเขา
    if (mounted) {
      changed = true;
      await load();
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

  Widget buildTile(Map<String, dynamic> user) {
    final int? id = (user['id'] as num?)?.toInt();

    final bool following = user['is_following'] == true;
    final bool followsMe = user['follows_me'] == true;

    final String? relation = following && followsMe
        ? 'ติดตามกันและกัน'
        : followsMe
        ? 'ติดตามคุณ'
        : null;

    final bool busy = id != null && busyIds.contains(id);

    // ธีมของแอปให้ปุ่มกว้างเต็มจอ → ในแถวต้องกำหนดขนาดเอง
    const Size buttonSize = Size(0, 36);
    const EdgeInsets buttonPadding = EdgeInsets.symmetric(horizontal: 14);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: UserAvatar(user: user, radius: 22),
      title: Text(
        user['name']?.toString() ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700),
      ),
      subtitle: relation == null
          ? null
          : Text(
              relation,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
      onTap: () => openProfile(user),
      trailing: following
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: buttonSize,
                padding: buttonPadding,
              ),
              onPressed: busy ? null : () => toggleFollow(user),
              child: const Text('ติดตามแล้ว'),
            )
          : FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: buttonSize,
                padding: buttonPadding,
              ),
              onPressed: busy ? null : () => toggleFollow(user),
              child: Text(followsMe ? 'ติดตามกลับ' : 'ติดตาม'),
            ),
    );
  }

  Widget buildMessage({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 90, 32, 32),
      children: [
        Icon(icon, size: 48, color: AppColors.muted),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
        ),
        if (action != null) ...[
          const SizedBox(height: 16),
          Center(child: action),
        ],
      ],
    );
  }

  Widget buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (loadError != null && users.isEmpty) {
      return buildMessage(
        icon: Icons.cloud_off_rounded,
        title: 'โหลดรายชื่อไม่สำเร็จ',
        message: loadError!,
        action: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
          onPressed: () {
            setState(() => isLoading = true);
            load();
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('ลองอีกครั้ง'),
        ),
      );
    }

    if (users.isEmpty) {
      return widget.followers
          ? buildMessage(
              icon: Icons.people_outline_rounded,
              title: 'ยังไม่มีผู้ติดตาม',
              message: 'เมื่อมีคนกดติดตามคุณในชุมชน รายชื่อจะแสดงที่นี่',
            )
          : buildMessage(
              icon: Icons.person_add_alt_outlined,
              title: 'คุณยังไม่ได้ติดตามใคร',
              message:
                  'กด "ติดตาม" ในโปรไฟล์ของคนในชุมชน เพื่อเห็นโพสต์ของเขาก่อน',
            );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 300) load(more: true);

        return false;
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        itemCount: users.length + (isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= users.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          return buildTile(users[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        Navigator.of(context).pop(changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.followers ? 'ผู้ติดตาม' : 'กำลังติดตาม'),
        ),
        body: RefreshIndicator(onRefresh: load, child: buildBody()),
      ),
    );
  }
}
