import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme/app_theme.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({
    super.key,
  });

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  // ความยาวสูงสุดของโพสต์ ตรงกับ Laravel (content max:5000)
  static const int maxPostLength = 5000;

  // จำนวนความคิดเห็นที่แสดงก่อนกด "ดูก่อนหน้า"
  static const int collapsedCommentCount = 2;

  final TextEditingController postController = TextEditingController();

  bool isLoading = true;
  bool isPosting = false;

  // ข้อความ Error เมื่อโหลดครั้งแรกไม่สำเร็จ
  String? loadError;

  List<Map<String, dynamic>> posts = [];

  Map<String, dynamic>? currentUser;

  // โพสต์ที่กำลังลบ (แสดง Loading บนการ์ด)
  final Set<int> deletingPostIds = {};

  // โพสต์ที่กดดูความคิดเห็นทั้งหมดแล้ว
  final Set<int> expandedPostIds = {};

  @override
  void initState() {
    super.initState();
    loadPosts();
  }

  // =====================================================
  // โหลดโพสต์
  // =====================================================

  Future<void> loadPosts() async {
    try {
      final result = await PostService.getPosts();

      if (!mounted) return;

      if (result['status'] == true) {
        final dynamic rawPosts = result['posts'];

        final dynamic userData = result['current_user'] ?? result['user'];

        setState(() {
          posts = rawPosts is List
              ? rawPosts
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
              : [];

          if (userData is Map) {
            currentUser = Map<String, dynamic>.from(userData);
          }

          loadError = null;
        });
      } else {
        handleLoadError(
          result['message']?.toString() ?? 'โหลดโพสต์ไม่สำเร็จ',
        );
      }
    } catch (e) {
      if (!mounted) return;

      handleLoadError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ยังไม่มีโพสต์ในจอ → แสดงการ์ด "ลองอีกครั้ง"
  // มีโพสต์อยู่แล้ว → แจ้งด้วย SnackBar
  void handleLoadError(String message) {
    if (posts.isEmpty) {
      setState(() {
        loadError = message;
      });
    } else {
      showMessage(message);
    }
  }

  Future<void> retryLoad() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    await loadPosts();
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

    setState(() {
      isPosting = true;
    });

    try {
      final result = await PostService.createPost(content);

      if (!mounted) return;

      if (result['status'] == true) {
        postController.clear();

        FocusScope.of(context).unfocus();

        await loadPosts();

        if (!mounted) return;

        showMessage('แชร์ให้ครอบครัวแล้ว');
      } else {
        showMessage(
          result['message']?.toString() ?? 'โพสต์ไม่สำเร็จ',
        );
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
          posts.removeWhere((post) => postIdOf(post) == postId);
          expandedPostIds.remove(postId);
        });

        showMessage(
          result['message']?.toString() ?? 'ลบโพสต์แล้ว',
        );
      } else {
        showMessage(
          result['message']?.toString() ?? 'ลบโพสต์ไม่สำเร็จ',
        );
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

  // =====================================================
  // Comment
  // ใช้ local String แทน Controller
  // เพื่อป้องกัน Dialog lifecycle error เดิม
  // =====================================================

  Future<void> showCommentDialog(int postId) async {
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
              icon: const Icon(
                Icons.send_rounded,
                size: 18,
              ),
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
    await Future<void>.delayed(
      const Duration(milliseconds: 300),
    );

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

  // =====================================================
  // SnackBar
  // =====================================================

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  // =====================================================
  // HELPERS
  // =====================================================

  int? postIdOf(Map<String, dynamic> post) {
    final dynamic id = post['id'];

    return id is num ? id.toInt() : null;
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
            colors: [
              AppColors.primary,
              Color(0xFF7B80FF),
            ],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF182458),
            Color(0xFF4650D8),
            Color(0xFF646BFF),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.warm,
                      size: 15,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'FAMILY ORBIT',
                      style: TextStyle(
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
              const Text(
                'วันนี้ครอบครัว\nเป็นอย่างไรกันบ้าง?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'แชร์เรื่องเล็ก ๆ ให้คนสำคัญของคุณรับรู้',
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
                  buildCounter: (
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
                    hintText: 'มีอะไรอยากเล่าให้ครอบครัวฟังไหม?',
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
              buildChip(
                icon: Icons.lock_outline_rounded,
                label: 'เฉพาะครอบครัว',
              ),
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
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.30),
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
                        : const Icon(
                            Icons.send_rounded,
                            size: 17,
                          ),
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

  Widget buildChip({
    required IconData icon,
    required String label,
    Color color = AppColors.primary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
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
        ],
      ),
    );
  }

  // =====================================================
  // หัวข้อรายการโพสต์
  // =====================================================

  Widget buildSectionHeader() {
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
        if (!isLoading && posts.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${posts.length} โพสต์',
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

    final String name =
        user is Map ? (user['name']?.toString() ?? 'สมาชิก') : 'สมาชิก';

    final List<dynamic> comments = (post['comments'] as List?) ?? [];

    final int? postId = postIdOf(post);

    final bool mine = isMine(post);

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
                              const Icon(
                                Icons.family_restroom_rounded,
                                size: 13,
                                color: AppColors.muted,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'ครอบครัว · ${formatDate(post['created_at'])}',
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    else if (mine && postId != null)
                      buildPostMenu(postId)
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
                    if (comments.isNotEmpty) ...[
                      const Icon(
                        Icons.chat_bubble_rounded,
                        size: 14,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${comments.length} ความคิดเห็น',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
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
                buildCommentsSection(
                  postId: postId,
                  comments: comments,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildYouBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 2,
      ),
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

  // เมนู ⋯ บนโพสต์ของตัวเอง
  Widget buildPostMenu(int postId) {
    return PopupMenuButton<String>(
      tooltip: 'ตัวเลือกโพสต์',
      position: PopupMenuPosition.under,
      icon: const Icon(
        Icons.more_horiz_rounded,
        color: AppColors.muted,
      ),
      onSelected: (value) {
        if (value == 'delete') {
          confirmDeletePost(postId);
        }
      },
      itemBuilder: (context) {
        return const [
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                  size: 20,
                ),
                SizedBox(width: 10),
                Text(
                  'ลบโพสต์',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ];
      },
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
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
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

    final String content =
        comment is Map ? (comment['content']?.toString() ?? '') : '';

    return Padding(
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
    );
  }

  // =====================================================
  // Empty / Error State
  // =====================================================

  Widget buildEmptyState() {
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
      message: loadError ?? 'กรุณาลองใหม่อีกครั้ง',
      action: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(170, 46),
        ),
        onPressed: retryLoad,
        icon: const Icon(
          Icons.refresh_rounded,
          size: 18,
        ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 40,
      ),
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
            child: Icon(
              icon,
              size: 34,
              color: color,
            ),
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
          if (action != null) ...[
            const SizedBox(height: 18),
            action,
          ],
        ],
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  List<Widget> buildFeedItems() {
    if (isLoading) {
      return const [
        _PostSkeleton(),
        _PostSkeleton(),
      ];
    }

    if (loadError != null && posts.isEmpty) {
      return [buildErrorState()];
    }

    if (posts.isEmpty) {
      return [buildEmptyState()];
    }

    return posts.map(buildPostCard).toList();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: loadPosts,
      child: ListView(
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
