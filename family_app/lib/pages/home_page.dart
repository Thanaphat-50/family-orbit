import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../config/app_info.dart';
import '../services/auth_service.dart';
import '../services/family_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/section_switch.dart';

import 'activity_page.dart';
import 'feed_page.dart';
import 'map_page.dart';
import 'my_shop_page.dart';
import 'notification_page.dart';
import 'profile_page.dart';
import 'shop_page.dart';

// หน้าย่อยของแท็บ "หน้าหลัก"
enum HomeSection { community, shop }

// หน้าย่อยของแท็บ "ครอบครัว"
enum FamilySection { posts, members }

class HomePage extends StatefulWidget {
  final String userName;

  const HomePage({super.key, required this.userName});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final TextEditingController familyNameController = TextEditingController();

  final TextEditingController inviteCodeController = TextEditingController();

  int selectedIndex = 0;
  int unreadNotificationCount = 0;

  // หน้าหลัก: ชุมชน | ตลาด
  HomeSection homeSection = HomeSection.community;

  // ครอบครัว: โพสต์ | สมาชิก
  FamilySection familySection = FamilySection.posts;

  // แถบเมนูล่าง: ในแท็บหน้าหลัก เลื่อนลงแล้วซ่อน เลื่อนขึ้นแล้วแสดง
  bool bottomBarVisible = true;

  // เพิ่มเมื่อร้านของเราเปลี่ยน → หน้าตลาดโหลดใหม่
  int marketRefreshToken = 0;

  bool isLoading = true;
  bool isWorking = false;

