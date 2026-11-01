import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../config/app_info.dart';
import '../services/post_service.dart';
import '../services/social_service.dart';
import '../theme/app_theme.dart';
import '../widgets/comment_media.dart';
import '../widgets/community_sheets.dart';
import '../widgets/hashtag_text.dart';
import '../widgets/user_avatar.dart';
import 'post_detail_page.dart';
import 'user_profile_page.dart';

// =======================================================
// วิดีโอในชุมชนแบบเต็มจอ (แท็บ "วิดีโอ" ในหน้าหลัก)
// - ปัดขึ้น-ลง = คลิปถัดไป/ก่อนหน้า, แตะจอ = หยุด/เล่น
// - ด้านขวา: คนโพสต์ ถูกใจ ความคิดเห็น (เลื่อนขึ้นมาทับวิดีโอ) แชร์
// - ด้านล่างซ้าย: ชื่อคนโพสต์ + ข้อความ (#แฮชแท็กกดได้)
// - ปุ่มย้อนกลับ / ปัดไปทางขวา → กลับแท็บ "ล่าสุด" (onExit)
// - เล่นเฉพาะคลิปที่อยู่บนจอ หยุดเมื่อเปิดหน้าอื่นทับหรือออกจากแอป
// =======================================================

class VideoFeedPage extends StatefulWidget {
  final VoidCallback onExit;

  const VideoFeedPage({super.key, required this.onExit});

  @override
  State<VideoFeedPage> createState() => _VideoFeedPageState();
}

class _VideoFeedPageState extends State<VideoFeedPage> {
  final PageController pageController = PageController();

  List<Map<String, dynamic>> posts = [];

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = false;
  int page = 1;
  String? loadError;

  // คลิปที่อยู่บนจอ
  int current = 0;

  final Set<int> busyPostIds = {};

  // ผู้ใช้ที่ล็อกอินอยู่ (ความคิดเห็นของเรารายงานไม่ได้)
  Map<String, dynamic>? currentUser;

  @override
  void initState() {
    super.initState();

    loadVideos();
  }

  // =====================================================
  // โหลดวิดีโอ (ทีละหน้า เลื่อนใกล้ท้ายแล้วโหลดต่อ)
  // =====================================================

