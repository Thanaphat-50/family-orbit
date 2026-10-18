import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import 'login_page.dart';

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
  // PASSWORD
  // =====================================================

  Future<void> changePassword() async {
    String currentPassword = '';

    String newPassword = '';

    String confirmation = '';

    bool hideCurrent = true;
    bool hideNew = true;
    bool hideConfirm = true;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,

      isScrollControlled: true,

      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  15,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 25,
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [
                    const Text(
                      'เปลี่ยนรหัสผ่าน',

                      style: TextStyle(
                        color: AppColors.navy,

                        fontSize: 21,

                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร',

                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),

                    const SizedBox(height: 22),

                    TextField(
                      obscureText: hideCurrent,

                      onChanged: (value) {
                        currentPassword = value;
                      },

                      decoration: InputDecoration(
                        labelText: 'รหัสผ่านปัจจุบัน',

                        prefixIcon: const Icon(Icons.lock_outline_rounded),

                        suffixIcon: IconButton(
                          onPressed: () {
                            setSheetState(() {
                              hideCurrent = !hideCurrent;
                            });
                          },

                          icon: Icon(
                            hideCurrent
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      obscureText: hideNew,

                      onChanged: (value) {
                        newPassword = value;
                      },

                      decoration: InputDecoration(
                        labelText: 'รหัสผ่านใหม่',

                        prefixIcon: const Icon(Icons.key_rounded),

                        suffixIcon: IconButton(
                          onPressed: () {
                            setSheetState(() {
                              hideNew = !hideNew;
                            });
                          },

                          icon: Icon(
                            hideNew
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      obscureText: hideConfirm,

                      onChanged: (value) {
                        confirmation = value;
                      },

                      decoration: InputDecoration(
                        labelText: 'ยืนยันรหัสผ่านใหม่',

                        prefixIcon: const Icon(Icons.verified_user_outlined),

                        suffixIcon: IconButton(
                          onPressed: () {
                            setSheetState(() {
                              hideConfirm = !hideConfirm;
                            });
                          },

                          icon: Icon(
                            hideConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    FilledButton(
                      onPressed: () {
                        if (currentPassword.isEmpty ||
                            newPassword.length < 8 ||
                            newPassword != confirmation) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('กรุณาตรวจสอบข้อมูลรหัสผ่าน'),
                            ),
                          );

                          return;
                        }

                        Navigator.of(sheetContext).pop({
                          'current': currentPassword,

                          'password': newPassword,

                          'confirmation': confirmation,
                        });
                      },

                      child: const Text('เปลี่ยนรหัสผ่าน'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));

    try {
      final response = await ProfileService.updatePassword(
        currentPassword: result['current']!,

        password: result['password']!,

        passwordConfirmation: result['confirmation']!,
      );

      if (!mounted) return;

      showMessage(
        response['message'] ??
            (response['status'] == true
                ? 'เปลี่ยนรหัสผ่านแล้ว'
                : 'เปลี่ยนรหัสผ่านไม่สำเร็จ'),
      );
    } catch (e) {
      if (!mounted) return;

      showMessage('เปลี่ยนรหัสผ่านไม่สำเร็จ');
    }
  }

  // =====================================================
  // DELETE ACCOUNT
  // ลบบัญชีและข้อมูลทั้งหมด (ยืนยันด้วยรหัสผ่าน)
  // =====================================================

  Future<void> deleteAccount() async {
    String password = '';

    bool hidePassword = true;
    bool confirmed = false;

    final String? result = await showModalBottomSheet<String>(
      context: context,

      isScrollControlled: true,

      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  15,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 25,
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [
                    const Text(
                      'ลบบัญชี',

                      style: TextStyle(
                        color: AppColors.danger,

                        fontSize: 21,

                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'ข้อมูลต่อไปนี้จะถูกลบถาวร และกู้คืนไม่ได้\n'
                      '• บัญชีและรูปโปรไฟล์\n'
                      '• การเป็นสมาชิกครอบครัวและตำแหน่ง\n'
                      '• โพสต์ ความคิดเห็น และกิจกรรมทั้งหมด',

                      style: TextStyle(
                        color: AppColors.muted,

                        fontSize: 13,

                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 20),

                    TextField(
                      obscureText: hidePassword,

                      onChanged: (value) {
                        password = value;
                      },

                      decoration: InputDecoration(
                        labelText: 'ยืนยันด้วยรหัสผ่าน',

                        prefixIcon: const Icon(Icons.lock_outline_rounded),

                        suffixIcon: IconButton(
                          onPressed: () {
                            setSheetState(() {
                              hidePassword = !hidePassword;
                            });
                          },

                          icon: Icon(
                            hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    CheckboxListTile(
                      value: confirmed,

                      contentPadding: EdgeInsets.zero,

                      controlAffinity: ListTileControlAffinity.leading,

                      activeColor: AppColors.danger,

                      title: const Text(
                        'ฉันเข้าใจว่าข้อมูลทั้งหมดจะถูกลบถาวร',

                        style: TextStyle(
                          color: AppColors.navy,

                          fontSize: 13,

                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      onChanged: (value) {
                        setSheetState(() {
                          confirmed = value ?? false;
                        });
                      },
                    ),

                    const SizedBox(height: 14),

                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,

                        disabledBackgroundColor:
                            AppColors.danger.withValues(alpha: 0.35),

                        disabledForegroundColor: Colors.white,

                        minimumSize: const Size(double.infinity, 52),
                      ),

                      onPressed: confirmed
                          ? () {
                              if (password.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('กรุณากรอกรหัสผ่าน'),
                                  ),
                                );

                                return;
                              }

                              Navigator.of(sheetContext).pop(password);
                            }
                          : null,

                      child: const Text('ลบบัญชีถาวร'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));

    try {
      final response = await ProfileService.deleteAccount(
        password: result,
      );

      if (!mounted) return;

      if (response['status'] != true) {
        showMessage(response['message'] ?? 'ลบบัญชีไม่สำเร็จ');
        return;
      }

      // บัญชีถูกลบแล้ว → ล้าง Token ในเครื่อง แล้วกลับหน้า Login
      await AuthService.clearToken();

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response['message'] ?? 'ลบบัญชีเรียบร้อยแล้ว',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    }
  }

  // =====================================================
  // LOGOUT
  // =====================================================

  Future<void> logout() async {
    try {
      await AuthService.logout();
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
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
            'Family Orbit',

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
            'ความปลอดภัย',

            style: TextStyle(
              color: AppColors.navy,

              fontSize: 17,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 10),

          buildSettingTile(
            icon: Icons.password_rounded,

            title: 'เปลี่ยนรหัสผ่าน',

            subtitle: 'อัปเดตรหัสผ่านสำหรับบัญชีนี้',

            color: AppColors.warm,

            onTap: changePassword,
          ),

          const SizedBox(height: 23),

          buildSettingTile(
            icon: Icons.logout_rounded,

            title: 'ออกจากระบบ',

            subtitle: 'ออกจากบัญชี Family Orbit',

            color: AppColors.danger,

            danger: true,

            onTap: logout,
          ),

          const SizedBox(height: 10),

          buildSettingTile(
            icon: Icons.delete_forever_rounded,

            title: 'ลบบัญชี',

            subtitle: 'ลบบัญชีและข้อมูลทั้งหมดถาวร',

            color: AppColors.danger,

            danger: true,

            onTap: deleteAccount,
          ),
        ],
      ),
    );
  }
}
