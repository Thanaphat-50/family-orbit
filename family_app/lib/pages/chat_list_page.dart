import 'dart:async';

import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'chat_room_page.dart';

// =======================================================
// รายการแชท
// - ด้านบน: คนในครอบครัว (กดเพื่อเริ่มคุย)
// - ด้านล่าง: ห้องแชทที่คุยกันแล้ว เรียงตามข้อความล่าสุด
// =======================================================

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  List<Map<String, dynamic>> conversations = [];

  List<Map<String, dynamic>> contacts = [];

  bool isLoading = true;

  String? loadError;

  // ระหว่างเปิดหน้านี้ โหลดใหม่เป็นระยะ (มีข้อความใหม่เข้ามา)
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();

    loadChats();

    refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => loadChats(),
    );
  }

  List<Map<String, dynamic>> parseList(dynamic raw) {
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> loadChats() async {
    try {
      final result = await ChatService.getChats();

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          conversations = parseList(result['conversations']);
          contacts = parseList(result['contacts']);
          loadError = null;
        });
      } else if (conversations.isEmpty) {
        setState(() {
          loadError = result['message']?.toString() ?? 'โหลดแชทไม่สำเร็จ';
        });
      }
    } catch (e) {
      if (mounted && conversations.isEmpty) {
        setState(() => loadError = e.toString());
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }

    ChatService.refreshUnreadCount();
  }

  // UserAvatar อ่านรูปจาก profile_photo_url
  Map<String, dynamic> avatarOf(dynamic user) {
    final Map<String, dynamic> data = user is Map
        ? Map<String, dynamic>.from(user)
        : {};

    return {...data, 'profile_photo_url': data['profile_image_url']};
  }

  Future<void> openRoom(int conversationId, dynamic user) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          conversationId: conversationId,
          user: user is Map ? Map<String, dynamic>.from(user) : null,
        ),
      ),
    );

    if (mounted) loadChats();
  }

  Future<void> startChat(Map<String, dynamic> contact) async {
    final dynamic existing = contact['conversation_id'];

    if (existing is num) {
      await openRoom(existing.toInt(), contact);
      return;
    }

    final dynamic id = contact['id'];

    if (id is! num) return;

    try {
      final result = await ChatService.openChat(id.toInt());

      if (!mounted) return;

      final dynamic room = result['conversation'];

      if (result['status'] == true && room is Map && room['id'] is num) {
        await openRoom((room['id'] as num).toInt(), room['user']);
      } else {
        showMessage(result['message']?.toString() ?? 'เปิดแชทไม่สำเร็จ');
      }
    } catch (e) {
      if (mounted) showMessage(e.toString());
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String formatTime(dynamic value) {
    final DateTime? time = DateTime.tryParse(value?.toString() ?? '')
        ?.toLocal();

    if (time == null) return '';

    final DateTime now = DateTime.now();

    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    }

    final int days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(time.year, time.month, time.day)).inDays;

    if (days == 1) return 'เมื่อวาน';

    if (days < 7) return '$days วันก่อน';

    return '${time.day}/${time.month}/${time.year}';
  }

  String previewOf(Map<String, dynamic> conversation) {
    final dynamic last = conversation['last_message'];

    if (last is! Map) return '';

    final String body = last['body']?.toString() ?? '';

    final String text = body.isNotEmpty
        ? body
        : (last['has_image'] == true ? '📷 รูปภาพ' : '');

    return last['is_mine'] == true ? 'คุณ: $text' : text;
  }

  // =====================================================
  // UI
  // =====================================================

  Widget buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget buildContacts() {
    if (contacts.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'ยังไม่มีคนอื่นในครอบครัว ชวนคนในบ้านเข้าครอบครัวด้วยรหัสเชิญ แล้วคุยกันได้ที่นี่',
          style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
        ),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: contacts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final Map<String, dynamic> contact = contacts[index];

          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => startChat(contact),
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  UserAvatar(user: avatarOf(contact), radius: 28),
                  const SizedBox(height: 6),
                  Text(
                    contact['name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget buildConversation(Map<String, dynamic> conversation) {
    final dynamic user = conversation['user'];

    final String name = user is Map
        ? (user['name']?.toString() ?? 'แชท')
        : 'แชท';

    final dynamic unreadValue = conversation['unread_count'];

    final int unread = unreadValue is num ? unreadValue.toInt() : 0;

    final dynamic last = conversation['last_message'];

    return ListTile(
      onTap: () {
        final dynamic id = conversation['id'];

        if (id is num) openRoom(id.toInt(), user);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: UserAvatar(user: avatarOf(user), radius: 26),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            last is Map ? formatTime(last['created_at']) : '',
            style: TextStyle(
              color: unread > 0 ? AppColors.primary : AppColors.muted,
              fontSize: 12,
              fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                previewOf(conversation),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unread > 0 ? AppColors.navy : AppColors.muted,
                  fontSize: 13.5,
                  fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (unread > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
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

    if (loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    isLoading = true;
                    loadError = null;
                  });
                  loadChats();
                },
                child: const Text('ลองอีกครั้ง'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: loadChats,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          buildSectionTitle('คนในครอบครัว'),
          buildContacts(),
          buildSectionTitle('ข้อความ'),
          if (conversations.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                children: [
                  Icon(Icons.forum_outlined, size: 40, color: AppColors.muted),
                  SizedBox(height: 10),
                  Text(
                    'ยังไม่มีข้อความ\nกดรูปคนในครอบครัวด้านบนเพื่อเริ่มคุย',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          else
            ...conversations.map(buildConversation),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แชท')),
      body: buildBody(),
    );
  }

  @override
  void dispose() {
    refreshTimer?.cancel();

    super.dispose();
  }
}
