import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/market_data.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_intro.dart';
import 'edit_profile_page.dart';
import 'feed_page.dart';
import 'my_shop_page.dart';
import 'settings_page.dart';
import 'user_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _imagePicker = ImagePicker();

  bool isLoading = true;
  bool isUploadingPhoto = false;

  Map<String, dynamic> profileData = {};

  // =====================================================
  // INIT
  // =====================================================

  @override
  void initState() {
    super.initState();

    loadProfile();
  }

  // =====================================================
  // LOAD PROFILE
  // =====================================================

  Future<void> loadProfile() async {
    try {
      final result = await ProfileService.getProfile();

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          profileData = Map<String, dynamic>.from(result);
        });
      } else {
        showMessage(result['message'] ?? 'โหลดข้อมูลโปรไฟล์ไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('โหลดข้อมูลโปรไฟล์ไม่สำเร็จ');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // =====================================================
  // USER
  // =====================================================

  Map<String, dynamic> get user {
    final value = profileData['user'];

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return {};
  }

  Map<String, dynamic>? get family {
    final value = profileData['family'];

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  String get userName {
    return user['name']?.toString() ?? 'ผู้ใช้งาน';
  }

  String get email {
    return user['email']?.toString() ?? '';
  }

  String get familyName {
    return family?['name']?.toString() ?? 'ยังไม่มีครอบครัว';
  }

  String get role {
    final value = profileData['role']?.toString();

    if (value == 'owner') {
      return 'เจ้าของครอบครัว';
    }

    if (value == 'member') {
      return 'สมาชิก';
    }

    return 'ยังไม่มีบทบาท';
  }

  String? get photoUrl {
    final value = user['profile_photo_url'];

    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  bool get hasPhoto => photoUrl != null;

  int? get userId {
    final dynamic value = user['id'];

    return value is num ? value.toInt() : null;
  }

  // ตัวเลขจาก /api/profile (posts, likes_received)
  int stat(String key) {
    final dynamic stats = profileData['stats'];

    final dynamic value = stats is Map ? stats[key] : null;

    return value is num ? value.toInt() : 0;
  }

  // =====================================================
  // เปิดหน้าอื่น
  // =====================================================

  Map<String, String> get intro => introFrom(user['intro']);

  Future<void> openEditProfile() async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => EditProfilePage(name: userName, intro: intro),
      ),
    );

    if (saved == true && mounted) loadProfile();
  }

  void openPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
  }

  void openPublicProfile() {
    final int? id = userId;

    if (id == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserProfilePage(userId: id, name: userName),
      ),
    );
  }

  String get initial {
    final name = userName.trim();

    if (name.isEmpty) {
      return '?';
    }

    return name.substring(0, 1).toUpperCase();
  }

  // =====================================================
  // PHOTO MENU
  // =====================================================

  Future<void> showPhotoMenu() async {
    await showModalBottomSheet<void>(
      context: context,

      showDragHandle: true,

      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 5, 18, 25),

            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                Text(
                  'รูปโปรไฟล์',

                  style: TextStyle(
                    color: AppColors.navy,

                    fontSize: 20,

                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'เลือกรูปที่ต้องการใช้เป็นรูปบัญชี',

                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),

                const SizedBox(height: 20),

                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.photo_library_outlined),
                  ),

                  title: const Text('เลือกรูปจาก Gallery'),

                  subtitle: const Text('รองรับ JPG, PNG และ WEBP'),

                  onTap: () {
                    Navigator.of(sheetContext).pop();

                    pickPhoto();
                  },
                ),

                if (hasPhoto)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.softDanger,

                      child: Icon(
                        Icons.delete_outline_rounded,

                        color: AppColors.danger,
                      ),
                    ),

                    title: Text(
                      'ลบรูปโปรไฟล์',

                      style: TextStyle(color: AppColors.danger),
                    ),

                    subtitle: const Text('กลับไปใช้ตัวอักษรแทนรูป'),

                    onTap: () {
                      Navigator.of(sheetContext).pop();

                      deletePhoto();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =====================================================
  // PICK PHOTO
  // =====================================================

  Future<void> pickPhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,

        imageQuality: 85,

        maxWidth: 1600,
      );

      if (image == null || !mounted) {
        return;
      }

      setState(() {
        isUploadingPhoto = true;
      });

      final result = await ProfileService.uploadProfilePhoto(image.path);

      if (!mounted) return;

      if (result['status'] == true) {
        await loadProfile();

        if (!mounted) return;

        showMessage('เปลี่ยนรูปโปรไฟล์เรียบร้อยแล้ว');
      } else {
        showMessage(result['message'] ?? 'อัปโหลดรูปไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('อัปโหลดรูปไม่สำเร็จ: $e');
    } finally {
      if (mounted) {
        setState(() {
          isUploadingPhoto = false;
        });
      }
    }
  }

  // =====================================================
  // DELETE PHOTO
  // =====================================================

  Future<void> deletePhoto() async {
    final confirm = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.delete_outline_rounded,

            color: AppColors.danger,

            size: 38,
          ),

          title: const Text('ลบรูปโปรไฟล์?'),

          content: const Text(
            'รูปปัจจุบันจะถูกลบ และบัญชีจะกลับไปใช้ตัวอักษรแทนรูป',
          ),

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

              child: const Text('ลบรูป'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));

    setState(() {
      isUploadingPhoto = true;
    });

    try {
      final result = await ProfileService.deleteProfilePhoto();

      if (!mounted) return;

      if (result['status'] == true) {
        await loadProfile();

        if (!mounted) return;

        showMessage('ลบรูปโปรไฟล์เรียบร้อยแล้ว');
      } else {
        showMessage(result['message'] ?? 'ลบรูปไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('ลบรูปไม่สำเร็จ: $e');
    } finally {
      if (mounted) {
        setState(() {
          isUploadingPhoto = false;
        });
      }
    }
  }

  // =====================================================
  // AVATAR
  // =====================================================

  Widget buildAvatar() {
    final url = photoUrl;

    return Stack(
      clipBehavior: Clip.none,

      children: [
        Container(
          width: 112,
          height: 112,

          padding: const EdgeInsets.all(4),

          decoration: BoxDecoration(
            shape: BoxShape.circle,

            gradient: LinearGradient(
              begin: Alignment.topLeft,

              end: Alignment.bottomRight,

              colors: [AppColors.sky, AppColors.primary],
            ),
          ),

          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,

              shape: BoxShape.circle,
            ),

            padding: const EdgeInsets.all(3),

            child: ClipOval(
              child: url != null
                  ? Image.network(
                      url,

                      width: 100,

                      height: 100,

                      fit: BoxFit.cover,

                      errorBuilder: (context, error, stackTrace) {
                        return buildInitialAvatar();
                      },
                    )
                  : buildInitialAvatar(),
            ),
          ),
        ),

        Positioned(
          right: -2,
          bottom: 3,

          child: Material(
            color: AppColors.primary,

            shape: const CircleBorder(),

            elevation: 4,

            child: InkWell(
              customBorder: const CircleBorder(),

              onTap: isUploadingPhoto ? null : showPhotoMenu,

              child: SizedBox(
                width: 37,
                height: 37,

                child: isUploadingPhoto
                    ? const Padding(
                        padding: EdgeInsets.all(10),

                        child: CircularProgressIndicator(
                          color: Colors.white,

                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.photo_camera_rounded,

                        color: Colors.white,

                        size: 18,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildInitialAvatar() {
    return Container(
      color: AppColors.softPrimary,

      alignment: Alignment.center,

      child: Text(
        initial,

        style: TextStyle(
          color: AppColors.primary,

          fontSize: 38,

          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // =====================================================
  // HEADER
  // =====================================================

  Widget buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

          colors: [Color(0xFF172554), Color(0xFF4650D8), Color(0xFF666CFF)],
        ),

        borderRadius: BorderRadius.circular(28),
      ),

      child: Column(
        children: [
          buildAvatar(),

          const SizedBox(height: 15),

          Text(
            userName,

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: Colors.white,

              fontSize: 22,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            email,

            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),

              fontSize: 11,
            ),
          ),

          const SizedBox(height: 14),

          // ครอบครัว + บทบาท
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),

            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),

              borderRadius: BorderRadius.circular(99),
            ),

            child: Row(
              mainAxisSize: MainAxisSize.min,

              children: [
                const Icon(
                  Icons.family_restroom_rounded,

                  color: Colors.white,

                  size: 15,
                ),

                const SizedBox(width: 6),

                Flexible(
                  child: Text(
                    family == null ? familyName : '$familyName · $role',

                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      color: Colors.white,

                      fontSize: 12,

                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: buildHeaderStat(
                  value: stat('posts'),

                  label: 'โพสต์',
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: buildHeaderStat(
                  value: stat('likes_received'),

                  label: 'ถูกใจที่ได้รับ',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // กล่องตัวเลขในหัวโปรไฟล์
  Widget buildHeaderStat({required int value, required String label}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),

      borderRadius: BorderRadius.circular(16),

      child: InkWell(
        borderRadius: BorderRadius.circular(16),

        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),

          child: Column(
            children: [
              Text(
                '$value',

                style: const TextStyle(
                  color: Colors.white,

                  fontSize: 20,

                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 1),

              Text(
                label,

                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),

                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // ทางลัด (บัญชีผู้ขาย / ตั้งค่า)
  // =====================================================

  Widget buildShortcut({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ส่วนบนของหน้า (ต่อด้วยรายการโพสต์ของฉัน)
  Widget buildPageHeader() {
    if (isLoading) {
      return const SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildProfileHeader(),
        const SizedBox(height: 14),
        ProfileIntroCard(intro: intro, onEdit: openEditProfile),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: openEditProfile,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('แก้ไขโปรไฟล์'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: openPublicProfile,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('มุมมองคนอื่น'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: buildShortcut(
                icon: Icons.storefront_outlined,
                label: 'บัญชีผู้ขาย',
                color: marketColor,
                onTap: () => openPage(const MyShopPage()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: buildShortcut(
                icon: Icons.settings_outlined,
                label: 'ตั้งค่า',
                color: AppColors.muted,
                onTap: () => openPage(const SettingsPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'โพสต์ของฉัน',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
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
  // UI
  // โปรไฟล์ + แนะนำตัว แล้วต่อด้วยโพสต์ทั้งหมดของเรา (ครอบครัว + ชุมชน)
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return FeedPage(
      scope: FeedScope.mine,
      header: buildPageHeader(),
      onRefresh: loadProfile,
    );
  }
}