  Future<void> loadVideos({bool more = false}) async {
    if (more) {
      if (isLoading || isLoadingMore || !hasMore) return;

      setState(() => isLoadingMore = true);
    }

    final int nextPage = more ? page + 1 : 1;

    try {
      final result = await PostService.getPosts(
        scope: 'community',
        page: nextPage,
        media: 'video',
      );

      if (!mounted) return;

      if (result['status'] == true) {
        final dynamic raw = result['posts'];

        final List<Map<String, dynamic>> items = (raw is List ? raw : const [])
            .whereType<Map>()
            .map((post) => Map<String, dynamic>.from(post))
            .where((post) => post['video'] is Map)
            .toList();

        final dynamic me = result['current_user'];

        setState(() {
          if (me is Map) currentUser = Map<String, dynamic>.from(me);

          posts = more ? [...posts, ...items] : items;
          page = nextPage;
          hasMore = result['has_more'] == true;
          loadError = null;

          if (!more) current = 0;
        });

        if (!more && pageController.hasClients) pageController.jumpToPage(0);
      } else if (!more) {
        setState(() {
          loadError = result['message']?.toString() ?? 'โหลดวิดีโอไม่สำเร็จ';
        });
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

  void onPageChanged(int index) {
    setState(() => current = index);

    if (index >= posts.length - 2) loadVideos(more: true);
  }

  // =====================================================
  // ถูกใจ / ความคิดเห็น / แชร์ / โปรไฟล์
  // =====================================================

  int? postIdOf(Map<String, dynamic> post) => (post['id'] as num?)?.toInt();

  int countOf(dynamic value) => value is num ? value.toInt() : 0;

  bool isLiked(Map<String, dynamic> post) =>
      post['liked_by_me'] == true || post['liked_by_me'] == 1;

  Future<void> toggleLike(Map<String, dynamic> post) async {
    final int? postId = postIdOf(post);

    if (postId == null || !busyPostIds.add(postId)) return;

    final bool wasLiked = isLiked(post);

    final int oldCount = countOf(post['likes_count']);

    void restore() {
      post['liked_by_me'] = wasLiked;
      post['likes_count'] = oldCount;
    }

    // เปลี่ยนบนจอทันที ถ้า Server ตอบผิดพลาดค่อยคืนค่าเดิม
    setState(() {
      post['liked_by_me'] = !wasLiked;
      post['likes_count'] = wasLiked
          ? (oldCount > 0 ? oldCount - 1 : 0)
          : oldCount + 1;
    });

    try {
      final result = await PostService.toggleLike(postId);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          post['liked_by_me'] = result['liked'] == true;
          post['likes_count'] = result['likes_count'] ?? post['likes_count'];
        });
      } else {
        setState(restore);

        showMessage(result['message']?.toString() ?? 'ถูกใจไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      setState(restore);

      showMessage(e.toString());
    } finally {
      busyPostIds.remove(postId);
    }
  }

  // ความคิดเห็น / แชร์ในแอป ใช้หน้าโพสต์เดียว (การ์ดเดียวกับฟีด)
  Future<void> openPost(Map<String, dynamic> post) async {
    final int? postId = postIdOf(post);

    if (postId == null) return;

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PostDetailPage(postId: postId)));

    if (!mounted) return;

    // อาจแสดงความคิดเห็น / ถูกใจในหน้านั้น → ดึงตัวเลขล่าสุด
    try {
      final result = await PostService.getPost(postId);

      final dynamic fresh = result['post'];

      if (!mounted || result['status'] != true || fresh is! Map) return;

      setState(() {
        for (final key in [
          'comments',
          'likes_count',
          'liked_by_me',
          'shares_count',
        ]) {
          if (fresh.containsKey(key)) post[key] = fresh[key];
        }
      });
    } catch (_) {
      // ตัวเลขเดิมยังใช้ได้
    }
  }

