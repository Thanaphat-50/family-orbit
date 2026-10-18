import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../widgets/community_sheets.dart';

// ฟีด "ครอบครัว" (เฉพาะครอบครัว) และ "ชุมชน" (ทุกคนในแอป)
enum FeedScope { family, community }

// ข้อมูลของแต่ละฟีด แยกกันเพื่อสลับแท็บได้โดยไม่ต้องโหลดใหม่
class _ScopeFeed {
  List<Map<String, dynamic>> posts = [];

  bool isLoading = true;
  bool isLoadingMore = false;

  // โหลดครั้งแรกสำเร็จแล้ว
  bool loaded = false;

  // ข้อความ Error เมื่อโหลดครั้งแรกไม่สำเร็จ
  String? loadError;

  // การแบ่งหน้า (ใช้กับฟีดชุมชน)
  int page = 1;
  bool hasMore = false;
}

// ฟีดโพสต์ ใช้ได้ 2 แบบ
// - FeedScope.community: หน้าหลัก (ทุกครอบครัวเห็น)
// - FeedScope.family:    แท็บครอบครัว (เฉพาะครอบครัว)
class FeedPage extends StatefulWidget {
  final FeedScope scope;

  const FeedPage({super.key, required this.scope});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  // ความยาวสูงสุดของโพสต์ ตรงกับ Laravel (content max:5000)
  static const int maxPostLength = 5000;

  // จำนวนความคิดเห็นที่แสดงก่อนกด "ดูก่อนหน้า"
  static const int collapsedCommentCount = 2;

  // สีของป้าย/ปุ่มฝั่งชุมชน
  static const Color communityColor = Color(0xFF0B7FA6);

  // สีปุ่มถูกใจ
  static const Color likeColor = Color(0xFFE5486B);

  final TextEditingController postController = TextEditingController();

  final ScrollController scrollController = ScrollController();

  bool isPosting = false;

  // ฟีดนี้เป็นของครอบครัวหรือชุมชน (กำหนดจากหน้าที่เปิด)
  FeedScope get scope => widget.scope;

  final _ScopeFeed feed = _ScopeFeed();

  Map<String, dynamic>? currentUser;

  bool communityTermsAccepted = false;

  // โพสต์ที่กำลังลบ (แสดง Loading บนการ์ด)
  final Set<int> deletingPostIds = {};

  // โพสต์ที่กดดูความคิดเห็นทั้งหมดแล้ว
  final Set<int> expandedPostIds = {};

  // โพสต์ที่กำลังส่งการถูกใจไป Server (กันกดรัว)
  final Set<int> likingPostIds = {};

  @override
  void initState() {
    super.initState();
    scrollController.addListener(onScroll);
    loadPosts();
  }

  String apiScope(FeedScope value) {
    return value == FeedScope.community ? 'community' : 'family';
  }

  // =====================================================
  // โหลดโพสต์
  // loadMore = true → โหลดหน้าถัดไปต่อท้าย (ฟีดชุมชน)
  // =====================================================

