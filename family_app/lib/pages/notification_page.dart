import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class NotificationPage
    extends StatefulWidget {
  const NotificationPage({
    super.key,
  });

  @override
  State<NotificationPage> createState() =>
      _NotificationPageState();
}

class _NotificationPageState
    extends State<NotificationPage> {
  bool isLoading = true;
  bool isReadingAll = false;

  List<Map<String, dynamic>>
      notifications = [];

  @override
  void initState() {
    super.initState();

    loadNotifications();
  }

  // =====================================================
  // LOAD
  // =====================================================

  Future<void>
      loadNotifications() async {
    try {
      final result =
          await NotificationService
              .getNotifications();

      if (!mounted) return;

      final List<Map<String, dynamic>>
          items =
          extractNotifications(
        result,
      );

      setState(() {
        notifications =
            items;

        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      showMessage(
        'โหลดการแจ้งเตือนไม่สำเร็จ',
      );
    }
  }

  // =====================================================
  // รองรับ response หลายรูปแบบ
  // =====================================================

  List<Map<String, dynamic>>
      extractNotifications(
    Map<String, dynamic> result,
  ) {
    dynamic raw =
        result['notifications'] ??
            result['data'];

    // Laravel Pagination
    if (raw is Map) {
      raw = raw['data'] ??
          raw['notifications'];
    }

    if (raw is! List) {
      return [];
    }

    final List<Map<String, dynamic>>
        items = [];

    for (final item in raw) {
      if (item is Map) {
        items.add(
          Map<String, dynamic>.from(
            item,
          ),
        );
      }
    }

    return items;
  }

  // =====================================================
  // READ STATE
  // =====================================================

  bool isRead(
    Map<String, dynamic> item,
  ) {
    final value =
        item['is_read'];

    return value == true ||
        value == 1 ||
        value == '1';
  }

  int get unreadCount {
    return notifications
        .where(
          (item) => !isRead(item),
        )
        .length;
  }

  // =====================================================
  // MARK ONE
  // =====================================================

  Future<void> markRead(
    Map<String, dynamic> item,
  ) async {
    if (isRead(item)) {
      return;
    }

    final idValue =
        item['id'];

    if (idValue is! num) {
      return;
    }

    try {
      final result =
          await NotificationService
              .markAsRead(
        idValue.toInt(),
      );

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          item['is_read'] =
              true;
        });
      }
    } catch (_) {
      // ถ้าอ่านสถานะไม่สำเร็จ
      // ยังเปิดรายละเอียดให้ผู้ใช้ดูได้
    }
  }

  // =====================================================
  // READ ALL
  // =====================================================

  Future<void>
      markAllRead() async {
    if (unreadCount == 0 ||
        isReadingAll) {
      return;
    }

    setState(() {
      isReadingAll = true;
    });

    try {
      final result =
          await NotificationService
              .markAllAsRead();

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          for (final item
              in notifications) {
            item['is_read'] =
                true;
          }
        });

        showMessage(
          'อ่านการแจ้งเตือนทั้งหมดแล้ว',
        );
      } else {
        showMessage(
          result['message'] ??
              'ดำเนินการไม่สำเร็จ',
        );
      }
    } catch (_) {
      if (!mounted) return;

      showMessage(
        'ไม่สามารถอัปเดตการแจ้งเตือนได้',
      );
    } finally {
      if (mounted) {
        setState(() {
          isReadingAll =
              false;
        });
      }
    }
  }

  // =====================================================
  // OPEN DETAIL
  // =====================================================

  Future<void> openNotification(
    Map<String, dynamic> item,
  ) async {
    await markRead(
      item,
    );

    if (!mounted) return;

    final type =
        item['type']
                ?.toString() ??
            '';

    final style =
        getNotificationStyle(
      type,
    );

    await showModalBottomSheet<void>(
      context: context,

      backgroundColor:
          Colors.transparent,

      isScrollControlled: true,

      builder: (
        sheetContext,
      ) {
        return Container(
          margin:
              const EdgeInsets.only(
            top: 120,
          ),

          decoration:
              const BoxDecoration(
            color:
                Colors.white,

            borderRadius:
                BorderRadius.vertical(
              top:
                  Radius.circular(
                30,
              ),
            ),
          ),

          child: SafeArea(
            top: false,

            child: Padding(
              padding:
                  const EdgeInsets
                      .fromLTRB(
                22,
                12,
                22,
                27,
              ),

              child: Column(
                mainAxisSize:
                    MainAxisSize.min,

                crossAxisAlignment:
                    CrossAxisAlignment
                        .stretch,

                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,

                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xFFD8DBE5,
                        ),

                        borderRadius:
                            BorderRadius.circular(
                          99,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 25,
                  ),

                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,

                        decoration:
                            BoxDecoration(
                          color:
                              style.color
                                  .withValues(
                            alpha:
                                0.10,
                          ),

                          borderRadius:
                              BorderRadius.circular(
                            17,
                          ),
                        ),

                        child: Icon(
                          style.icon,

                          color:
                              style.color,

                          size: 27,
                        ),
                      ),

                      const SizedBox(
                        width: 14,
                      ),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              style.label,

                              style:
                                  TextStyle(
                                color:
                                    style.color,
                                fontSize: 10,
                                fontWeight:
                                    FontWeight.w800,
                                letterSpacing:
                                    0.8,
                              ),
                            ),

                            const SizedBox(
                              height: 4,
                            ),

                            Text(
                              item['title']
                                      ?.toString() ??
                                  'การแจ้งเตือน',

                              style:
                                  const TextStyle(
                                color:
                                    AppColors.navy,
                                fontSize: 19,
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        onPressed: () {
                          Navigator.of(
                            sheetContext,
                          ).pop();
                        },

                        icon:
                            const Icon(
                          Icons
                              .close_rounded,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 22,
                  ),

                  Container(
                    padding:
                        const EdgeInsets
                            .all(
                      17,
                    ),

                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xFFF7F8FC,
                      ),

                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),

                      border:
                          Border.all(
                        color:
                            AppColors.border,
                      ),
                    ),

                    child: Text(
                      item['message']
                              ?.toString() ??
                          '',

                      style:
                          const TextStyle(
                        color:
                            Color(
                          0xFF344054,
                        ),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 15,
                  ),

                  Row(
                    children: [
                      const Icon(
                        Icons
                            .schedule_rounded,
                        color:
                            AppColors.muted,
                        size: 16,
                      ),

                      const SizedBox(
                        width: 6,
                      ),

                      Text(
                        formatDateTime(
                          item[
                              'created_at'],
                        ),

                        style:
                            const TextStyle(
                          color:
                              AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 25,
                  ),

                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(
                        sheetContext,
                      ).pop();
                    },

                    child:
                        const Text(
                      'เรียบร้อย',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =====================================================
  // DATE
  // =====================================================

  String formatTimeAgo(
    dynamic value,
  ) {
    if (value == null) {
      return '';
    }

    try {
      final date =
          DateTime.parse(
        value.toString(),
      ).toLocal();

      final difference =
          DateTime.now()
              .difference(
        date,
      );

      if (difference.isNegative ||
          difference.inMinutes < 1) {
        return 'เมื่อสักครู่';
      }

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} นาทีที่แล้ว';
      }

      if (difference.inHours < 24) {
        return '${difference.inHours} ชั่วโมงที่แล้ว';
      }

      if (difference.inDays == 1) {
        return 'เมื่อวาน';
      }

      if (difference.inDays < 7) {
        return '${difference.inDays} วันที่แล้ว';
      }

      return '${date.day}/'
          '${date.month}/'
          '${date.year}';
    } catch (_) {
      return '';
    }
  }

  String formatDateTime(
    dynamic value,
  ) {
    if (value == null) {
      return '-';
    }

    try {
      final date =
          DateTime.parse(
        value.toString(),
      ).toLocal();

      final hour =
          date.hour
              .toString()
              .padLeft(
                2,
                '0',
              );

      final minute =
          date.minute
              .toString()
              .padLeft(
                2,
                '0',
              );

      return '${date.day}/'
          '${date.month}/'
          '${date.year} • '
          '$hour:$minute น.';
    } catch (_) {
      return '-';
    }
  }

  // =====================================================
  // STYLE ตาม TYPE
  // =====================================================

  _NotificationStyle
      getNotificationStyle(
    String type,
  ) {
    switch (type) {
      case 'member_joined':
        return const _NotificationStyle(
          icon:
              Icons
                  .person_add_alt_1_rounded,

          color:
              AppColors.sky,

          label:
              'NEW MEMBER',
        );

      case 'new_post':
        return const _NotificationStyle(
          icon:
              Icons
                  .dynamic_feed_rounded,

          color:
              AppColors.primary,

          label:
              'NEW POST',
        );

      case 'new_comment':
        return const _NotificationStyle(
          icon:
              Icons
                  .chat_bubble_rounded,

          color:
              AppColors.warm,

          label:
              'NEW COMMENT',
        );

      case 'new_activity':
        return const _NotificationStyle(
          icon: Icons.event_available_rounded,

          color: AppColors.success,

          label: 'NEW ACTIVITY',
        );

      default:
        return const _NotificationStyle(
          icon:
              Icons
                  .notifications_rounded,

          color:
              AppColors.primary,

          label:
              'FAMILY ORBIT',
        );
    }
  }

  // =====================================================
  // HEADER
  // =====================================================

  Widget buildHero() {
    return Container(
      padding:
          const EdgeInsets.all(
        22,
      ),

      decoration:
          BoxDecoration(
        gradient:
            const LinearGradient(
          begin:
              Alignment.topLeft,
          end:
              Alignment.bottomRight,
          colors: [
            Color(
              0xFF172554,
            ),
            Color(
              0xFF4650D8,
            ),
            Color(
              0xFF656BFF,
            ),
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
              alpha: 0.20,
            ),

            blurRadius: 30,

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
          Positioned(
            right: -45,
            top: -65,

            child: Container(
              width: 175,
              height: 175,

              decoration:
                  BoxDecoration(
                shape:
                    BoxShape.circle,

                border:
                    Border.all(
                  color:
                      Colors.white
                          .withValues(
                    alpha: 0.11,
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            right: 10,
            bottom: -65,

            child: Container(
              width: 125,
              height: 125,

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

          Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,

            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),

                    decoration:
                        BoxDecoration(
                      color:
                          Colors.white
                              .withValues(
                        alpha: 0.13,
                      ),

                      borderRadius:
                          BorderRadius.circular(
                        99,
                      ),
                    ),

                    child:
                        const Row(
                      children: [
                        Icon(
                          Icons
                              .notifications_active_rounded,
                          color:
                              AppColors.warm,
                          size: 15,
                        ),

                        SizedBox(
                          width: 6,
                        ),

                        Text(
                          'ORBIT SIGNAL',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w800,
                            letterSpacing:
                                1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  if (unreadCount > 0)
                    Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),

                      decoration:
                          BoxDecoration(
                        color:
                            AppColors.warm
                                .withValues(
                          alpha:
                              0.18,
                        ),

                        borderRadius:
                            BorderRadius.circular(
                          99,
                        ),
                      ),

                      child: Text(
                        '$unreadCount NEW',

                        style:
                            const TextStyle(
                          color:
                              AppColors.warm,
                          fontSize: 10,
                          fontWeight:
                              FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(
                height: 21,
              ),

              const Text(
                'ไม่พลาดทุกเรื่อง\nของคนในวงโคจร',
                style:
                    TextStyle(
                  color:
                      Colors.white,
                  fontSize: 25,
                  height: 1.18,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              const SizedBox(
                height: 9,
              ),

              Text(
                unreadCount == 0
                    ? 'คุณอ่านการแจ้งเตือนครบทั้งหมดแล้ว'
                    : 'มี $unreadCount เรื่องใหม่ที่รอคุณอยู่',

                style:
                    TextStyle(
                  color:
                      Colors.white
                          .withValues(
                    alpha: 0.75,
                  ),

                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================
  // NOTIFICATION CARD
  // =====================================================

  Widget buildNotificationCard(
    Map<String, dynamic> item,
  ) {
    final bool read =
        isRead(
      item,
    );

    final style =
        getNotificationStyle(
      item['type']
              ?.toString() ??
          '',
    );

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),

      decoration:
          BoxDecoration(
        color: read
            ? Colors.white
            : AppColors.primary
                .withValues(
                  alpha: 0.045,
                ),

        borderRadius:
            BorderRadius.circular(
          21,
        ),

        border:
            Border.all(
          color: read
              ? AppColors.border
              : AppColors.primary
                  .withValues(
                    alpha: 0.18,
                  ),
        ),
      ),

      child: Material(
        color:
            Colors.transparent,

        child: InkWell(
          borderRadius:
              BorderRadius.circular(
            21,
          ),

          onTap: () {
            openNotification(
              item,
            );
          },

          child: Padding(
            padding:
                const EdgeInsets
                    .fromLTRB(
              14,
              14,
              10,
              14,
            ),

            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

              children: [
                // =======================================
                // ICON
                // =======================================

                Stack(
                  clipBehavior:
                      Clip.none,

                  children: [
                    Container(
                      width: 48,
                      height: 48,

                      decoration:
                          BoxDecoration(
                        color:
                            style.color
                                .withValues(
                          alpha:
                              0.10,
                        ),

                        borderRadius:
                            BorderRadius.circular(
                          15,
                        ),
                      ),

                      child: Icon(
                        style.icon,

                        color:
                            style.color,

                        size: 23,
                      ),
                    ),

                    if (!read)
                      Positioned(
                        right: -2,
                        top: -2,

                        child: Container(
                          width: 11,
                          height: 11,

                          decoration:
                              BoxDecoration(
                            color:
                                AppColors.danger,

                            shape:
                                BoxShape.circle,

                            border:
                                Border.all(
                              color:
                                  Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(
                  width: 12,
                ),

                // =======================================
                // CONTENT
                // =======================================

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['title']
                                      ?.toString() ??
                                  'การแจ้งเตือน',

                              maxLines: 1,

                              overflow:
                                  TextOverflow
                                      .ellipsis,

                              style:
                                  TextStyle(
                                color:
                                    AppColors.navy,

                                fontSize: 14,

                                fontWeight:
                                    read
                                        ? FontWeight.w700
                                        : FontWeight.w800,
                              ),
                            ),
                          ),

                          if (!read)
                            Container(
                              margin:
                                  const EdgeInsets.only(
                                left: 7,
                              ),

                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),

                              decoration:
                                  BoxDecoration(
                                color:
                                    AppColors.primary,

                                borderRadius:
                                    BorderRadius.circular(
                                  99,
                                ),
                              ),

                              child:
                                  const Text(
                                'ใหม่',
                                style:
                                    TextStyle(
                                  color:
                                      Colors.white,
                                  fontSize: 8,
                                  fontWeight:
                                      FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(
                        height: 5,
                      ),

                      Text(
                        item['message']
                                ?.toString() ??
                            '',

                        maxLines: 2,

                        overflow:
                            TextOverflow
                                .ellipsis,

                        style:
                            const TextStyle(
                          color:
                              AppColors.muted,

                          fontSize: 12,

                          height: 1.45,
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      Row(
                        children: [
                          Icon(
                            style.icon,

                            color:
                                style.color,

                            size: 12,
                          ),

                          const SizedBox(
                            width: 5,
                          ),

                          Text(
                            style.label,

                            style:
                                TextStyle(
                              color:
                                  style.color,

                              fontSize: 8,

                              fontWeight:
                                  FontWeight.w800,

                              letterSpacing:
                                  0.5,
                            ),
                          ),

                          const SizedBox(
                            width: 8,
                          ),

                          Container(
                            width: 3,
                            height: 3,

                            decoration:
                                const BoxDecoration(
                              color:
                                  AppColors.muted,
                              shape:
                                  BoxShape.circle,
                            ),
                          ),

                          const SizedBox(
                            width: 8,
                          ),

                          Text(
                            formatTimeAgo(
                              item[
                                  'created_at'],
                            ),

                            style:
                                const TextStyle(
                              color:
                                  AppColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(
                  width: 4,
                ),

                const Padding(
                  padding:
                      EdgeInsets.only(
                    top: 12,
                  ),

                  child: Icon(
                    Icons
                        .chevron_right_rounded,
                    color:
                        AppColors.muted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // EMPTY
  // =====================================================

  Widget buildEmptyState() {
    return Container(
      width:
          double.infinity,

      padding:
          const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 48,
      ),

      decoration:
          BoxDecoration(
        color:
            Colors.white,

        borderRadius:
            BorderRadius.circular(
          25,
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
            width: 86,
            height: 86,

            decoration:
                BoxDecoration(
              color:
                  AppColors.primary
                      .withValues(
                alpha: 0.08,
              ),

              shape:
                  BoxShape.circle,
            ),

            child:
                const Icon(
              Icons
                  .notifications_none_rounded,

              size: 39,

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
            'เมื่อมีสมาชิกใหม่ โพสต์ หรือความคิดเห็น\n'
            'การแจ้งเตือนจะปรากฏที่นี่',

            textAlign:
                TextAlign.center,

            style:
                TextStyle(
              color:
                  AppColors.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // MESSAGE
  // =====================================================

  void showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          AppColors.background,

      appBar: AppBar(
        title:
            const Text(
          'การแจ้งเตือน',
        ),

        leading:
            IconButton(
          onPressed: () {
            Navigator.of(
              context,
            ).pop();
          },

          icon:
              const Icon(
            Icons
                .arrow_back_rounded,
          ),
        ),

        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed:
                  isReadingAll
                      ? null
                      : markAllRead,

              child:
                  isReadingAll
                      ? const SizedBox(
                          width: 17,
                          height: 17,

                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2,
                          ),
                        )
                      : const Text(
                          'อ่านทั้งหมด',
                        ),
            ),

          const SizedBox(
            width: 6,
          ),
        ],
      ),

      body:
          RefreshIndicator(
        color:
            AppColors.primary,

        onRefresh:
            loadNotifications,

        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),

          padding:
              const EdgeInsets.fromLTRB(
            17,
            10,
            17,
            35,
          ),

          children: [
            buildHero(),

            const SizedBox(
              height: 26,
            ),

            Row(
              children: [
                const Text(
                  'ล่าสุด',
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
                    notifications
                        .isNotEmpty)
                  Text(
                    '${notifications.length} รายการ',

                    style:
                        const TextStyle(
                      color:
                          AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),

            const SizedBox(
              height: 5,
            ),

            const Text(
              'ข่าวสารและความเคลื่อนไหวภายในครอบครัว',

              style:
                  TextStyle(
                color:
                    AppColors.muted,
                fontSize: 12,
              ),
            ),

            const SizedBox(
              height: 15,
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
            else if (notifications
                .isEmpty)
              buildEmptyState()
            else
              ...notifications.map(
                buildNotificationCard,
              ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// NOTIFICATION STYLE
// =======================================================

class _NotificationStyle {
  final IconData icon;
  final Color color;
  final String label;

  const _NotificationStyle({
    required this.icon,
    required this.color,
    required this.label,
  });
}