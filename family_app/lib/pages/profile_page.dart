import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/market_data.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import 'my_shop_page.dart';
import 'settings_page.dart';

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
                const Text(
                  'รูปโปรไฟล์',

                  style: TextStyle(
                    color: AppColors.navy,

                    fontSize: 20,

                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 5),

                const Text(
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
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFFEEEE),

                      child: Icon(
                        Icons.delete_outline_rounded,

                        color: AppColors.danger,
                      ),
                    ),

                    title: const Text(
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
          icon: const Icon(
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
  // EDIT NAME
  // =====================================================

  Future<void> editName() async {
    String name = userName;

    final result = await showDialog<String>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('แก้ไขชื่อ'),

          content: TextFormField(
            initialValue: userName,

            autofocus: true,

            textInputAction: TextInputAction.done,

            onChanged: (value) {
              name = value;
            },

            decoration: const InputDecoration(labelText: 'ชื่อที่แสดง'),
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
                final clean = name.trim();

                if (clean.isEmpty) {
                  return;
                }

                Navigator.of(dialogContext).pop(clean);
              },

              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));

    try {
      final response = await ProfileService.updateProfile(name: result);

      if (!mounted) return;

      if (response['status'] == true) {
        await loadProfile();

        if (!mounted) return;

        showMessage('แก้ไขชื่อเรียบร้อยแล้ว');
      } else {
        showMessage(response['message'] ?? 'แก้ไขชื่อไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('แก้ไขชื่อไม่สำเร็จ');
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

          decoration: const BoxDecoration(
            shape: BoxShape.circle,

            gradient: LinearGradient(
              begin: Alignment.topLeft,

              end: Alignment.bottomRight,

              colors: [AppColors.sky, AppColors.primary],
            ),
          ),

          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,

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
      color: const Color(0xFFEEF0FF),

      alignment: Alignment.center,

      child: Text(
        initial,

        style: const TextStyle(
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
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 25),

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

          const SizedBox(height: 17),

          Text(
            userName,

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: Colors.white,

              fontSize: 22,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            email,

            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),

              fontSize: 11,
            ),
          ),

          const SizedBox(height: 17),

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
                    familyName,

                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      color: Colors.white,

                      fontSize: 10,

                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SETTING CARD
  // =====================================================

  Widget buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color color = AppColors.primary,
    bool danger = false,
  }) {
    return Material(
      color: Colors.white,

      borderRadius: BorderRadius.circular(18),

      child: InkWell(
        borderRadius: BorderRadius.circular(18),

        onTap: onTap,

        child: Padding(
          padding: const EdgeInsets.all(14),

          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,

                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.09),

                  borderRadius: BorderRadius.circular(14),
                ),

                child: Icon(icon, color: color, size: 21),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      title,

                      style: TextStyle(
                        color: danger ? AppColors.danger : AppColors.navy,

                        fontWeight: FontWeight.w700,

                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      subtitle,

                      style: const TextStyle(
                        color: AppColors.muted,

                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
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
  // =====================================================

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: loadProfile,

      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),

        padding: const EdgeInsets.fromLTRB(17, 12, 17, 110),

        children: [
          buildProfileHeader(),

          const SizedBox(height: 25),

          const Text(
            'บัญชี',

            style: TextStyle(
              color: AppColors.navy,

              fontSize: 17,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 10),

          buildSettingTile(
            icon: Icons.photo_camera_outlined,

            title: 'รูปโปรไฟล์',

            subtitle: hasPhoto
                ? 'เปลี่ยนหรือลบรูปปัจจุบัน'
                : 'เพิ่มรูปให้บัญชีของคุณ',

            onTap: showPhotoMenu,
          ),

          const SizedBox(height: 9),

          buildSettingTile(
            icon: Icons.edit_outlined,

            title: 'ชื่อที่แสดง',

            subtitle: userName,

            onTap: editName,
          ),

          const SizedBox(height: 23),

          const Text(
            'ครอบครัว',

            style: TextStyle(
              color: AppColors.navy,

              fontSize: 17,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 10),

          buildSettingTile(
            icon: Icons.family_restroom_rounded,

            title: familyName,

            subtitle: role,

            color: AppColors.sky,

            onTap: () {
              showMessage(
                family == null ? 'ยังไม่ได้เข้าร่วมครอบครัว' : 'คุณเป็น $role',
              );
            },
          ),

          const SizedBox(height: 23),

          const Text(
            'ตลาด',

            style: TextStyle(
              color: AppColors.navy,

              fontSize: 17,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 10),

          buildSettingTile(
            icon: Icons.storefront_outlined,

            title: 'บัญชีผู้ขาย',

            subtitle: 'เปิดร้าน จัดการสินค้า และดูสถานะร้าน',

            color: marketColor,

            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const MyShopPage()),
              );
            },
          ),

          const SizedBox(height: 23),

          // แจ้งเตือน ตำแหน่ง ความเป็นส่วนตัว รหัสผ่าน ออกจากระบบ ลบบัญชี
          buildSettingTile(
            icon: Icons.settings_outlined,

            title: 'ตั้งค่า',

            subtitle: 'การแจ้งเตือน ตำแหน่ง บัญชี และความเป็นส่วนตัว',

            color: AppColors.muted,

            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
