import 'package:flutter/material.dart';

import '../services/social_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'post_detail_page.dart';
import 'user_profile_page.dart';

// =======================================================
// ประวัติการใช้งาน แยกแท็บ: ถูกใจ / ความคิดเห็น / แชร์ / ติดตาม
// เห็นได้เฉพาะเรา ใช้จัดฟีด "สำหรับคุณ" และแนะนำคนที่ชอบคล้ายกัน
// =======================================================

class _HistoryTabInfo {
  final String type;
  final String label;
  final IconData icon;
  final Color color;
  final String empty;

  const _HistoryTabInfo(
    this.type,
    this.label,
    this.icon,
    this.color,
    this.empty,
  );
}

const Color _likeColor = Color(0xFFE5486B);

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  static final List<_HistoryTabInfo> tabs = [
    const _HistoryTabInfo(
      'like',
      'ถูกใจ',
      Icons.favorite_rounded,
      _likeColor,
      'โพสต์ที่คุณกดหัวใจจะอยู่ที่นี่',
    ),
    _HistoryTabInfo(
      'comment',
      'ความคิดเห็น',
      Icons.chat_bubble_rounded,
      AppColors.primary,
      'ความคิดเห็นที่คุณเขียนจะอยู่ที่นี่',
    ),
    _HistoryTabInfo(
      'share',
      'แชร์',
      Icons.share_rounded,
      AppColors.success,
      'โพสต์ที่คุณแชร์จะอยู่ที่นี่',
    ),
    _HistoryTabInfo(
      'follow',
      'ติดตาม',
      Icons.person_add_alt_1_rounded,
      AppColors.sky,
      'คนที่คุณติดตามจะอยู่ที่นี่',
    ),
  ];

  late final TabController tabController = TabController(
    length: tabs.length,
    vsync: this,
  );

  // จำนวนของแต่ละแท็บ (ได้จาก Server ทุกครั้งที่โหลด)
  Map<String, int> counts = {};

  // เพิ่มเมื่อล้างประวัติ → แท็บนั้นโหลดใหม่
  final Map<String, int> versions = {};

  @override
  void initState() {
    super.initState();

    tabController.addListener(() {
      if (!tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  void updateCounts(dynamic raw) {
    if (raw is! Map || !mounted) return;

    setState(() {
      counts = raw.map(
        (key, value) => MapEntry('$key', value is num ? value.toInt() : 0),
      );
    });
  }

  Future<void> clearCurrentTab() async {
    final _HistoryTabInfo tab = tabs[tabController.index];

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('ล้างประวัติ${tab.label}?'),
        content: const Text(
          'ฟีด "สำหรับคุณ" และคนที่แนะนำจะเรียนรู้ความสนใจของคุณใหม่ '
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
      final result = await SocialService.clearHistory(type: tab.type);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          counts = {...counts, tab.type: 0};
          versions[tab.type] = (versions[tab.type] ?? 0) + 1;
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

  @override
  Widget build(BuildContext context) {
    final bool hasItems = (counts[tabs[tabController.index].type] ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติการใช้งาน'),
        actions: [
          if (hasItems)
            TextButton(
              onPressed: clearCurrentTab,
              child: Text('ล้าง', style: TextStyle(color: AppColors.danger)),
            ),
        ],
        bottom: TabBar(
          controller: tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            for (final tab in tabs)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab.icon, size: 17, color: tab.color),
                    const SizedBox(width: 6),
                    Text(
                      (counts[tab.type] ?? 0) > 0
                          ? '${tab.label} ${counts[tab.type]}'
                          : tab.label,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          for (final tab in tabs)
            _HistoryList(
              key: ValueKey('${tab.type}-${versions[tab.type] ?? 0}'),
              tab: tab,
              onCounts: updateCounts,
            ),
        ],
      ),
    );
  }
}

// รายการของแท็บเดียว (โหลดทีละหน้า และจำไว้เมื่อสลับแท็บ)
class _HistoryList extends StatefulWidget {
  final _HistoryTabInfo tab;

  final ValueChanged<dynamic> onCounts;

  const _HistoryList({super.key, required this.tab, required this.onCounts});

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList>
    with AutomaticKeepAliveClientMixin {
  final List<Map<String, dynamic>> items = [];

  final ScrollController scrollController = ScrollController();

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = false;
  int page = 1;
  String? loadError;

  @override
  bool get wantKeepAlive => true;

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
      final result = await SocialService.history(
        page: next,
        type: widget.tab.type,
      );

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

        widget.onCounts(result['counts']);
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

  static String nameOf(dynamic user) {
    return user is Map ? (user['name']?.toString() ?? 'สมาชิก') : 'สมาชิก';
  }

  String titleOf(Map<String, dynamic> item) {
    final dynamic post = item['post'];

    final String owner = nameOf(post is Map ? post['user'] : null);

    switch (item['type']) {
      case 'like':
        return 'ถูกใจโพสต์ของ $owner';
      case 'comment':
        return 'แสดงความคิดเห็นในโพสต์ของ $owner';
      case 'share':
        const Map<String, String> where = {
          'external': 'ส่งต่อไปแอปอื่น',
          'community': 'แชร์ในชุมชน',
          'family': 'ส่งให้ครอบครัว',
        };

        return '${where[item['channel']] ?? 'แชร์'} · โพสต์ของ $owner';
      case 'follow':
        return 'ติดตาม ${nameOf(item['target_user'])}';
      default:
        return 'ใช้งาน';
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
    final dynamic post = item['post'];

    final String detail = item['type'] == 'comment'
        ? '"${item['excerpt'] ?? ''}"'
        : post is Map
        ? (post['content']?.toString() ?? '')
        : '';

    final dynamic face = item['type'] == 'follow'
        ? item['target_user']
        : (post is Map ? post['user'] : null);

    final String? imageUrl = post is Map ? post['image_url']?.toString() : null;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openItem(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
                        color: widget.tab.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                      child: Icon(
                        widget.tab.icon,
                        size: 11,
                        color: Colors.white,
                      ),
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
                      titleOf(item),
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
              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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

    return RefreshIndicator(
      onRefresh: load,
      child: items.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Icon(widget.tab.icon, size: 46, color: widget.tab.color),
                const SizedBox(height: 12),
                Text(
                  widget.tab.empty,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
              ],
            )
          : ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
            ),
    );
  }
}