  // ความคิดเห็น: เลื่อนขึ้นมาทับวิดีโอ อ่านและเขียนได้ในหน้านี้
  Future<void> openComments(Map<String, dynamic> post) async {
    if (postIdOf(post) == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _CommentsSheet(
        post: post,
        myId: (currentUser?['id'] as num?)?.toInt(),
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  // ส่งต่อไปแอปอื่น (LINE, Facebook ฯลฯ)
  Future<void> shareExternally(Map<String, dynamic> post) async {
    final int? postId = postIdOf(post);

    if (postId == null || busyPostIds.contains(postId)) return;

    final String content = post['content']?.toString().trim() ?? '';

    final String text = [
      if (content.isNotEmpty) content,
      '— ${authorName(post)} ในแอป${AppInfo.name}',
    ].join('\n\n');

    try {
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(text: text, subject: 'วิดีโอจากแอป${AppInfo.name}'),
      );

      // ปิดหน้าแชร์ไปโดยไม่ได้ส่ง → ไม่นับ
      if (result.status == ShareResultStatus.dismissed) return;

      final response = await SocialService.sharePost(
        postId,
        channel: 'external',
      );

      if (!mounted || response['status'] != true) return;

      setState(() => post['shares_count'] = response['shares_count']);
    } catch (_) {
      if (mounted) showMessage('เปิดหน้าแชร์ไม่ได้');
    }
  }

  Map<String, dynamic> authorOf(Map<String, dynamic> post) {
    final dynamic user = post['user'];

    return user is Map ? Map<String, dynamic>.from(user) : {};
  }

  String authorName(Map<String, dynamic> post) =>
      authorOf(post)['name']?.toString() ?? 'สมาชิก';

  void openProfile(Map<String, dynamic> post) {
    final int? userId = (authorOf(post)['id'] as num?)?.toInt();

    if (userId == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(userId: userId, name: authorName(post)),
      ),
    );
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // UI
  // =====================================================

  // หน้านี้วาดเต็มจอถึงขอบบน (ใต้แถบสถานะ) → ใช้ระยะขอบจริงของจอ
  double get statusBarHeight =>
      MediaQueryData.fromView(View.of(context)).padding.top;

  Widget buildAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 34, shadows: const [_shadow]),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                shadows: [_shadow],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const Shadow _shadow = Shadow(color: Colors.black54, blurRadius: 6);

  Widget buildClip(Map<String, dynamic> post, int index) {
    final Map<String, dynamic> author = authorOf(post);

    final bool liked = isLiked(post);

    final String content = post['content']?.toString().trim() ?? '';

    final double bottom = MediaQuery.paddingOf(context).bottom + 18;

    return Stack(
      fit: StackFit.expand,
      children: [
        _VideoClip(
          video: Map<String, dynamic>.from(post['video'] as Map),
          active: index == current,
        ),

        // ไล่เงาด้านล่างให้อ่านข้อความออก
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.55, 1],
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
          ),
        ),

        // ด้านขวา: คนโพสต์ ถูกใจ ความคิดเห็น แชร์
        Positioned(
          right: 8,
          bottom: bottom + 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => openProfile(post),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: UserAvatar(
                    user: {
                      'name': author['name'],
                      'profile_photo_url': author['profile_image_url'],
                    },
                    radius: 22,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              buildAction(
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: liked ? const Color(0xFFFF4D6D) : Colors.white,
                label: '${countOf(post['likes_count'])}',
                onTap: () => toggleLike(post),
              ),
              buildAction(
                icon: Icons.chat_bubble_rounded,
                label: '${(post['comments'] as List?)?.length ?? 0}',
                onTap: () => openComments(post),
              ),
              buildAction(
                icon: Icons.reply_rounded,
                label: '${countOf(post['shares_count'])}',
                onTap: () => shareExternally(post),
              ),
            ],
          ),
        ),