  Map<String, dynamic>? familyData;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    loadFamily();
    loadUnreadNotificationCount();
  }

  // =====================================================
  // APP LIFECYCLE
  // =====================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadFamily(showLoading: false);

      loadUnreadNotificationCount();
    }
  }

  // =====================================================
  // FAMILY
  // =====================================================

  Future<void> loadFamily({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final result = await FamilyService.getCurrentFamily();

      if (!mounted) return;

      setState(() {
        familyData = result;
      });
    } catch (e) {
      if (!mounted) return;

      showMessage('โหลดข้อมูลครอบครัวไม่สำเร็จ: $e');
    } finally {
      if (showLoading && mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // =====================================================
  // NOTIFICATION
  // =====================================================

  Future<void> loadUnreadNotificationCount() async {
    try {
      final count = await NotificationService.getUnreadCount();

      if (!mounted) return;

      setState(() {
        unreadNotificationCount = count;
      });
    } catch (_) {
      // Notification ล้มเหลว
      // ไม่ให้กระทบหน้าหลัก
    }
  }

  Future<void> openNotifications() async {
    final NotificationTarget? target = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationPage()),
    );

    if (!mounted) return;

    // กดการแจ้งเตือนกิจกรรม / สมาชิกใหม่ → เปิดแท็บนั้น
    switch (target) {
      case NotificationTarget.activities:
        setState(() {
          selectedIndex = 3;
          bottomBarVisible = true;
        });
      case NotificationTarget.familyMembers:
        setState(() {
          selectedIndex = 1;
          familySection = FamilySection.members;
          bottomBarVisible = true;
        });
        loadFamily(showLoading: false);
      case null:
        break;
    }

    await loadUnreadNotificationCount();
  }

  // =====================================================
  // MESSAGE
  // =====================================================

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // CREATE FAMILY
  // =====================================================

  Future<void> createFamily() async {
    final name = familyNameController.text.trim();

    if (name.isEmpty) {
      showMessage('กรุณาใส่ชื่อครอบครัว');

      return;
    }

    setState(() {
      isWorking = true;
    });

    try {
      final result = await FamilyService.createFamily(name: name);

      if (!mounted) return;

      if (result['status'] == true) {
        familyNameController.clear();

        await loadFamily();

        if (!mounted) return;

        showMessage('สร้างครอบครัวสำเร็จ');
      } else {
        showMessage(result['message'] ?? 'สร้างครอบครัวไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) {
        setState(() {
          isWorking = false;
        });
      }
    }
  }

  // =====================================================
  // JOIN FAMILY
  // =====================================================

  Future<void> joinFamily() async {
    final code = inviteCodeController.text.trim();

    if (code.isEmpty) {
      showMessage('กรุณาใส่ Invite Code');

      return;
    }

    setState(() {
      isWorking = true;
    });

    try {
      final result = await FamilyService.joinFamily(inviteCode: code);

      if (!mounted) return;

      if (result['status'] == true) {
        inviteCodeController.clear();

        await loadFamily();

        if (!mounted) return;

        showMessage('เข้าร่วมครอบครัวสำเร็จ');
      } else {
        showMessage(result['message'] ?? 'เข้าร่วมครอบครัวไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) {
        setState(() {
          isWorking = false;
        });
      }
    }
  }

  // =====================================================
  // COPY INVITE CODE
  // =====================================================

  Future<void> copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));

    if (!mounted) return;

    showMessage('คัดลอก Invite Code แล้ว');
  }

  // =====================================================
  // EDIT FAMILY NAME
  // =====================================================

  Future<void> editFamilyName() async {
    final family = familyData?['family'];

    if (family == null) return;

    String newName = family['name']?.toString() ?? '';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          surfaceTintColor: Colors.transparent,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),

          title: const Text(
            'เปลี่ยนชื่อครอบครัว',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),

          content: TextFormField(
            initialValue: newName,

            autofocus: true,

            onChanged: (value) {
              newName = value;
            },

            decoration: const InputDecoration(
              labelText: 'ชื่อครอบครัว',
              prefixIcon: Icon(Icons.family_restroom_rounded),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('ยกเลิก'),
            ),

            FilledButton(
              onPressed: () {
                final name = newName.trim();

                if (name.isEmpty) {
                  return;
                }

                Navigator.of(dialogContext).pop(name);
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    try {
      final response = await FamilyService.updateFamilyName(
        familyId: (family['id'] as num).toInt(),
        name: result,
      );

      if (!mounted) return;

      if (response['status'] == true) {
        await loadFamily(showLoading: false);

        if (!mounted) return;

        showMessage('เปลี่ยนชื่อครอบครัวสำเร็จ');
      } else {
        showMessage(response['message'] ?? 'เปลี่ยนชื่อครอบครัวไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  // =====================================================
  // REGENERATE INVITE CODE
  // =====================================================

  Future<void> regenerateInviteCode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          surfaceTintColor: Colors.transparent,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),

          title: const Text(
            'สร้าง Invite Code ใหม่',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),

          content: const Text('รหัสเดิมจะไม่สามารถใช้เข้าร่วมครอบครัวได้อีก'),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),

            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('สร้างรหัสใหม่'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    try {
      final response = await FamilyService.regenerateInviteCode();

      if (!mounted) return;

      if (response['status'] == true) {
        await loadFamily(showLoading: false);

        if (!mounted) return;

        showMessage('สร้าง Invite Code ใหม่แล้ว');
      } else {
        showMessage(response['message'] ?? 'สร้าง Invite Code ใหม่ไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  // =====================================================
  // REMOVE MEMBER
  // =====================================================

  Future<void> removeFamilyMember(int userId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          surfaceTintColor: Colors.transparent,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),

          title: const Text(
            'นำสมาชิกออก',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),

          content: Text('ต้องการนำ $name ออกจากครอบครัวหรือไม่?'),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),

            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('นำออก'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    try {
      final response = await FamilyService.removeMember(userId: userId);

      if (!mounted) return;

      if (response['status'] == true) {
        await loadFamily(showLoading: false);

        if (!mounted) return;

        showMessage('นำสมาชิกออกจากครอบครัวแล้ว');
      } else {
        showMessage(response['message'] ?? 'นำสมาชิกออกไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  // =====================================================
  // LEAVE FAMILY
  // =====================================================

  Future<void> leaveFamily() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          surfaceTintColor: Colors.transparent,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),

          title: const Text(
            'ออกจากครอบครัว',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),

          content: const Text('คุณต้องการออกจากครอบครัวนี้หรือไม่?'),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),

            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('ออกจากครอบครัว'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    try {
      final response = await FamilyService.leaveFamily();

      if (!mounted) return;

      if (response['status'] == true) {
        await loadFamily();

        if (!mounted) return;

        setState(() {
          selectedIndex = 0;
        });

        showMessage('ออกจากครอบครัวแล้ว');
      } else {
        showMessage(response['message'] ?? 'ไม่สามารถออกจากครอบครัวได้');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  // =====================================================
  // TRANSFER OWNER
  // =====================================================

  Future<void> transferFamilyOwner(int userId, String memberName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          surfaceTintColor: Colors.transparent,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),

          title: const Text(
            'โอนสิทธิ์ Owner',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),

          content: Text(
            'ต้องการโอนสิทธิ์ Owner ให้ $memberName หรือไม่?\n\n'
            'หลังจากโอนแล้ว คุณจะกลายเป็น Member',
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),

            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('โอนสิทธิ์'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    try {
      final result = await FamilyService.transferOwner(userId: userId);

      if (!mounted) return;

      if (result['status'] == true) {
        await loadFamily(showLoading: false);

        if (!mounted) return;

        showMessage('โอนสิทธิ์ Owner ให้ $memberName สำเร็จ');
      } else {
        showMessage(result['message'] ?? 'โอนสิทธิ์ Owner ไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  // =====================================================
  // DELETE FAMILY
  // =====================================================

  Future<void> deleteCurrentFamily() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,

          surfaceTintColor: Colors.transparent,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),

          icon: const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.danger,
            size: 42,
          ),

          title: const Text(
            'ลบครอบครัว?',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),

          content: const Text(
            'สมาชิกทั้งหมดจะออกจากครอบครัว '
            'โพสต์และข้อมูลของครอบครัวจะถูกลบ\n\n'
            'การดำเนินการนี้ไม่สามารถย้อนกลับได้',
            textAlign: TextAlign.center,
          ),

          actionsAlignment: MainAxisAlignment.center,

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),

            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('ลบครอบครัว'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    try {
      final result = await FamilyService.deleteFamily();

      if (!mounted) return;

      if (result['status'] == true) {
        await loadFamily();

        if (!mounted) return;

        setState(() {
          selectedIndex = 0;
        });

        showMessage('ลบครอบครัวสำเร็จ');
      } else {
        showMessage(result['message'] ?? 'ลบครอบครัวไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  // =====================================================
  // LOGOUT
  // =====================================================

  Future<void> logout() async {
    await AuthService.logout();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // =====================================================
  // HELPERS
  // =====================================================

  bool get hasFamily => familyData?['has_family'] == true;

  String getPageTitle() {
    switch (selectedIndex) {
      case 0:
        return homeSection == HomeSection.shop ? 'ตลาด' : 'ชุมชน';

      case 1:
        return 'ครอบครัว';

      case 2:
        return 'Family Map';

      case 3:
        return 'กิจกรรม';

      case 4:
        return 'โปรไฟล์';

      default:
        return AppInfo.name;
    }
  }

  String getInitial(String name) {
    final text = name.trim();

    if (text.isEmpty) {
      return '?';
    }

    return text.characters.first.toUpperCase();
  }

  String? getMemberProfileImage(dynamic member) {
    if (member is! Map) return null;

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
      final value = member[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return null;
  }

  Widget buildMemberAvatar({
    required String name,
    required bool isOwner,
    String? imageUrl,
    double size = 48,
  }) {
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    Widget fallbackAvatar() {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isOwner
                ? const [AppColors.warm, Color(0xFFFF8A5B)]
                : const [AppColors.primary, Color(0xFF767BFF)],
          ),
          shape: BoxShape.circle,
        ),
        child: Text(
          getInitial(name),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: hasImage
                ? Image.network(
                    imageUrl.trim(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallbackAvatar(),
                  )
                : fallbackAvatar(),
          ),
        ),

        if (isOwner)
          Positioned(
            right: -3,
            bottom: -2,
            child: Container(
              width: 21,
              height: 21,

              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,

                border: Border.all(color: AppColors.border),
              ),

              child: const Icon(
                Icons.workspace_premium_rounded,
                size: 14,
                color: AppColors.warm,
              ),
            ),
          ),
      ],
    );
  }

  // =====================================================
  // PAGE SELECTOR
  // =====================================================

  Widget getCurrentPage() {
    if (isLoading &&
        (selectedIndex == 0 || selectedIndex == 1 || selectedIndex == 2)) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (selectedIndex) {
      case 0:
        if (!hasFamily) {
          return buildNoFamily();
        }

        return buildHomeTab();

      case 1:
        return buildFamilyContent();

      case 2:
        if (!hasFamily) {
          return buildFamilyRequiredPage(
            message: 'เข้าร่วมครอบครัวก่อนเพื่อดูตำแหน่งของสมาชิก',
          );
        }

        return const MapPage();

      case 3:
        return const ActivityPage();

      case 4:
        return const ProfilePage();

      default:
        return buildNoFamily();
    }
  }

  // =====================================================
  // NOTIFICATION BUTTON
  // =====================================================

  Widget buildNotificationButton() {
    return IconButton(
      onPressed: openNotifications,

      tooltip: 'การแจ้งเตือน',

      icon: Stack(
        clipBehavior: Clip.none,

        children: [
          const Icon(Icons.notifications_none_rounded, size: 26),

          if (unreadNotificationCount > 0)
            Positioned(
              right: -6,
              top: -5,

              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),

                padding: const EdgeInsets.symmetric(horizontal: 4),

                alignment: Alignment.center,

                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),

                child: Text(
                  unreadNotificationCount > 99
                      ? '99+'
                      : unreadNotificationCount.toString(),

                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =====================================================
  // แท็บ ชุมชน | ตลาด บนแถบด้านบน
  // =====================================================

  bool get showHomeTabs => selectedIndex == 0 && hasFamily && !isLoading;

  void switchHomeSection(HomeSection section) {
    if (section == homeSection) return;

    setState(() {
      homeSection = section;
      bottomBarVisible = true;
    });
  }

  Widget buildAppLogo() {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF787CFF)],
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Icon(
        Icons.family_restroom_rounded,
        color: Colors.white,
        size: 21,
      ),
    );
  }

  Widget buildHomeTabs() {
    return Row(
      children: [
        buildAppLogo(),
        const SizedBox(width: 8),
        buildHomeTabButton(HomeSection.community, 'ชุมชน'),
        buildHomeTabButton(HomeSection.shop, 'ตลาด'),
      ],
    );
  }

  // แท็บที่เลือกอยู่: ตัวหนา + ขีดใต้ / แท็บอื่น: สีจาง
  Widget buildHomeTabButton(HomeSection section, String label) {
    final bool selected = homeSection == section;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => switchHomeSection(section),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.navy : AppColors.muted,
                  fontSize: selected ? 20 : 17,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 22 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ปุ่ม 🏪 บัญชีผู้ขาย (แสดงเมื่ออยู่หน้าตลาด)
  Future<void> openSellerAccount() async {
    final dynamic changed = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => const MyShopPage()));

    if (changed == true && mounted) {
      setState(() {
        marketRefreshToken++;
      });
    }
  }

  // เลื่อนลง → ซ่อนแถบล่าง / เลื่อนขึ้น → แสดง (เฉพาะแท็บหน้าหลัก)
  bool handleUserScroll(UserScrollNotification notification) {
    if (selectedIndex != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    // แจ้งครั้งเดียวตอนเริ่มลาก (ตอนนั้นยังอยู่บนสุด) จึงดูแค่ทิศทาง
    final ScrollDirection direction = notification.direction;

    final bool atTop =
        notification.metrics.pixels <= notification.metrics.minScrollExtent;

    final bool show =
        direction == ScrollDirection.forward ||
        (direction == ScrollDirection.idle && atTop);

    if (direction == ScrollDirection.reverse && bottomBarVisible) {
      setState(() => bottomBarVisible = false);
    } else if (show && !bottomBarVisible) {
      setState(() => bottomBarVisible = true);
    }

    return false;
  }

  // =====================================================
  // MAIN
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final bool showBottomBar = bottomBarVisible || selectedIndex != 0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,

        titleSpacing: 16,

        // หน้าหลัก: แท็บ ชุมชน | ตลาด / หน้าอื่น: ชื่อหน้า
        title: showHomeTabs
            ? buildHomeTabs()
            : Row(
                children: [
                  buildAppLogo(),

                  const SizedBox(width: 11),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        AppInfo.name,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 1),

                      Text(
                        getPageTitle(),
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

        actions: [
          if (showHomeTabs && homeSection == HomeSection.shop)
            IconButton(
              tooltip: 'บัญชีผู้ขาย',
              onPressed: openSellerAccount,
              icon: const Icon(Icons.storefront_outlined, size: 26),
            ),

          buildNotificationButton(),

          PopupMenuButton<String>(
            tooltip: 'เมนู',

            icon: const Icon(Icons.more_horiz_rounded),

            onSelected: (value) {
              if (value == 'logout') {
                logout();
              }
            },

            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: AppColors.danger),
                    SizedBox(width: 10),
                    Text('ออกจากระบบ'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(width: 5),
        ],
      ),

      body: NotificationListener<UserScrollNotification>(
        onNotification: handleUserScroll,
        child: getCurrentPage(),
      ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,

          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.06),
              blurRadius: 25,
              offset: const Offset(0, -8),
            ),
          ],
        ),

        child: SafeArea(
          top: false,

          // ซ่อนแถบด้วยการย่อความสูงลงจนเหลือ 0 (เนื้อหาด้านบนขยายลงมาแทน)
          child: ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: showBottomBar ? 1 : 0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, factor, child) {
                return Align(
                  alignment: Alignment.topCenter,
                  heightFactor: factor,
                  child: child,
                );
              },
              child: NavigationBar(
                selectedIndex: selectedIndex,

                onDestinationSelected: (index) {
                  setState(() {
                    selectedIndex = index;
                    bottomBarVisible = true;
                  });

                  loadUnreadNotificationCount();

                  if (index == 0 || index == 1 || index == 2) {
                    loadFamily(showLoading: false);
                  }
                },

                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'หน้าหลัก',
                  ),

                  NavigationDestination(
                    icon: Icon(Icons.favorite_border_rounded),
                    selectedIcon: Icon(Icons.favorite_rounded),
                    label: 'ครอบครัว',
                  ),

                  NavigationDestination(
                    icon: Icon(Icons.location_on_outlined),
                    selectedIcon: Icon(Icons.location_on_rounded),
                    label: 'ตำแหน่ง',
                  ),

                  NavigationDestination(
                    icon: Icon(Icons.event_note_outlined),
                    selectedIcon: Icon(Icons.event_note_rounded),
                    label: 'กิจกรรม',
                  ),

                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'โปรไฟล์',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // FAMILY REQUIRED
  // =====================================================

  Widget buildFamilyRequiredPage({required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 100,
              height: 100,

              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.09),

                shape: BoxShape.circle,
              ),

              child: const Icon(
                Icons.family_restroom_rounded,
                size: 46,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'เข้าร่วมวงโคจรก่อน',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 15,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 25),

            SizedBox(
              width: 230,

              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    selectedIndex = 1;
                  });

                  loadFamily();
                },

                icon: const Icon(Icons.arrow_forward_rounded),

                label: const Text('ไปหน้าครอบครัว'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // FAMILY CONTENT
  // =====================================================

  Widget buildFamilyContent() {
    if (!hasFamily) {
      return buildNoFamily();
    }

    return buildFamilyTab();
  }

  // =====================================================
  // หน้าหลัก: ชุมชน | ตลาด
  // =====================================================

  // สลับหน้าด้วยแท็บบนแถบด้านบน (buildHomeTabs)
  Widget buildHomeTab() {
    return homeSection == HomeSection.shop
        ? ShopPage(refreshToken: marketRefreshToken)
        : const FeedPage(
            key: ValueKey('feed-community'),
            scope: FeedScope.community,
          );
  }

  // =====================================================
  // ครอบครัว: โพสต์ | สมาชิก
  // =====================================================

  Widget buildFamilyTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SectionSwitch<FamilySection>(
            value: familySection,
            options: const [
              SectionOption(
                value: FamilySection.posts,
                icon: Icons.forum_rounded,
                label: 'โพสต์',
              ),
              SectionOption(
                value: FamilySection.members,
                icon: Icons.groups_rounded,
                label: 'สมาชิก',
              ),
            ],
            onChanged: (value) {
              setState(() {
                familySection = value;
              });
            },
          ),
        ),
        Expanded(
          child: familySection == FamilySection.members
              ? buildFamily()
              : const FeedPage(
                  key: ValueKey('feed-family'),
                  scope: FeedScope.family,
                ),
        ),
      ],
    );
  }

  // =====================================================
  // NO FAMILY
  // =====================================================

  Widget buildNoFamily() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 35),

      children: [
        // ===============================================
        // HERO
        // ===============================================

        Container(
          padding: const EdgeInsets.all(24),

          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF182458), Color(0xFF4F59E5)],
            ),

            borderRadius: BorderRadius.circular(28),

            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.20),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),

          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -45,

                child: Container(
                  width: 145,
                  height: 145,

                  decoration: BoxDecoration(
                    shape: BoxShape.circle,

                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,

                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),

                      borderRadius: BorderRadius.circular(18),
                    ),

                    child: const Icon(
                      Icons.track_changes_rounded,
                      color: Colors.white,
                      size: 29,
                    ),
                  ),

                  const SizedBox(height: 22),

                  Text(
                    'สวัสดี ${widget.userName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'สร้างวงโคจรใหม่ หรือเข้าร่วมครอบครัวของคุณ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.80),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 26),

        const Text(
          'เริ่มต้นครอบครัวของคุณ',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          'เลือกวิธีที่เหมาะกับคุณ',
          style: TextStyle(color: AppColors.muted),
        ),

        const SizedBox(height: 16),

        // ===============================================
        // CREATE
        // ===============================================
        Container(
          padding: const EdgeInsets.all(20),

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
                    width: 46,
                    height: 46,

                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),

                      borderRadius: BorderRadius.circular(15),
                    ),

                    child: const Icon(
                      Icons.add_home_rounded,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(width: 13),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'สร้างครอบครัว',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        SizedBox(height: 3),

                        Text(
                          'คุณจะเป็น Owner ของครอบครัว',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              TextField(
                controller: familyNameController,

                decoration: const InputDecoration(
                  labelText: 'ชื่อครอบครัว',
                  hintText: 'เช่น บ้านของเรา',
                  prefixIcon: Icon(Icons.favorite_outline_rounded),
                ),
              ),

              const SizedBox(height: 14),

              ElevatedButton.icon(
                onPressed: isWorking ? null : createFamily,

                icon: const Icon(Icons.add_rounded),

                label: Text(isWorking ? 'กำลังสร้าง...' : 'สร้างครอบครัว'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ===============================================
        // JOIN
        // ===============================================
        Container(
          padding: const EdgeInsets.all(20),

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
                    width: 46,
                    height: 46,

                    decoration: BoxDecoration(
                      color: AppColors.sky.withValues(alpha: 0.13),

                      borderRadius: BorderRadius.circular(15),
                    ),

                    child: const Icon(
                      Icons.group_add_rounded,
                      color: AppColors.sky,
                    ),
                  ),

                  const SizedBox(width: 13),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'เข้าร่วมครอบครัว',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        SizedBox(height: 3),

                        Text(
                          'ใช้ Invite Code จาก Owner',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              TextField(
                controller: inviteCodeController,

                textCapitalization: TextCapitalization.characters,

                decoration: const InputDecoration(
                  labelText: 'Invite Code',
                  hintText: 'XXXXXXXX',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
              ),

              const SizedBox(height: 14),

              OutlinedButton.icon(
                onPressed: isWorking ? null : joinFamily,

                icon: const Icon(Icons.login_rounded),

                label: const Text('เข้าร่วมครอบครัว'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =====================================================
  // FAMILY PAGE
  // =====================================================

  Widget buildFamily() {
    final family = familyData?['family'];

    if (family == null) {
      return const Center(child: Text('ไม่พบข้อมูลครอบครัว'));
    }

    final List members = family['members'] as List? ?? [];

    final String myRole = familyData?['role']?.toString() ?? 'member';

    final bool isOwner = myRole == 'owner';

    final int ownerId = (family['owner_id'] as num).toInt();

    final String familyName = family['name']?.toString() ?? 'Family';

    final String inviteCode = family['invite_code']?.toString() ?? '';

    return RefreshIndicator(
      color: AppColors.primary,

      onRefresh: () => loadFamily(showLoading: false),

      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),

        padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),

        children: [
          // ===============================================
          // FAMILY HERO CARD
          // ===============================================

          Container(
            padding: const EdgeInsets.all(23),

            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF172554),
                  Color(0xFF4650D8),
                  Color(0xFF656BFF),
                ],
              ),

              borderRadius: BorderRadius.circular(30),

              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  blurRadius: 30,
                  offset: const Offset(0, 13),
                ),
              ],
            ),

            child: Stack(
              children: [
                Positioned(
                  right: -45,
                  top: -70,

                  child: Container(
                    width: 190,
                    height: 190,

                    decoration: BoxDecoration(
                      shape: BoxShape.circle,

                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

                Positioned(
                  right: 20,
                  bottom: -55,

                  child: Container(
                    width: 120,
                    height: 120,

                    decoration: BoxDecoration(
                      shape: BoxShape.circle,

                      border: Border.all(
                        color: AppColors.sky.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  right: 42,
                  top: 29,

                  child: Container(
                    width: 10,
                    height: 10,

                    decoration: const BoxDecoration(
                      color: AppColors.sky,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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

                          child: const Text(
                            'MY ORBIT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),

                        const Spacer(),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),

                          decoration: BoxDecoration(
                            color: isOwner
                                ? AppColors.warm.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.12),

                            borderRadius: BorderRadius.circular(999),
                          ),

                          child: Row(
                            children: [
                              Icon(
                                isOwner
                                    ? Icons.workspace_premium_rounded
                                    : Icons.person_rounded,
                                color: isOwner ? AppColors.warm : Colors.white,
                                size: 14,
                              ),

                              const SizedBox(width: 5),

                              Text(
                                isOwner ? 'OWNER' : 'MEMBER',
                                style: TextStyle(
                                  color: isOwner
                                      ? AppColors.warm
                                      : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                familyName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 29,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),

                              const SizedBox(height: 8),

                              Text(
                                '${members.length} สมาชิกในวงโคจร',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.76),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (isOwner)
                          IconButton.filledTonal(
                            onPressed: editFamilyName,

                            tooltip: 'แก้ไขชื่อ',

                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.13,
                              ),
                              foregroundColor: Colors.white,
                            ),

                            icon: const Icon(Icons.edit_rounded, size: 19),
                          ),
                      ],
                    ),

                    const SizedBox(height: 25),

                    Container(
                      padding: const EdgeInsets.all(14),

                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),

                        borderRadius: BorderRadius.circular(18),

                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),

                      child: Row(
                        children: [
                          const Icon(
                            Icons.key_rounded,
                            color: AppColors.warm,
                            size: 20,
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'INVITE CODE',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.64),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),

                                const SizedBox(height: 2),

                                Text(
                                  inviteCode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          IconButton(
                            onPressed: () {
                              copyInviteCode(inviteCode);
                            },

                            tooltip: 'คัดลอก',

                            icon: const Icon(
                              Icons.content_copy_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (isOwner) ...[
                      const SizedBox(height: 12),

                      InkWell(
                        borderRadius: BorderRadius.circular(14),

                        onTap: regenerateInviteCode,

                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),

                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.refresh_rounded,
                                color: Colors.white,
                                size: 17,
                              ),

                              SizedBox(width: 7),

                              Text(
                                'สร้างรหัสเชิญใหม่',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // ===============================================
          // MEMBER HEADER
          // ===============================================
          Row(
            children: [
              const Text(
                'สมาชิกในครอบครัว',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const Spacer(),

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
                  '${members.length} คน',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          const Text(
            'คนสำคัญที่อยู่ในวงโคจรเดียวกับคุณ',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),

          const SizedBox(height: 14),

          // ===============================================
          // MEMBERS
          // ===============================================
          ...members.map((dynamic member) {
            final int memberId = (member['id'] as num).toInt();

            final bool memberIsOwner = memberId == ownerId;

            final String memberName = member['name']?.toString() ?? 'สมาชิก';

            final String email = member['email']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),

              padding: const EdgeInsets.fromLTRB(15, 13, 10, 13),

              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.circular(20),

                border: Border.all(color: AppColors.border),
              ),

              child: Row(
                children: [
                  buildMemberAvatar(
                    name: memberName,
                    isOwner: memberIsOwner,
                    imageUrl: getMemberProfileImage(member),
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                memberName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.navy,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),

                            if (memberIsOwner) ...[
                              const SizedBox(width: 7),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),

                                decoration: BoxDecoration(
                                  color: AppColors.warm.withValues(alpha: 0.14),

                                  borderRadius: BorderRadius.circular(999),
                                ),

                                child: const Text(
                                  'OWNER',
                                  style: TextStyle(
                                    color: Color(0xFFCF762F),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 3),

                        Text(
                          email,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (isOwner && !memberIsOwner)
                    PopupMenuButton<String>(
                      tooltip: 'จัดการสมาชิก',

                      onSelected: (value) {
                        if (value == 'owner') {
                          transferFamilyOwner(memberId, memberName);
                        }

                        if (value == 'remove') {
                          removeFamilyMember(memberId, memberName);
                        }
                      },

                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'owner',
                          child: Row(
                            children: [
                              Icon(
                                Icons.workspace_premium_rounded,
                                color: AppColors.warm,
                              ),

                              SizedBox(width: 10),

                              Text('ตั้งเป็น Owner'),
                            ],
                          ),
                        ),

                        PopupMenuItem(
                          value: 'remove',
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_remove_rounded,
                                color: AppColors.danger,
                              ),

                              SizedBox(width: 10),

                              Text('นำออกจากครอบครัว'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          }),

          const SizedBox(height: 22),

          // ===============================================
          // MEMBER LEAVE
          // ===============================================
          if (!isOwner)
            Container(
              padding: const EdgeInsets.all(18),

              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.circular(22),

                border: Border.all(color: AppColors.border),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'การเป็นสมาชิก',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 5),

                  const Text(
                    'คุณสามารถออกจากครอบครัวนี้ได้ทุกเมื่อ',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),

                  const SizedBox(height: 15),

                  OutlinedButton.icon(
                    onPressed: leaveFamily,

                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,

                      side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.35),
                      ),
                    ),

                    icon: const Icon(Icons.logout_rounded),

                    label: const Text('ออกจากครอบครัว'),
                  ),
                ],
              ),
            ),

          // ===============================================
          // OWNER DANGER ZONE
          // ===============================================
          if (isOwner) ...[
            Container(
              padding: const EdgeInsets.all(18),

              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.045),

                borderRadius: BorderRadius.circular(22),

                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.18),
                ),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: AppColors.danger),

                      SizedBox(width: 9),

                      Text(
                        'Owner Zone',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 7),

                  const Text(
                    'คุณเป็นผู้ดูแลครอบครัวนี้ '
                    'หากต้องการออก กรุณาโอน Owner ให้สมาชิกคนอื่นก่อน',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: 16),

                  OutlinedButton.icon(
                    onPressed: deleteCurrentFamily,

                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,

                      side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.35),
                      ),
                    ),

                    icon: const Icon(Icons.delete_outline_rounded),

                    label: const Text('ลบครอบครัว'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =====================================================
  // DISPOSE
  // =====================================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    familyNameController.dispose();
    inviteCodeController.dispose();

    super.dispose();
  }
}
