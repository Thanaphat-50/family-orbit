import 'package:flutter/material.dart';

import '../pages/user_profile_page.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import 'comment_media.dart';
import 'community_sheets.dart';
import 'hashtag_text.dart';
import 'user_avatar.dart';

// เปิดแผ่นความคิดเห็นของโพสต์ (ฟีด / โพสต์เดียว / หน้าวิดีโอ ใช้แบบเดียวกัน)
// แผ่นแก้ post['comments'] ตรง ๆ แล้วเรียก onChanged ให้หน้าที่เปิดวาดใหม่
Future<void> showCommentsSheet(
  BuildContext context, {
  required Map<String, dynamic> post,
  required int? myId,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => CommentsSheet(post: post, myId: myId, onChanged: onChanged),
  );
}

// =======================================================
// แผ่นความคิดเห็น (เลื่อนขึ้นจากด้านล่าง)
// - เขียนความคิดเห็นได้ทันที (#แฮชแท็กกดได้)
// - แนบรูป / GIF / วิดีโอได้ 1 ไฟล์ แสดงย่อ แตะเพื่อดูเต็มจอ
// - แตะชื่อ/รูป = เปิดโปรไฟล์, กดค้างความคิดเห็นของคนอื่น = รายงาน
// =======================================================

class CommentsSheet extends StatefulWidget {
  final Map<String, dynamic> post;

  final int? myId;

  // จำนวนความคิดเห็นเปลี่ยน → หน้าวิดีโอวาดตัวเลขใหม่
  final VoidCallback onChanged;

  const CommentsSheet({
    super.key,
    required this.post,
    required this.myId,
    required this.onChanged,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
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
                          hintText: 'เขียนความคิดเห็น...',
                          hintMaxLines: 1,
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