        // ด้านล่างซ้าย: ชื่อ + ข้อความ (แตะข้อความ = เปิดโพสต์)
        Positioned(
          left: 16,
          right: 84,
          bottom: bottom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => openProfile(post),
                child: Text(
                  authorName(post),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    shadows: [_shadow],
                  ),
                ),
              ),
              if (content.isNotEmpty) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => openPost(post),
                  child: HashtagText(
                    content,
                    tagColor: const Color(0xFFB9C7FF),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.4,
                      shadows: [_shadow],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget buildMessage({
    required IconData icon,
    required String title,
    required String message,
    String? action,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 52),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                child: Text(action),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (loadError != null && posts.isEmpty) {
      return buildMessage(
        icon: Icons.wifi_off_rounded,
        title: 'โหลดวิดีโอไม่สำเร็จ',
        message: loadError!,
        action: 'ลองอีกครั้ง',
        onAction: () {
          setState(() => isLoading = true);

          loadVideos();
        },
      );
    }

    if (posts.isEmpty) {
      return buildMessage(
        icon: Icons.smart_display_rounded,
        title: 'ยังไม่มีวิดีโอในชุมชน',
        message: 'แชร์วิดีโอได้จากแท็บ สำหรับคุณ หรือ ล่าสุด\nกดปุ่ม + แล้วเลือกวิดีโอ',
      );
    }

    // ดึงลงที่คลิปแรก = โหลดใหม่
    return RefreshIndicator(
      onRefresh: loadVideos,
      edgeOffset: statusBarHeight + 48,
      child: PageView.builder(
        controller: pageController,
        scrollDirection: Axis.vertical,
        itemCount: posts.length,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) => buildClip(posts[index], index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(child: buildBody()),

            // ด้านบน: ย้อนกลับไปแท็บ "ล่าสุด"
            Positioned(
              top: statusBarHeight + 4,
              left: 4,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'กลับ',
                    onPressed: widget.onExit,
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      shadows: [_shadow],
                    ),
                  ),
                  const Text(
                    'วิดีโอ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      shadows: [_shadow],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    pageController.dispose();

    super.dispose();
  }
}

// =======================================================
// คลิปเดียว: เล่นวนเมื่อ active และหน้านี้อยู่บนสุด
// แตะ = หยุด/เล่น
// =======================================================

class _VideoClip extends StatefulWidget {
  final Map<String, dynamic> video;

  final bool active;

  const _VideoClip({required this.video, required this.active});

  @override
  State<_VideoClip> createState() => _VideoClipState();
}

class _VideoClipState extends State<_VideoClip> {
  VideoPlayerController? controller;

  bool failed = false;

  // ผู้ใช้แตะหยุดเอง
  bool userPaused = false;

  // มีหน้าอื่นเปิดทับอยู่ (ความคิดเห็น / โปรไฟล์ / หน้าแชร์)
  bool routeVisible = true;

  // แอปถูกพับ / ปิดจอ
  bool appVisible = true;

  late final AppLifecycleListener lifecycle;

  @override
  void initState() {
    super.initState();

    lifecycle = AppLifecycleListener(
      onHide: () {
        appVisible = false;
        syncPlayback();
      },
      onShow: () {
        appVisible = true;
        syncPlayback();
      },
    );

    final String? url = widget.video['url']?.toString();

    if (url == null || url.isEmpty) {
      failed = true;
      return;
    }

    final VideoPlayerController player = VideoPlayerController.networkUrl(
      Uri.parse(url),
    );

    controller = player;

    player
        .initialize()
        .then((_) {
          if (!mounted) return;

          player.setLooping(true);

          setState(() {});

          syncPlayback();
        })
        .catchError((_) {
          if (mounted) setState(() => failed = true);
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // หน้าอื่นเปิดทับ → หยุด / ปิดหน้านั้นกลับมา → เล่นต่อ
    routeVisible = ModalRoute.isCurrentOf(context) ?? true;

    syncPlayback();
  }

  @override
  void didUpdateWidget(_VideoClip oldWidget) {
    super.didUpdateWidget(oldWidget);

    // เลื่อนกลับมาที่คลิปนี้ → เล่นต่อเสมอ
    if (widget.active && !oldWidget.active) userPaused = false;

    syncPlayback();
  }

  bool get shouldPlay =>
      widget.active && routeVisible && appVisible && !userPaused;

  void syncPlayback() {
    final VideoPlayerController? player = controller;

    if (player == null || !player.value.isInitialized) return;

    if (shouldPlay && !player.value.isPlaying) {
      player.play();
    } else if (!shouldPlay && player.value.isPlaying) {
      player.pause();
    }
  }

  void togglePause() {
    setState(() => userPaused = !userPaused);

    syncPlayback();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = controller;

    final bool ready = player != null && player.value.isInitialized;

    final String? thumbnail = widget.video['thumbnail_url']?.toString();

    // แนวตั้งเต็มจอ / แนวนอนพอดีกว้าง (ไม่ตัดภาพ)
    final BoxFit fit = ready && player.value.aspectRatio < 1
        ? BoxFit.cover
        : BoxFit.contain;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: ready ? togglePause : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: player.value.size.width,
                height: player.value.size.height,
                child: VideoPlayer(player),
              ),
            )
          else if (thumbnail != null && thumbnail.isNotEmpty)
            // รูปตัวอย่างแสดงเต็มภาพ (ขนาดที่บันทึกไว้อาจไม่ตรงกับภาพจริง)
            Image.network(
              thumbnail,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),

          if (failed)
            const Center(
              child: Text(
                'เปิดวิดีโอไม่ได้',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else if (!ready)
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          if (ready && userPaused)
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 52,
                ),
              ),
            ),

          // แถบเวลาบาง ๆ ด้านล่าง
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom,
              height: 3,
              child: VideoProgressIndicator(
                player,
                allowScrubbing: false,
                padding: EdgeInsets.zero,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    lifecycle.dispose();

    controller?.dispose();

    super.dispose();
  }
}

// =======================================================
// ความคิดเห็นของวิดีโอ (แผ่นที่เลื่อนขึ้นมาทับวิดีโอ)
// - เขียนความคิดเห็นได้ทันที (#แฮชแท็กกดได้)
// - แนบรูป / GIF / วิดีโอได้ 1 ไฟล์ แสดงย่อ แตะเพื่อดูเต็มจอ
// - แตะชื่อ/รูป = เปิดโปรไฟล์, กดค้างความคิดเห็นของคนอื่น = รายงาน
// =======================================================

class _CommentsSheet extends StatefulWidget {
  final Map<String, dynamic> post;

  final int? myId;

  // จำนวนความคิดเห็นเปลี่ยน → หน้าวิดีโอวาดตัวเลขใหม่
  final VoidCallback onChanged;

  const _CommentsSheet({
    required this.post,
    required this.myId,
    required this.onChanged,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  // ตรงกับ Laravel (content max:2000)
  static const int maxCommentLength = 2000;

  final TextEditingController input = TextEditingController();

  final ScrollController scrollController = ScrollController();

  bool sending = false;

  // ไฟล์ที่แนบไว้ (ยังไม่ส่ง) / กำลังเตรียมวิดีโอ (บีบอัด)
  CommentMediaFile? attachment;

  bool preparing = false;

  bool get canSend =>
      !sending &&
      !preparing &&
      (input.text.trim().isNotEmpty || attachment != null);

  Future<void> attachMedia() async {
    final CommentMediaFile? picked = await pickCommentMedia(
      context,
      onBusy: (busy) {
        if (mounted) setState(() => preparing = busy);
      },
    );

    if (picked != null && mounted) setState(() => attachment = picked);
  }

  // GIF / สติกเกอร์ที่กดจากคีย์บอร์ด
  Future<void> attachFromKeyboard(KeyboardInsertedContent content) async {
    final CommentMediaFile? picked = await commentMediaFromKeyboard(
      context,
      content,
    );

    if (picked != null && mounted) setState(() => attachment = picked);
  }

  List<dynamic> get comments => (widget.post['comments'] as List?) ?? [];

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> send() async {
    final String text = input.text.trim();

    final int? postId = (widget.post['id'] as num?)?.toInt();

    if (!canSend || postId == null) return;

    setState(() => sending = true);

    try {
      final result = await PostService.createComment(
        postId: postId,
        content: text,
        media: attachment,
      );

      if (!mounted) return;

      final dynamic comment = result['comment'];

      if (result['status'] == true && comment is Map) {
        setState(() {
          widget.post['comments'] = [
            ...comments,
            Map<String, dynamic>.from(comment),
          ];

          input.clear();

          attachment = null;
        });

        widget.onChanged();

        // เลื่อนลงไปที่ความคิดเห็นใหม่
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        showMessage(
          result['message']?.toString() ?? 'แสดงความคิดเห็นไม่สำเร็จ',
        );
      }
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void openProfile(Map<String, dynamic> user) {
    final int? userId = (user['id'] as num?)?.toInt();

    if (userId == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            UserProfilePage(userId: userId, name: user['name']?.toString()),
      ),
    );
  }

  Future<void> reportComment(int commentId, String name) async {
    final String? reason = await showReportReasonSheet(
      context,
      title: 'รายงานความคิดเห็นของ $name',
      note: 'เจ้าของความคิดเห็นจะไม่รู้ว่าใครเป็นคนรายงาน',
    );

    if (reason == null || !mounted) return;

    try {
      final result = await PostService.reportComment(
        commentId: commentId,
        reason: reason,
      );

      if (mounted) {
        showMessage(result['message']?.toString() ?? 'ขอบคุณที่รายงาน');
      }
    } catch (e) {
      if (mounted) showMessage(e.toString());
    }
  }

  static String timeAgo(dynamic value) {
    final DateTime? date = DateTime.tryParse(value?.toString() ?? '')
        ?.toLocal();

    if (date == null) return '';

    final Duration ago = DateTime.now().difference(date);

    if (ago.inMinutes < 1) return 'เมื่อสักครู่';
    if (ago.inMinutes < 60) return '${ago.inMinutes} นาที';
    if (ago.inHours < 24) return '${ago.inHours} ชั่วโมง';
    if (ago.inDays < 7) return '${ago.inDays} วัน';

    return '${date.day}/${date.month}/${date.year}';
  }

  Widget buildComment(Map<String, dynamic> comment) {
    final Map<String, dynamic> user = comment['user'] is Map
        ? Map<String, dynamic>.from(comment['user'] as Map)
        : {};

    final String name = user['name']?.toString() ?? 'สมาชิก';

    final int? commentId = (comment['id'] as num?)?.toInt();

    final int? authorId =
        (comment['user_id'] as num?)?.toInt() ?? (user['id'] as num?)?.toInt();

    final bool mine = authorId != null && authorId == widget.myId;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: commentId == null || mine
          ? null
          : () => reportComment(commentId, name),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => openProfile(user),
              child: UserAvatar(
                user: {
                  'name': name,
                  'profile_photo_url': user['profile_image_url'],
                },
                radius: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => openProfile(user),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: name,
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: '  ${timeAgo(comment['created_at'])}',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if ((comment['content']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    HashtagText(
                      comment['content'].toString(),
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (comment['media'] is Map) ...[
                    const SizedBox(height: 6),
                    CommentMediaThumb(
                      media: Map<String, dynamic>.from(comment['media'] as Map),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = comments
        .whereType<Map>()
        .map((comment) => Map<String, dynamic>.from(comment))
        .toList();

    return Padding(
      // ยกขึ้นเหนือคีย์บอร์ด
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            Text(
              'ความคิดเห็น ${items.length}',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: AppColors.border),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'ยังไม่มีความคิดเห็น\nเป็นคนแรกที่แสดงความคิดเห็น',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          buildComment(items[index]),
                    ),
            ),
            Divider(height: 1, color: AppColors.border),
            if (preparing)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'กำลังเตรียมวิดีโอ…',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              )
            else if (attachment != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CommentMediaPreview(
                    media: attachment!,
                    onRemove: () => setState(() => attachment = null),
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 6, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'แนบรูป GIF หรือวิดีโอ',
                      onPressed: sending || preparing ? null : attachMedia,
                      icon: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: input,
                        enabled: !sending,
                        // กด GIF / สติกเกอร์บนคีย์บอร์ด → แนบเป็นไฟล์
                        contentInsertionConfiguration:
                            ContentInsertionConfiguration(
                              allowedMimeTypes: commentKeyboardMimeTypes,
                              onContentInserted: attachFromKeyboard,
                            ),
                        minLines: 1,
                        maxLines: 4,
                        maxLength: maxCommentLength,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'เขียนความคิดเห็น... ใส่ #แฮชแท็ก ได้',
                          counterText: '',
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.fill,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: input,
                      builder: (context, value, child) => IconButton(
                        tooltip: 'ส่ง',
                        onPressed: canSend ? send : null,
                        icon: sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.send_rounded,
                                color: canSend
                                    ? AppColors.primary
                                    : AppColors.muted,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    input.dispose();
    scrollController.dispose();

    super.dispose();
  }
}
