import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme/app_theme.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({
    super.key,
  });

  @override
  State<FeedPage> createState() =>
      _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final TextEditingController postController =
      TextEditingController();

  bool isLoading = true;
  bool isPosting = false;

  List<dynamic> posts = [];

  Map<String, dynamic>? currentUser;

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
      final result =
          await PostService.getPosts();

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          posts =
              result['posts'] ?? [];

          final dynamic userData =
              result['current_user'] ??
              result['user'];

          if (userData is Map) {
            currentUser =
                Map<String, dynamic>.from(
              userData,
            );
          }
        });
      } else {
        showMessage(
          result['message'] ??
              'โหลดโพสต์ไม่สำเร็จ',
        );
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(
        'โหลดโพสต์ไม่สำเร็จ: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // =====================================================
  // สร้างโพสต์
  // =====================================================

  Future<void> createPost() async {
    final content =
        postController.text.trim();

    if (content.isEmpty) {
      showMessage(
        'กรุณาพิมพ์ข้อความก่อนโพสต์',
      );
      return;
    }

    setState(() {
      isPosting = true;
    });

    try {
      final result =
          await PostService.createPost(
        content,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        postController.clear();

        FocusScope.of(context).unfocus();

        await loadPosts();

        if (!mounted) return;

        showMessage(
          'แชร์ให้ครอบครัวแล้ว',
        );
      } else {
        showMessage(
          result['message'] ??
              'โพสต์ไม่สำเร็จ',
        );
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(
        'เกิดข้อผิดพลาด: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          isPosting = false;
        });
      }
    }
  }

  // =====================================================
  // Comment
  // ใช้ local String แทน Controller
  // เพื่อป้องกัน Dialog lifecycle error เดิม
  // =====================================================

  Future<void> showCommentDialog(
    int postId,
  ) async {
    String commentText = '';

    final String? content =
        await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              Colors.white,
          surfaceTintColor:
              Colors.transparent,

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              26,
            ),
          ),

          titlePadding:
              const EdgeInsets.fromLTRB(
            24,
            24,
            24,
            0,
          ),

          contentPadding:
              const EdgeInsets.fromLTRB(
            24,
            18,
            24,
            10,
          ),

          actionsPadding:
              const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16,
          ),

          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    Color(0xFFEDEDFF),
                child: Icon(
                  Icons
                      .chat_bubble_outline_rounded,
                  color:
                      AppColors.primary,
                ),
              ),
              SizedBox(
                width: 12,
              ),
              Text(
                'แสดงความคิดเห็น',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight:
                      FontWeight.w800,
                  color:
                      AppColors.navy,
                ),
              ),
            ],
          ),

          content: TextField(
            autofocus: true,
            maxLines: 4,
            minLines: 3,

            onChanged: (value) {
              commentText = value;
            },

            decoration:
                const InputDecoration(
              hintText:
                  'เขียนความคิดเห็นของคุณ...',
              alignLabelWithHint: true,
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: const Text(
                'ยกเลิก',
              ),
            ),

            FilledButton.icon(
              onPressed: () {
                final text =
                    commentText.trim();

                if (text.isEmpty) {
                  return;
                }

                Navigator.of(
                  dialogContext,
                ).pop(text);
              },
              icon: const Icon(
                Icons.send_rounded,
                size: 18,
              ),
              label: const Text(
                'ส่ง',
              ),
            ),
          ],
        );
      },
    );

    if (!mounted ||
        content == null ||
        content.isEmpty) {
      return;
    }

    // รอ Dialog ปิดสนิทก่อนเรียก API
    await Future<void>.delayed(
      const Duration(
        milliseconds: 300,
      ),
    );

    if (!mounted) return;

    try {
      final result =
          await PostService.createComment(
        postId: postId,
        content: content,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        await loadPosts();

        if (!mounted) return;

        showMessage(
          'แสดงความคิดเห็นแล้ว',
        );
      } else {
        showMessage(
          result['message'] ??
              'แสดงความคิดเห็นไม่สำเร็จ',
        );
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(
        'เกิดข้อผิดพลาด: $e',
      );
    }
  }

  // =====================================================
  // SnackBar
  // =====================================================

  void showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // =====================================================
  // แปลงเวลา
  // =====================================================

  String formatDate(
    dynamic value,
  ) {
    if (value == null) {
      return '';
    }

    try {
      final date = DateTime.parse(
        value.toString(),
      ).toLocal();

      final now = DateTime.now();

      final difference =
          now.difference(date);

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

      final day =
          date.day.toString().padLeft(
                2,
                '0',
              );

      final month =
          date.month.toString().padLeft(
                2,
                '0',
              );

      return '$day/$month/${date.year}';
    } catch (_) {
      return '';
    }
  }

  // =====================================================
  // ตัวอักษร Avatar
  // =====================================================

  String getInitial(
    dynamic name,
  ) {
    final text =
        name?.toString().trim() ?? '';

    if (text.isEmpty) {
      return '?';
    }

    return text.characters.first
        .toUpperCase();
  }

  // =====================================================
  // ดึง URL รูปโปรไฟล์
  // รองรับชื่อ key หลายแบบจาก API
  // =====================================================

  String? getProfileImage(
    dynamic user,
  ) {
    if (user is! Map) {
      return null;
    }

    const possibleKeys = [
      'profile_image_url',
      'profile_image',
      'avatar_url',
      'avatar',
      'photo_url',
      'photo',
      'image_url',
      'image',
    ];

    for (final key in possibleKeys) {
      final value =
          user[key]?.toString().trim();

      if (value != null &&
          value.isNotEmpty &&
          value.toLowerCase() !=
              'null') {
        return value;
      }
    }

    return null;
  }

  // =====================================================
  // Avatar
  // =====================================================

  Widget buildAvatar({
    required String name,
    String? imageUrl,
    double radius = 22,
  }) {
    final double size =
        radius * 2;

    Widget fallbackAvatar() {
      return Container(
        width: size,
        height: size,

        decoration:
            BoxDecoration(
          gradient:
              const LinearGradient(
            begin:
                Alignment.topLeft,
            end:
                Alignment.bottomRight,
            colors: [
              AppColors.primary,
              Color(0xFF7B80FF),
            ],
          ),

          shape:
              BoxShape.circle,

          boxShadow: [
            BoxShadow(
              color:
                  AppColors.primary
                      .withValues(
                alpha: 0.16,
              ),
              blurRadius: 12,
              offset:
                  const Offset(
                0,
                5,
              ),
            ),
          ],
        ),

        alignment:
            Alignment.center,

        child: Text(
          getInitial(name),
          style: TextStyle(
            color: Colors.white,
            fontSize:
                radius * 0.72,
            fontWeight:
                FontWeight.w800,
          ),
        ),
      );
    }

    final bool hasImage =
        imageUrl != null &&
        imageUrl.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,

      decoration:
          BoxDecoration(
        shape:
            BoxShape.circle,

        boxShadow: [
          BoxShadow(
            color:
                AppColors.navy
                    .withValues(
              alpha: 0.10,
            ),
            blurRadius: 10,
            offset:
                const Offset(
              0,
              4,
            ),
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

                errorBuilder:
                    (
                  context,
                  error,
                  stackTrace,
                ) {
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
      padding:
          const EdgeInsets.all(22),

      decoration:
          BoxDecoration(
        gradient:
            const LinearGradient(
          begin:
              Alignment.topLeft,
          end:
              Alignment.bottomRight,
          colors: [
            Color(0xFF182458),
            Color(0xFF4650D8),
            Color(0xFF646BFF),
          ],
        ),

        borderRadius:
            BorderRadius.circular(
          28,
        ),

        boxShadow: [
          BoxShadow(
            color:
                AppColors.primary
                    .withValues(
              alpha: 0.18,
            ),
            blurRadius: 28,
            offset:
                const Offset(
              0,
              12,
            ),
          ),
        ],
      ),

      child: Stack(
        children: [
          // Orbit ใหญ่
          Positioned(
            right: -35,
            top: -55,
            child: Container(
              width: 155,
              height: 155,
              decoration:
                  BoxDecoration(
                shape:
                    BoxShape.circle,
                border:
                    Border.all(
                  color:
                      Colors.white
                          .withValues(
                    alpha: 0.12,
                  ),
                  width: 1.5,
                ),
              ),
            ),
          ),

          // Orbit เล็ก
          Positioned(
            right: 12,
            bottom: -50,
            child: Container(
              width: 105,
              height: 105,
              decoration:
                  BoxDecoration(
                shape:
                    BoxShape.circle,
                border:
                    Border.all(
                  color:
                      AppColors.sky
                          .withValues(
                    alpha: 0.25,
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            right: 35,
            top: 25,
            child: Container(
              width: 9,
              height: 9,
              decoration:
                  const BoxDecoration(
                color:
                    AppColors.sky,
                shape:
                    BoxShape.circle,
              ),
            ),
          ),

          Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),

                decoration:
                    BoxDecoration(
                  color: Colors.white
                      .withValues(
                    alpha: 0.13,
                  ),

                  borderRadius:
                      BorderRadius.circular(
                    999,
                  ),
                ),

                child:
                    const Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      Icons
                          .auto_awesome_rounded,
                      color:
                          AppColors.warm,
                      size: 16,
                    ),
                    SizedBox(
                      width: 6,
                    ),
                    Text(
                      'FAMILY ORBIT',
                      style:
                          TextStyle(
                        color:
                            Colors.white,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w800,
                        letterSpacing:
                            1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 18,
              ),

              const Text(
                'วันนี้ครอบครัว\nเป็นอย่างไรกันบ้าง?',
                style:
                    TextStyle(
                  color:
                      Colors.white,
                  fontSize: 26,
                  height: 1.2,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              const SizedBox(
                height: 9,
              ),

              Text(
                'แชร์เรื่องเล็ก ๆ ให้คนสำคัญของคุณรับรู้',
                style:
                    TextStyle(
                  color:
                      Colors.white
                          .withValues(
                    alpha: 0.78,
                  ),
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
    return Container(
      padding:
          const EdgeInsets.all(18),

      decoration:
          BoxDecoration(
        color:
            Colors.white,

        borderRadius:
            BorderRadius.circular(
          24,
        ),

        border:
            Border.all(
          color:
              AppColors.border,
        ),

        boxShadow: [
          BoxShadow(
            color:
                AppColors.navy
                    .withValues(
              alpha: 0.035,
            ),
            blurRadius: 22,
            offset:
                const Offset(
              0,
              8,
            ),
          ),
        ],
      ),

      child: Column(
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              buildAvatar(
                name:
                    currentUser?['name']
                            ?.toString() ??
                        'F',
                imageUrl:
                    getProfileImage(
                  currentUser,
                ),
                radius: 21,
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                child: TextField(
                  controller:
                      postController,

                  minLines: 2,
                  maxLines: 5,

                  textCapitalization:
                      TextCapitalization
                          .sentences,

                  decoration:
                      InputDecoration(
                    hintText:
                        'มีอะไรอยากเล่าให้ครอบครัวฟังไหม?',

                    filled: true,

                    fillColor:
                        const Color(
                      0xFFF7F8FC,
                    ),

                    contentPadding:
                        const EdgeInsets
                            .all(
                      16,
                    ),

                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        18,
                      ),
                      borderSide:
                          BorderSide
                              .none,
                    ),

                    enabledBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        18,
                      ),
                      borderSide:
                          BorderSide
                              .none,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 14,
          ),

          Row(
            children: [
              const Icon(
                Icons
                    .lock_outline_rounded,
                size: 16,
                color:
                    AppColors.muted,
              ),

              const SizedBox(
                width: 6,
              ),

              const Expanded(
                child: Text(
                  'เห็นเฉพาะสมาชิกในครอบครัว',
                  style:
                      TextStyle(
                    color:
                        AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),

              FilledButton.icon(
                onPressed:
                    isPosting
                        ? null
                        : createPost,

                style:
                    FilledButton
                        .styleFrom(
                  backgroundColor:
                      AppColors.primary,

                  foregroundColor:
                      Colors.white,

                  minimumSize:
                      const Size(
                    0,
                    42,
                  ),

                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 17,
                  ),

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius
                            .circular(
                      14,
                    ),
                  ),
                ),

                icon:
                    isPosting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(
                              strokeWidth:
                                  2,
                              color:
                                  Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons
                                .send_rounded,
                            size: 17,
                          ),

                label: Text(
                  isPosting
                      ? 'กำลังส่ง'
                      : 'แชร์',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================
  // Post Card
  // =====================================================

  Widget buildPostCard(
    Map<String, dynamic> post,
  ) {
    final dynamic user =
        post['user'];

    final String name =
        user?['name']?.toString() ??
            'สมาชิก';

    final List<dynamic> comments =
        (post['comments'] as List?) ??
            [];

    final int postId =
        (post['id'] as num).toInt();

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 16,
      ),

      decoration:
          BoxDecoration(
        color:
            Colors.white,

        borderRadius:
            BorderRadius.circular(
          24,
        ),

        border:
            Border.all(
          color:
              AppColors.border,
        ),

        boxShadow: [
          BoxShadow(
            color:
                AppColors.navy
                    .withValues(
              alpha: 0.035,
            ),
            blurRadius: 22,
            offset:
                const Offset(
              0,
              8,
            ),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment
                .start,
        children: [
          // ===============================================
          // Post Header
          // ===============================================

          Padding(
            padding:
                const EdgeInsets
                    .fromLTRB(
              18,
              18,
              18,
              0,
            ),

            child: Row(
              children: [
                buildAvatar(
                  name: name,
                  imageUrl:
                      getProfileImage(
                    user,
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        name,
                        style:
                            const TextStyle(
                          color:
                              AppColors.navy,
                          fontSize: 15,
                          fontWeight:
                              FontWeight.w800,
                        ),
                      ),

                      const SizedBox(
                        height: 3,
                      ),

                      Row(
                        children: [
                          const Icon(
                            Icons
                                .family_restroom_rounded,
                            size: 13,
                            color:
                                AppColors
                                    .muted,
                          ),

                          const SizedBox(
                            width: 4,
                          ),

                          Text(
                            formatDate(
                              post[
                                  'created_at'],
                            ),
                            style:
                                const TextStyle(
                              color:
                                  AppColors
                                      .muted,
                              fontSize:
                                  11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      const BoxDecoration(
                    color:
                        AppColors.sky,
                    shape:
                        BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),

          // ===============================================
          // Content
          // ===============================================

          Padding(
            padding:
                const EdgeInsets
                    .fromLTRB(
              18,
              18,
              18,
              18,
            ),

            child: Text(
              post['content']
                      ?.toString() ??
                  '',

              style:
                  const TextStyle(
                color:
                    AppColors.navy,
                fontSize: 16,
                height: 1.55,
                fontWeight:
                    FontWeight.w500,
              ),
            ),
          ),

          // ===============================================
          // Comment Count
          // ===============================================

          if (comments.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets
                      .fromLTRB(
                18,
                0,
                18,
                12,
              ),

              child: Row(
                children: [
                  const Icon(
                    Icons
                        .chat_bubble_rounded,
                    size: 15,
                    color:
                        AppColors.muted,
                  ),

                  const SizedBox(
                    width: 6,
                  ),

                  Text(
                    '${comments.length} ความคิดเห็น',
                    style:
                        const TextStyle(
                      color:
                          AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          const Divider(
            height: 1,
          ),

          // ===============================================
          // Action
          // ===============================================

          InkWell(
            borderRadius:
                const BorderRadius
                    .vertical(
              bottom:
                  Radius.circular(
                24,
              ),
            ),

            onTap: () {
              showCommentDialog(
                postId,
              );
            },

            child: const Padding(
              padding:
                  EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),

              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment
                        .center,
                children: [
                  Icon(
                    Icons
                        .chat_bubble_outline_rounded,
                    color:
                        AppColors.primary,
                    size: 19,
                  ),

                  SizedBox(
                    width: 8,
                  ),

                  Text(
                    'แสดงความคิดเห็น',
                    style:
                        TextStyle(
                      color:
                          AppColors.primary,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ===============================================
          // Comments
          // ===============================================

          if (comments.isNotEmpty)
            Container(
              width:
                  double.infinity,

              decoration:
                  const BoxDecoration(
                color:
                    Color(
                  0xFFF8F9FD,
                ),

                borderRadius:
                    BorderRadius
                        .vertical(
                  bottom:
                      Radius.circular(
                    24,
                  ),
                ),
              ),

              padding:
                  const EdgeInsets
                      .fromLTRB(
                16,
                4,
                16,
                16,
              ),

              child: Column(
                children: comments.map(
                  (dynamic comment) {
                    final dynamic
                        commentUser =
                        comment['user'];

                    final String
                        commentName =
                        commentUser?[
                                    'name']
                                ?.toString() ??
                            'สมาชิก';

                    return Padding(
                      padding:
                          const EdgeInsets
                              .only(
                        top: 12,
                      ),

                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          buildAvatar(
                            name:
                                commentName,
                            imageUrl:
                                getProfileImage(
                              commentUser,
                            ),
                            radius: 16,
                          ),

                          const SizedBox(
                            width: 9,
                          ),

                          Expanded(
                            child:
                                Container(
                              padding:
                                  const EdgeInsets
                                      .fromLTRB(
                                13,
                                10,
                                13,
                                10,
                              ),

                              decoration:
                                  BoxDecoration(
                                color:
                                    Colors
                                        .white,
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  16,
                                ),
                                border:
                                    Border.all(
                                  color:
                                      AppColors
                                          .border,
                                ),
                              ),

                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Text(
                                    commentName,
                                    style:
                                        const TextStyle(
                                      color:
                                          AppColors
                                              .navy,
                                      fontSize:
                                          13,
                                      fontWeight:
                                          FontWeight
                                              .w800,
                                    ),
                                  ),

                                  const SizedBox(
                                    height:
                                        3,
                                  ),

                                  Text(
                                    comment[
                                                'content']
                                            ?.toString() ??
                                        '',
                                    style:
                                        const TextStyle(
                                      color:
                                          Color(
                                        0xFF344054,
                                      ),
                                      fontSize:
                                          14,
                                      height:
                                          1.4,
                                    ),
                                  ),

                                  if (comment[
                                          'created_at'] !=
                                      null) ...[
                                    const SizedBox(
                                      height:
                                          5,
                                    ),
                                    Text(
                                      formatDate(
                                        comment[
                                            'created_at'],
                                      ),
                                      style:
                                          const TextStyle(
                                        color:
                                            AppColors
                                                .muted,
                                        fontSize:
                                            10,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // =====================================================
  // Empty State
  // =====================================================

  Widget buildEmptyState() {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 25,
        vertical: 45,
      ),

      decoration:
          BoxDecoration(
        color:
            Colors.white,

        borderRadius:
            BorderRadius.circular(
          26,
        ),

        border:
            Border.all(
          color:
              AppColors.border,
        ),
      ),

      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,

            decoration:
                BoxDecoration(
              color:
                  AppColors.primary
                      .withValues(
                alpha: 0.09,
              ),

              shape:
                  BoxShape.circle,
            ),

            child:
                const Icon(
              Icons
                  .forum_outlined,
              size: 38,
              color:
                  AppColors.primary,
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          const Text(
            'วงโคจรยังเงียบอยู่',
            style:
                TextStyle(
              color:
                  AppColors.navy,
              fontSize: 19,
              fontWeight:
                  FontWeight.w800,
            ),
          ),

          const SizedBox(
            height: 7,
          ),

          const Text(
            'เริ่มต้นแชร์เรื่องราวแรกของครอบครัวกันเลย',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  AppColors.muted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color:
          AppColors.primary,

      onRefresh:
          loadPosts,

      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),

        padding:
            const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          35,
        ),

        children: [
          buildHeroHeader(),

          const SizedBox(
            height: 18,
          ),

          buildCreatePost(),

          const SizedBox(
            height: 26,
          ),

          Row(
            children: [
              const Text(
                'ล่าสุดในครอบครัว',
                style:
                    TextStyle(
                  color:
                      AppColors.navy,
                  fontSize: 20,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              const Spacer(),

              if (!isLoading &&
                  posts.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),

                  decoration:
                      BoxDecoration(
                    color:
                        AppColors.primary
                            .withValues(
                      alpha: 0.09,
                    ),

                    borderRadius:
                        BorderRadius
                            .circular(
                      999,
                    ),
                  ),

                  child: Text(
                    '${posts.length} โพสต์',
                    style:
                        const TextStyle(
                      color:
                          AppColors.primary,
                      fontSize: 11,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          if (isLoading)
            const Padding(
              padding:
                  EdgeInsets.symmetric(
                vertical: 65,
              ),
              child: Center(
                child:
                    CircularProgressIndicator(),
              ),
            )
          else if (posts.isEmpty)
            buildEmptyState()
          else
            ...posts.map(
              (dynamic item) {
                return buildPostCard(
                  Map<String, dynamic>.from(
                    item as Map,
                  ),
                );
              },
            ),
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