  Future<void> loadPosts({bool loadMore = false}) async {
    final state = feed;

    if (loadMore) {
      if (state.isLoading || state.isLoadingMore || !state.hasMore) {
        return;
      }

      setState(() {
        state.isLoadingMore = true;
      });
    }

    final int page = loadMore ? state.page + 1 : 1;

    try {
      final result = await PostService.getPosts(
        scope: apiScope(scope),
        page: page,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        final dynamic rawPosts = result['posts'];

        final List<Map<String, dynamic>> newPosts = rawPosts is List
            ? rawPosts
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];

        setState(() {
          if (loadMore) {
            // กันโพสต์ซ้ำ (มีโพสต์ใหม่เข้ามาระหว่างเลื่อน)
            final existingIds = state.posts.map(postIdOf).toSet();

            state.posts.addAll(
              newPosts.where((post) => !existingIds.contains(postIdOf(post))),
            );
          } else {
            state.posts = newPosts;
          }

          state.page = page;
          state.hasMore = result['has_more'] == true;
          state.loaded = true;
          state.loadError = null;

          applyCurrentUser(result['current_user'] ?? result['user']);
        });
      } else {
        handleLoadError(result['message']?.toString() ?? 'โหลดโพสต์ไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      handleLoadError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          state.isLoading = false;
          state.isLoadingMore = false;
        });
      }
    }
  }

  void applyCurrentUser(dynamic userData) {
    if (userData is! Map) return;

    currentUser = Map<String, dynamic>.from(userData);

    communityTermsAccepted = userData['community_terms_accepted'] == true;
  }

  // ยังไม่มีโพสต์ในจอ → แสดงการ์ด "ลองอีกครั้ง"
  // มีโพสต์อยู่แล้ว → แจ้งด้วย SnackBar
  void handleLoadError(String message) {
    if (feed.posts.isEmpty) {
      setState(() {
        feed.loadError = message;
      });
    } else {
      showMessage(message);
    }
  }

  Future<void> retryLoad() async {
    setState(() {
      feed.isLoading = true;
      feed.loadError = null;
    });

    await loadPosts();
  }

  // เลื่อนใกล้ท้ายฟีดชุมชน → โหลดหน้าถัดไป
  void onScroll() {
    if (scope != FeedScope.community || !scrollController.hasClients) {
      return;
    }

    final position = scrollController.position;

    if (position.pixels >= position.maxScrollExtent - 600) {
      loadPosts(loadMore: true);
    }
  }

  // =====================================================
  // กฎชุมชน: ต้องยอมรับก่อนโพสต์ชุมชนครั้งแรก
  // =====================================================

  Future<bool> ensureCommunityTerms() async {
    final bool accepted = await showCommunityRulesDialog(context);

    if (!accepted || !mounted) return false;

    try {
      final result = await PostService.acceptCommunityTerms();

      if (!mounted) return false;

      if (result['status'] == true) {
        setState(() {
          communityTermsAccepted = true;
        });

        return true;
      }

      showMessage(
        result['message']?.toString() ?? 'บันทึกการยอมรับกฎไม่สำเร็จ',
      );
    } catch (e) {
      if (mounted) {
        showMessage(e.toString());
      }
    }

    return false;
  }

  // =====================================================
  // สร้างโพสต์
  // =====================================================

  Future<void> createPost() async {
    final content = postController.text.trim();

    if (content.isEmpty) {
      showMessage('กรุณาพิมพ์ข้อความก่อนโพสต์');
      return;
    }

    final FeedScope target = scope;

    if (target == FeedScope.community && !communityTermsAccepted) {
      final bool ok = await ensureCommunityTerms();

      if (!ok || !mounted) return;
    }

    setState(() {
      isPosting = true;
    });

    try {
      final result = await PostService.createPost(
        content,
        visibility: apiScope(target),
      );

      if (!mounted) return;

      if (result['status'] == true) {
        postController.clear();

        dismissKeyboard();

        await loadPosts();

        if (!mounted) return;

        showMessage(
          target == FeedScope.community
              ? 'แชร์ในชุมชนแล้ว'
              : 'แชร์ให้ครอบครัวแล้ว',
        );
      } else if (result['code'] == 'terms_required') {
        setState(() {
          communityTermsAccepted = false;
        });

        showMessage(
          result['message']?.toString() ?? 'กรุณายอมรับกฎชุมชนก่อนโพสต์',
        );
      } else {
        showMessage(result['message']?.toString() ?? 'โพสต์ไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isPosting = false;
        });
      }
    }
  }

  // =====================================================
  // ลบโพสต์
  // =====================================================

  Future<void> confirmDeletePost(int postId) async {
    dismissKeyboard();

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
            child: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.danger,
              size: 28,
            ),
          ),
          title: const Text('ลบโพสต์นี้?'),
          content: const Text(
            'โพสต์และความคิดเห็นทั้งหมดจะถูกลบถาวร\n'
            'และไม่สามารถกู้คืนได้',
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
                    child: const Text('ลบโพสต์'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await deletePost(postId);
    }
  }

  Future<void> deletePost(int postId) async {
    setState(() {
      deletingPostIds.add(postId);
    });

    try {
      final result = await PostService.deletePost(postId);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          removePost(postId);
        });

        showMessage(result['message']?.toString() ?? 'ลบโพสต์แล้ว');
      } else {
        showMessage(result['message']?.toString() ?? 'ลบโพสต์ไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          deletingPostIds.remove(postId);
        });
      }
    }
  }

  void removePost(int postId) {
    feed.posts.removeWhere((post) => postIdOf(post) == postId);

    expandedPostIds.remove(postId);
  }

  // =====================================================
  // ถูกใจ / ยกเลิกถูกใจ
  // เปลี่ยนบนจอทันที ถ้า Server ตอบผิดพลาดค่อยคืนค่าเดิม
  // =====================================================

  Future<void> toggleLike(Map<String, dynamic> post, int postId) async {
    if (likingPostIds.contains(postId)) return;

    final bool wasLiked = isLikedByMe(post);

    final int oldCount = likesCountOf(post);

    void restore() {
      post['liked_by_me'] = wasLiked;
      post['likes_count'] = oldCount;
    }

    setState(() {
      likingPostIds.add(postId);

      post['liked_by_me'] = !wasLiked;
      post['likes_count'] = wasLiked
          ? (oldCount > 0 ? oldCount - 1 : 0)
          : oldCount + 1;
    });

    try {
      final result = await PostService.toggleLike(postId);

      if (!mounted) return;

      if (result['status'] == true) {
        // ใช้ตัวเลขจริงจาก Server (มีคนอื่นกดพร้อมกันได้)
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
      if (mounted) {
        setState(() {
          likingPostIds.remove(postId);
        });
      }
    }
  }

  // =====================================================
  // รายงานโพสต์ชุมชน
  // =====================================================

  Future<void> reportPost(int postId) async {
    dismissKeyboard();

    final String? reason = await showReportReasonSheet(context);

    if (reason == null || !mounted) return;

    try {
      final result = await PostService.reportPost(
        postId: postId,
        reason: reason,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        // ซ่อนโพสต์ที่รายงานจากจอของเราทันที
        setState(() {
          removePost(postId);
        });

        showMessage(result['message']?.toString() ?? 'ขอบคุณที่รายงาน');
      } else {
        showMessage(result['message']?.toString() ?? 'รายงานไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    }
  }

  // =====================================================
  // บล็อกผู้ใช้ในชุมชน
  // =====================================================

  Future<void> blockAuthor(int userId, String name) async {
    dismissKeyboard();

    final bool confirmed = await showBlockUserDialog(context, name);

    if (!confirmed || !mounted) return;

    try {
      final result = await PostService.blockUser(userId);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          removeUserFromCommunity(userId);
        });

        showMessage(result['message']?.toString() ?? 'บล็อก $name แล้ว');
      } else {
        showMessage(result['message']?.toString() ?? 'บล็อกไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    }
  }

  // เอาโพสต์และความคิดเห็นของคนที่บล็อกออกจากฟีดชุมชน
  void removeUserFromCommunity(int userId) {
    feed.posts.removeWhere((post) => authorIdOf(post) == userId);

    for (final post in feed.posts) {
      final dynamic comments = post['comments'];

      if (comments is List) {
        post['comments'] = comments
            .where(
              (comment) =>
                  !(comment is Map &&
                      comment['user_id']?.toString() == userId.toString()),
            )
            .toList();
      }
    }
  }

  // =====================================================
  // ความคิดเห็นของคนอื่นในฟีดชุมชน: รายงาน / บล็อก
  // =====================================================

  Future<void> openCommentActions({
    required int commentId,
    required int? authorId,
    required String authorName,
  }) async {
    dismissKeyboard();

    final String? action = await showCommentActionsSheet(
      context,
      authorName: authorName,
    );

    if (!mounted || action == null) return;

    if (action == 'report') {
      await reportComment(commentId);
    } else if (action == 'block' && authorId != null) {
      await blockAuthor(authorId, authorName);
    }
  }

  Future<void> reportComment(int commentId) async {
    final String? reason = await showReportReasonSheet(
      context,
      title: 'รายงานความคิดเห็นนี้',
    );

    if (reason == null || !mounted) return;

    try {
      final result = await PostService.reportComment(
        commentId: commentId,
        reason: reason,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        // ซ่อนความคิดเห็นที่รายงานจากจอของเราทันที
        setState(() {
          removeComment(commentId);
        });

        showMessage(result['message']?.toString() ?? 'ขอบคุณที่รายงาน');
      } else {
        showMessage(result['message']?.toString() ?? 'รายงานไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    }
  }

  void removeComment(int commentId) {
    for (final post in feed.posts) {
      final dynamic comments = post['comments'];

      if (comments is List) {
        post['comments'] = comments
            .where(
              (comment) =>
                  !(comment is Map &&
                      comment['id']?.toString() == commentId.toString()),
            )
            .toList();
      }
    }
  }

  Future<void> openBlockedUsers() async {
    dismissKeyboard();

    bool changed = false;

    await showBlockedUsersSheet(
      context,
      onChanged: () {
        changed = true;
      },
    );

    // เลิกบล็อกแล้ว → โหลดฟีดชุมชนใหม่ให้เห็นโพสต์ของเขาอีกครั้ง
    if (changed && mounted) {
      await loadPosts();
    }
  }

  // =====================================================
  // Comment
  // ใช้ local String แทน Controller
  // เพื่อป้องกัน Dialog lifecycle error เดิม
  // =====================================================

  Future<void> showCommentDialog(int postId) async {
    dismissKeyboard();

    String commentText = '';

    final String? content = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.softPrimary,
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 12),
              Text('แสดงความคิดเห็น'),
            ],
          ),
          content: TextField(
            autofocus: true,
            maxLines: 4,
            minLines: 3,
            maxLength: 2000,
            onChanged: (value) {
              commentText = value;
            },
            decoration: const InputDecoration(
              hintText: 'เขียนความคิดเห็นของคุณ...',
              alignLabelWithHint: true,
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('ยกเลิก'),
            ),
            FilledButton.icon(
              onPressed: () {
                final text = commentText.trim();

                if (text.isEmpty) {
                  return;
                }

                Navigator.of(dialogContext).pop(text);
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('ส่ง'),
            ),
          ],
        );
      },
    );

    if (!mounted || content == null || content.isEmpty) {
      return;
    }

    // รอ Dialog ปิดสนิทก่อนเรียก API
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    try {
      final result = await PostService.createComment(
        postId: postId,
        content: content,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        await loadPosts();

        if (!mounted) return;

        showMessage('แสดงความคิดเห็นแล้ว');
      } else {
        showMessage(
          result['message']?.toString() ?? 'แสดงความคิดเห็นไม่สำเร็จ',
        );
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    }
  }

  // ปิดคีย์บอร์ดของกล่องเขียนโพสต์
  // ใช้ primaryFocus.unfocus() เพื่อไม่ให้ Flutter คืนโฟกัส
  // กลับไปที่ช่องพิมพ์หลังปิด Dialog / Bottom Sheet
  void dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // =====================================================
  // SnackBar
  // =====================================================

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // HELPERS
  // =====================================================

  int? postIdOf(Map<String, dynamic> post) {
    final dynamic id = post['id'];

    return id is num ? id.toInt() : null;
  }

  int? authorIdOf(Map<String, dynamic> post) {
    final dynamic id =
        post['user_id'] ??
        (post['user'] is Map ? (post['user'] as Map)['id'] : null);

    return id is num ? id.toInt() : int.tryParse('$id');
  }

  bool isCommunityPost(Map<String, dynamic> post) {
    return post['visibility'] == 'community';
  }

  int likesCountOf(Map<String, dynamic> post) {
    final dynamic count = post['likes_count'];

    return count is num ? count.toInt() : int.tryParse('$count') ?? 0;
  }

  bool isLikedByMe(Map<String, dynamic> post) {
    final dynamic liked = post['liked_by_me'];

    return liked == true || liked == 1;
  }

  // ใช้ is_mine จาก Laravel ถ้ามี
  // ถ้าไม่มี (Server เวอร์ชันเก่า) เทียบ user_id กับผู้ใช้ปัจจุบัน
  bool isMine(Map<String, dynamic> post) {
    final dynamic mine = post['is_mine'];

    if (mine is bool) {
      return mine;
    }

    final dynamic myId = currentUser?['id'];

    return myId != null && post['user_id']?.toString() == myId.toString();
  }

  String formatDate(dynamic value) {
    if (value == null) {
      return '';
    }

    try {
      final date = DateTime.parse(value.toString()).toLocal();

      final difference = DateTime.now().difference(date);

      if (difference.inMinutes < 1) {
        return 'เมื่อสักครู่';
      }

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} นาทีที่แล้ว';
      }

      if (difference.inHours < 24) {
        return '${difference.inHours} ชั่วโมงที่แล้ว';
      }

      if (difference.inDays < 7) {
        return '${difference.inDays} วันที่แล้ว';
      }

      final day = date.day.toString().padLeft(2, '0');

      final month = date.month.toString().padLeft(2, '0');

      return '$day/$month/${date.year}';
    } catch (_) {
      return '';
    }
  }

  // ตัวอักษรบน Avatar
  // ชื่อไทยที่ขึ้นต้นด้วยสระหน้า (เ แ โ ใ ไ) ใช้พยัญชนะตัวถัดไป
  // และไม่เอาวรรณยุกต์ เช่น "แม่" → "ม", "พ่อ" → "พ"
  String getInitial(dynamic name) {
    final text = name?.toString().trim() ?? '';

    if (text.isEmpty) {
      return '?';
    }

    final runes = text.runes.toList();

    const leadingVowels = 'เแโใไ';

    final int index =
        runes.length > 1 &&
            leadingVowels.contains(String.fromCharCode(runes.first))
        ? 1
        : 0;

    return String.fromCharCode(runes[index]).toUpperCase();
  }

  // รองรับชื่อ key หลายแบบจาก API
  String? getProfileImage(dynamic user) {
    if (user is! Map) {
      return null;
    }

    const possibleKeys = [
      'profile_image_url',
      'profile_photo_url',
      'profile_image',
      'avatar_url',
      'avatar',
      'photo_url',
      'photo',
      'image_url',
      'image',
    ];

    for (final key in possibleKeys) {
      final value = user[key]?.toString().trim();

      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return null;
  }

  BoxDecoration cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // =====================================================
  // Avatar
  // =====================================================

  Widget buildAvatar({
    required String name,
    String? imageUrl,
    double radius = 22,
  }) {
    final double size = radius * 2;

    Widget fallbackAvatar() {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, Color(0xFF7B80FF)],
          ),
          shape: BoxShape.circle,
        ),
        child: Text(
          getInitial(name),
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.72,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final bool hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: hasImage
            ? Image.network(
                imageUrl.trim(),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return fallbackAvatar();
                },
              )
            : fallbackAvatar(),
      ),
    );
  }

  // =====================================================
  // Hero Header
  // =====================================================

  Widget buildHeroHeader() {
    final bool community = scope == FeedScope.community;

    // หน้าชุมชนใช้โทนฟ้า-เขียว แยกจากหน้าครอบครัว
    final List<Color> colors = community
        ? const [Color(0xFF0B2E4A), Color(0xFF0B7FA6), Color(0xFF35B9DC)]
        : const [Color(0xFF182458), Color(0xFF4650D8), Color(0xFF646BFF)];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: colors[1].withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Orbit ใหญ่
          Positioned(
            right: -40,
            top: -60,
            child: Container(
              width: 155,
              height: 155,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.5,
                ),
              ),
            ),
          ),

          // Orbit เล็ก
          Positioned(
            right: 10,
            bottom: -58,
            child: Container(
              width: 105,
              height: 105,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.sky.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),

          Positioned(
            right: 32,
            top: 22,
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AppColors.sky,
                shape: BoxShape.circle,
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      community
                          ? Icons.public_rounded
                          : Icons.auto_awesome_rounded,
                      color: AppColors.warm,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      community ? 'COMMUNITY' : 'FAMILY ORBIT',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                community
                    ? 'เรื่องราวจาก\nทุกครอบครัว'
                    : 'วันนี้ครอบครัว\nเป็นอย่างไรกันบ้าง?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                community
                    ? 'แชร์ ถาม-ตอบ และช่วยเหลือกันในชุมชน'
                    : 'แชร์เรื่องเล็ก ๆ ให้คนสำคัญของคุณรับรู้',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================
  // กล่องสร้างโพสต์
  // =====================================================

  Widget buildCreatePost() {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildAvatar(
                name: currentUser?['name']?.toString() ?? 'F',
                imageUrl: getProfileImage(currentUser),
                radius: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: postController,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: maxPostLength,
                  textCapitalization: TextCapitalization.sentences,

                  // แสดงตัวนับเมื่อใกล้ถึงขีดจำกัด
                  buildCounter:
                      (
                        context, {
                        required currentLength,
                        required isFocused,
                        required maxLength,
                      }) {
                        if (currentLength < maxPostLength - 500) {
                          return null;
                        }

                        return Text(
                          '$currentLength/$maxPostLength',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        );
                      },

                  decoration: InputDecoration(
                    hintText: scope == FeedScope.community
                        ? 'แชร์เรื่องราวให้ทุกครอบครัวในชุมชน...'
                        : 'มีอะไรอยากเล่าให้ครอบครัวฟังไหม?',
                    filled: true,
                    fillColor: const Color(0xFFF7F8FC),
                    contentPadding: const EdgeInsets.all(16),
                    border: inputBorder,
                    enabledBorder: inputBorder,
                    focusedBorder: inputBorder.copyWith(
                      borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              buildAudienceChip(),
              const Spacer(),

              // ปุ่มแชร์กดได้เมื่อมีข้อความเท่านั้น
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: postController,
                builder: (context, value, child) {
                  final bool canPost =
                      value.text.trim().isNotEmpty && !isPosting;

                  return FilledButton.icon(
                    onPressed: canPost ? createPost : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.primary.withValues(
                        alpha: 0.30,
                      ),
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: isPosting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 17),
                    label: Text(isPosting ? 'กำลังส่ง' : 'แชร์'),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // บอกว่าโพสต์นี้ใครจะเห็น (ตามหน้าที่เปิดอยู่)
  Widget buildAudienceChip() {
    if (scope == FeedScope.community) {
      return buildChip(
        icon: Icons.public_rounded,
        label: 'ชุมชน · ทุกคนเห็น',
        color: communityColor,
      );
    }

    return buildChip(icon: Icons.lock_outline_rounded, label: 'เฉพาะครอบครัว');
  }

  Widget buildChip({
    required IconData icon,
    required String label,
    Color color = AppColors.primary,
    IconData? trailingIcon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 2),
            Icon(trailingIcon, size: 16, color: color),
          ],
        ],
      ),
    );
  }

  // =====================================================
  // หัวข้อรายการโพสต์
  // =====================================================

  Widget buildSectionHeader() {
    if (scope == FeedScope.community) {
      return Row(
        children: [
          const Text(
            'ล่าสุดในชุมชน',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.muted,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: openBlockedUsers,
            icon: const Icon(Icons.block_rounded, size: 16),
            label: const Text('ผู้ใช้ที่บล็อก'),
          ),
        ],
      );
    }

    return Row(
      children: [
        const Text(
          'ล่าสุดในครอบครัว',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        if (!feed.isLoading && feed.posts.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${feed.posts.length} โพสต์',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  // =====================================================
  // Post Card
  // =====================================================

  Widget buildPostCard(Map<String, dynamic> post) {
    final dynamic user = post['user'];

    final String name = user is Map
        ? (user['name']?.toString() ?? 'สมาชิก')
        : 'สมาชิก';

    final List<dynamic> comments = (post['comments'] as List?) ?? [];

    final int? postId = postIdOf(post);

    final bool mine = isMine(post);

    final bool community = isCommunityPost(post);

    final bool deleting = postId != null && deletingPostIds.contains(postId);

    return AnimatedOpacity(
      key: ValueKey('post-$postId'),
      duration: const Duration(milliseconds: 200),
      opacity: deleting ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: deleting,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===========================================
              // Header
              // ===========================================

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
                child: Row(
                  children: [
                    buildAvatar(
                      name: name,
                      imageUrl: getProfileImage(user),
                      radius: 21,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.navy,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (mine) ...[
                                const SizedBox(width: 6),
                                buildYouBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                community
                                    ? Icons.public_rounded
                                    : Icons.family_restroom_rounded,
                                size: 13,
                                color: AppColors.muted,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${community ? 'ชุมชน' : 'ครอบครัว'} · '
                                  '${formatDate(post['created_at'])}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (deleting)
                      const Padding(
                        padding: EdgeInsets.all(15),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (postId != null && (mine || community))
                      buildPostMenu(post, postId, mine)
                    else
                      const SizedBox(width: 12, height: 48),
                  ],
                ),
              ),

              // ===========================================
              // Content
              // ===========================================
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Text(
                  post['content']?.toString() ?? '',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 15.5,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              // ===========================================
              // Action Bar
              // ===========================================
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                child: Row(
                  children: [
                    if (postId != null) ...[
                      buildLikeButton(post, postId),
                      const SizedBox(width: 10),
                    ],

                    // จำนวนความคิดเห็น (ย่อได้บนจอแคบ)
                    Expanded(
                      child: comments.isEmpty
                          ? const SizedBox.shrink()
                          : Row(
                              children: [
                                const Icon(
                                  Icons.chat_bubble_rounded,
                                  size: 14,
                                  color: AppColors.muted,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '${comments.length} ความคิดเห็น',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    if (postId != null)
                      Material(
                        color: AppColors.softPrimary,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () {
                            showCommentDialog(postId);
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: AppColors.primary,
                                  size: 17,
                                ),
                                SizedBox(width: 7),
                                Text(
                                  'แสดงความคิดเห็น',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ===========================================
              // Comments
              // ===========================================
              if (comments.isNotEmpty)
                buildCommentsSection(postId: postId, comments: comments),
            ],
          ),
        ),
      ),
    );
  }

  // ปุ่ม ❤️ + จำนวนถูกใจ
  Widget buildLikeButton(Map<String, dynamic> post, int postId) {
    final bool liked = isLikedByMe(post);

    final int count = likesCountOf(post);

    final Color color = liked ? likeColor : AppColors.muted;

    return Semantics(
      button: true,
      toggled: liked,
      label: liked ? 'ยกเลิกถูกใจ' : 'ถูกใจ',
      child: Material(
        color: liked
            ? likeColor.withValues(alpha: 0.10)
            : const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            toggleLike(post, postId);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // หัวใจเด้งเล็กน้อยตอนกด
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    key: ValueKey(liked),
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  count > 0 ? '$count' : 'ถูกใจ',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildYouBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.sky.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'คุณ',
        style: TextStyle(
          color: Color(0xFF0B7FA6),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // เมนู ⋯
  // - โพสต์ของเรา: ลบโพสต์
  // - โพสต์ชุมชนของคนอื่น: รายงาน / บล็อก
  Widget buildPostMenu(Map<String, dynamic> post, int postId, bool mine) {
    final int? authorId = authorIdOf(post);

    final dynamic user = post['user'];

    final String authorName = user is Map
        ? (user['name']?.toString() ?? 'สมาชิก')
        : 'สมาชิก';

    return PopupMenuButton<String>(
      tooltip: 'ตัวเลือกโพสต์',
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.more_horiz_rounded, color: AppColors.muted),
      onSelected: (value) {
        switch (value) {
          case 'delete':
            confirmDeletePost(postId);
          case 'report':
            reportPost(postId);
          case 'block':
            if (authorId != null) {
              blockAuthor(authorId, authorName);
            }
        }
      },
      itemBuilder: (context) {
        return [
          if (mine)
            buildMenuItem(
              value: 'delete',
              icon: Icons.delete_outline_rounded,
              label: 'ลบโพสต์',
              color: AppColors.danger,
            ),
          if (!mine)
            buildMenuItem(
              value: 'report',
              icon: Icons.flag_outlined,
              label: 'รายงานโพสต์',
              color: AppColors.navy,
            ),
          if (!mine && authorId != null)
            buildMenuItem(
              value: 'block',
              icon: Icons.block_rounded,
              label: 'บล็อก $authorName',
              color: AppColors.danger,
            ),
        ];
      },
    );
  }

  PopupMenuItem<String> buildMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // Comments Section
  // แสดงล่าสุด 2 รายการ กด "ดูก่อนหน้า" เพื่อดูทั้งหมด
  // =====================================================

  Widget buildCommentsSection({
    required int? postId,
    required List<dynamic> comments,
  }) {
    final bool expanded = postId != null && expandedPostIds.contains(postId);

    final List<dynamic> visibleComments =
        expanded || comments.length <= collapsedCommentCount
        ? comments
        : comments.sublist(comments.length - collapsedCommentCount);

    final int hiddenCount = comments.length - visibleComments.length;

    final bool canCollapse =
        expanded && comments.length > collapsedCommentCount;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FD),
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (postId != null && (hiddenCount > 0 || canCollapse))
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 36),
                foregroundColor: AppColors.muted,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () {
                setState(() {
                  if (expanded) {
                    expandedPostIds.remove(postId);
                  } else {
                    expandedPostIds.add(postId);
                  }
                });
              },
              child: Text(
                hiddenCount > 0
                    ? 'ดูความคิดเห็นก่อนหน้า ($hiddenCount)'
                    : 'ซ่อนความคิดเห็นเก่า',
              ),
            ),
          ...visibleComments.map(buildComment),
        ],
      ),
    );
  }

  Widget buildComment(dynamic comment) {
    final dynamic commentUser = comment is Map ? comment['user'] : null;

    final String commentName = commentUser is Map
        ? (commentUser['name']?.toString() ?? 'สมาชิก')
        : 'สมาชิก';

    final dynamic createdAt = comment is Map ? comment['created_at'] : null;

    final String content = comment is Map
        ? (comment['content']?.toString() ?? '')
        : '';

    final dynamic rawId = comment is Map ? comment['id'] : null;

    final int? commentId = rawId is num ? rawId.toInt() : null;

    final dynamic rawAuthorId = comment is Map ? comment['user_id'] : null;

    final int? authorId = rawAuthorId is num ? rawAuthorId.toInt() : null;

    final dynamic myId = currentUser?['id'];

    final bool mine =
        myId != null && authorId != null && myId.toString() == '$authorId';

    // ความคิดเห็นของคนอื่นในฟีดชุมชน → รายงาน / บล็อกได้
    final bool canAct =
        scope == FeedScope.community && commentId != null && !mine;

    void openActions() {
      if (commentId == null) return;

      openCommentActions(
        commentId: commentId,
        authorId: authorId,
        authorName: commentName,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: canAct ? openActions : null,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildAvatar(
              name: commentName,
              imageUrl: getProfileImage(commentUser),
              radius: 15,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // ชื่อ + เวลา ใช้พื้นที่ที่เหลือ → ปุ่ม ⋯ ชิดขวา
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  commentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.navy,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (createdAt != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  formatDate(createdAt),
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (canAct) ...[
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: openActions,
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: 18,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      content,
                      style: const TextStyle(
                        color: Color(0xFF344054),
                        fontSize: 14,
                        height: 1.4,
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

  // =====================================================
  // Empty / Error State
  // =====================================================

  Widget buildEmptyState() {
    if (scope == FeedScope.community) {
      return buildStateCard(
        icon: Icons.public_rounded,
        color: communityColor,
        title: 'ชุมชนยังเงียบอยู่',
        message: 'เป็นคนแรกที่แชร์เรื่องราวให้ทุกครอบครัวเห็น',
      );
    }

    return buildStateCard(
      icon: Icons.forum_outlined,
      color: AppColors.primary,
      title: 'วงโคจรยังเงียบอยู่',
      message: 'เริ่มต้นแชร์เรื่องราวแรกของครอบครัวกันเลย',
    );
  }

  Widget buildErrorState() {
    return buildStateCard(
      icon: Icons.cloud_off_rounded,
      color: AppColors.danger,
      title: 'โหลดโพสต์ไม่สำเร็จ',
      message: feed.loadError ?? 'กรุณาลองใหม่อีกครั้ง',
      action: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(170, 46)),
        onPressed: retryLoad,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('ลองอีกครั้ง'),
      ),
    );
  }

  Widget buildStateCard({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: color),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action],
        ],
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  List<Widget> buildFeedItems() {
    if (feed.isLoading) {
      return const [_PostSkeleton(), _PostSkeleton()];
    }

    if (feed.loadError != null && feed.posts.isEmpty) {
      return [buildErrorState()];
    }

    if (feed.posts.isEmpty) {
      return [buildEmptyState()];
    }

    return [
      ...feed.posts.map(buildPostCard),
      if (scope == FeedScope.community) buildFeedFooter(),
    ];
  }

  // ท้ายฟีดชุมชน: กำลังโหลดเพิ่ม / ไม่มีโพสต์เพิ่มแล้ว
  Widget buildFeedFooter() {
    if (feed.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (feed.hasMore) {
      return const SizedBox(height: 40);
    }

    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          'ไม่มีโพสต์เพิ่มแล้ว',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => loadPosts(),
      child: ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 35),
        children: [
          buildHeroHeader(),
          const SizedBox(height: 16),
          buildCreatePost(),
          const SizedBox(height: 24),
          buildSectionHeader(),
          const SizedBox(height: 12),
          ...buildFeedItems(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    postController.dispose();

    scrollController.dispose();

    super.dispose();
  }
}

// =======================================================
// Skeleton ระหว่างโหลดโพสต์
// =======================================================

class _PostSkeleton extends StatefulWidget {
  const _PostSkeleton();

  @override
  State<_PostSkeleton> createState() => _PostSkeletonState();
}

class _PostSkeletonState extends State<_PostSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> opacity = Tween<double>(
    begin: 0.45,
    end: 1,
  ).animate(controller);

  Widget bar(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEFF5),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEDEFF5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(110, 12),
                    const SizedBox(height: 7),
                    bar(70, 10),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            bar(double.infinity, 12),
            const SizedBox(height: 9),
            bar(double.infinity, 12),
            const SizedBox(height: 9),
            bar(170, 12),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();

    super.dispose();
  }
}
