import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_info.dart';
import '../services/auth_service.dart';
import '../services/location_tracker.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../services/social_auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/community_sheets.dart';
import 'login_page.dart';

// =======================================================
// ตั้งค่า
// - การแจ้งเตือน: เปิด/ปิดแต่ละประเภท
// - ตำแหน่ง: แชร์ตำแหน่งกับครอบครัว
// - ความเป็นส่วนตัว: ผู้ใช้ที่บล็อก
// - บัญชี: เปลี่ยนรหัสผ่าน / ออกจากระบบ / ลบบัญชี
// - เกี่ยวกับแอป: นโยบาย และเวอร์ชัน
// =======================================================

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ประเภทการแจ้งเตือนที่ปิดได้ (ตรงกับ AppNotification::OPTIONAL_TYPES)
  static const List<_NotificationOption> notificationOptions = [
    _NotificationOption(
      type: 'new_post',
      title: 'โพสต์ใหม่ในครอบครัว',
      icon: Icons.dynamic_feed_rounded,
    ),
    _NotificationOption(
      type: 'new_comment',
      title: 'ความคิดเห็นในโพสต์ของฉัน',
      icon: Icons.chat_bubble_outline_rounded,
    ),
    _NotificationOption(
      type: 'new_activity',
      title: 'กิจกรรมใหม่ในครอบครัว',
      icon: Icons.event_available_rounded,
    ),
    _NotificationOption(
      type: 'member_joined',
      title: 'มีสมาชิกใหม่เข้าครอบครัว',
      icon: Icons.person_add_alt_1_rounded,
    ),
    _NotificationOption(
      type: 'new_message',
      title: 'ข้อความแชท',
      icon: Icons.forum_outlined,
    ),
  ];

  bool isLoading = true;
  String? loadError;

  bool locationSharing = true;
  Map<String, bool> notifications = {};

  // ค่าที่กำลังบันทึก (กันกดซ้ำ)
  final Set<String> savingKeys = {};

  String version = '';

  // บัญชี Google / LINE / Facebook ที่เชื่อมไว้ + มีรหัสผ่านหรือยัง
  List<Map<String, dynamic>> socialAccounts = [];

  bool hasPassword = true;

  // เจ้าที่กำลังเชื่อม / ยกเลิก
  String? socialBusy;

  @override
  void initState() {
    super.initState();
    loadSettings();
    loadVersion();
    loadSocialAccounts();
  }

  // =====================================================
  // บัญชีที่เชื่อมต่อ (Google / LINE / Facebook)
  // =====================================================

  void applySocialAccounts(Map<String, dynamic> result) {
    final dynamic accounts = result['accounts'];

    if (result['status'] != true || accounts is! List) return;

    setState(() {
      hasPassword = result['has_password'] != false;

      socialAccounts = accounts
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    });
  }

  Future<void> loadSocialAccounts() async {
    try {
      final result = await SocialAuthService.linkedAccounts();

      if (mounted) applySocialAccounts(result);
    } catch (_) {
      // โหลดไม่ได้ → ไม่แสดงส่วนนี้
    }
  }

  Future<void> toggleSocial(Map<String, dynamic> account) async {
    final SocialProvider provider = SocialProvider.values.firstWhere(
      (value) => value.key == account['provider'],
    );

    final bool linked = account['linked'] == true;

    if (linked) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('ยกเลิกการเชื่อม ${provider.label}?'),
          content: Text(
            'จะเข้าสู่ระบบด้วย ${provider.label} ไม่ได้อีก จนกว่าจะเชื่อมใหม่',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ไม่ใช่ตอนนี้'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ยกเลิกการเชื่อม'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;
    }

    setState(() => socialBusy = provider.key);

    try {
      final result = linked
          ? await SocialAuthService.unlink(provider)
          : await SocialAuthService.link(provider);

      if (!mounted) return;

      applySocialAccounts(result);

      showMessage(
        result['message']?.toString() ??
            (result['status'] == true ? 'บันทึกแล้ว' : 'ทำรายการไม่สำเร็จ'),
      );
    } on SocialLoginCanceled {
      // ผู้ใช้ปิดหน้าล็อกอินเอง
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => socialBusy = null);
    }
  }

  Widget buildSocialRow(Map<String, dynamic> account) {
    final bool linked = account['linked'] == true;

    final bool busy = socialBusy == account['provider'];

    final String? email = account['email']?.toString();

    final Color color = switch (account['provider']) {
      'line' => const Color(0xFF06C755),
      'facebook' => const Color(0xFF1877F2),
      _ => const Color(0xFF4285F4),
    };

    return ListTile(
      leading: buildIcon(
        linked ? Icons.link_rounded : Icons.link_off_rounded,
        color,
      ),
      contentPadding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
      title: Text(
        account['label']?.toString() ?? '',
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        linked
            ? (email == null || email.isEmpty
                  ? 'เชื่อมแล้ว'
                  : 'เชื่อมแล้ว · $email')
            : 'ยังไม่ได้เชื่อม',
        style: TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      trailing: busy
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : TextButton(
              onPressed: socialBusy == null
                  ? () => toggleSocial(account)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: linked ? AppColors.danger : AppColors.primary,
              ),
              child: Text(linked ? 'ยกเลิก' : 'เชื่อม'),
            ),
    );
  }

  // แสดงเฉพาะเจ้าที่เปิดใช้ หรือที่เคยเชื่อมไว้
  List<Map<String, dynamic>> get visibleSocialAccounts => socialAccounts
      .where(
        (account) => account['enabled'] == true || account['linked'] == true,
      )
      .toList();

  // =====================================================
  // โหลด / บันทึกการตั้งค่า
  // =====================================================

  Future<void> loadSettings() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final result = await SettingsService.getSettings();

      if (!mounted) return;

      final dynamic settings = result['settings'];

      if (result['status'] == true && settings is Map) {
        final dynamic rawNotifications = settings['notifications'];

        setState(() {
          locationSharing = settings['location_sharing'] != false;

          notifications = {
            for (final option in notificationOptions)
              option.type: rawNotifications is Map
                  ? rawNotifications[option.type] != false
                  : true,
          };
        });
      } else {
        setState(() {
          loadError =
              result['message']?.toString() ?? 'โหลดการตั้งค่าไม่สำเร็จ';
        });
      }
    } catch (e) {
      if (mounted) setState(() => loadError = e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();

      if (mounted) {
        setState(() {
          version = '${info.version} (${info.buildNumber})';
        });
      }
    } catch (_) {
      // อ่านเวอร์ชันไม่ได้ → ไม่แสดง
    }
  }

  // เปิด/ปิดการแจ้งเตือน: เปลี่ยนบนจอทันที ถ้าบันทึกไม่สำเร็จค่อยคืนค่าเดิม
  Future<void> setNotification(String type, bool enabled) async {
    if (savingKeys.contains(type)) return;

    final bool previous = notifications[type] ?? true;

    setState(() {
      notifications[type] = enabled;
      savingKeys.add(type);
    });

    try {
      final result = await SettingsService.updateSettings(
        notifications: {type: enabled},
      );

      if (!mounted) return;

      if (result['status'] != true) {
        setState(() => notifications[type] = previous);
        showMessage(result['message']?.toString() ?? 'บันทึกไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => notifications[type] = previous);
      showMessage(e.toString());
    } finally {
      if (mounted) setState(() => savingKeys.remove(type));
    }
  }

  Future<void> setLocationSharing(bool enabled) async {
    const String key = 'location_sharing';

    if (savingKeys.contains(key)) return;

    // ปิดแชร์ → ยืนยันก่อน เพราะครอบครัวจะไม่เห็นตำแหน่งของเรา
    if (!enabled) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('ปิดการแชร์ตำแหน่ง?'),
            content: const Text(
              'ครอบครัวจะไม่เห็นตำแหน่งของคุณ และตำแหน่งล่าสุดที่บันทึกไว้จะถูกลบ '
              'เปิดกลับได้ทุกเมื่อ',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('ปิดการแชร์'),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !mounted) return;
    }

    final bool previous = locationSharing;

    setState(() {
      locationSharing = enabled;
      savingKeys.add(key);
    });

    try {
      final result = await SettingsService.updateSettings(
        locationSharing: enabled,
      );

      if (!mounted) return;

      if (result['status'] != true) {
        setState(() => locationSharing = previous);
        showMessage(result['message']?.toString() ?? 'บันทึกไม่สำเร็จ');
        return;
      }

      if (enabled) {
        await startSharingWithPermission();
      } else {
        LocationTracker.stop();
        showMessage('ปิดการแชร์ตำแหน่งแล้ว');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => locationSharing = previous);
      showMessage(e.toString());
    } finally {
      if (mounted) setState(() => savingKeys.remove(key));
    }
  }

  // เปิดแชร์แล้ว → ขอสิทธิ์ตำแหน่ง (ถ้ายังไม่ได้ให้) แล้วเริ่มส่ง
  Future<void> startSharingWithPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      showMessage('เปิดแชร์แล้ว แต่ยังไม่ได้อนุญาตตำแหน่งในเครื่อง');
      return;
    }

    await LocationTracker.start();

    if (mounted) showMessage('เปิดการแชร์ตำแหน่งแล้ว');
  }

  Future<void> openBlockedUsers() async {
    await showBlockedUsersSheet(context, onChanged: () {});
  }

  Future<void> openPolicy(String url) async {
    final bool opened = await AppInfo.openUrl(url);

    if (!opened) showMessage('เปิดหน้าเว็บไม่สำเร็จ: $url');
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
                    Text(
                      hasPassword ? 'เปลี่ยนรหัสผ่าน' : 'ตั้งรหัสผ่าน',

                      style: TextStyle(
                        color: AppColors.navy,

                        fontSize: 21,

                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      hasPassword ? 'รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร' : 'ตั้งรหัสผ่านเพื่อเข้าสู่ระบบด้วยอีเมลได้ด้วย (อย่างน้อย 8 ตัวอักษร)',

                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),

                    const SizedBox(height: 22),

                    if (hasPassword) ...[
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
                    ],

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
                        if ((hasPassword && currentPassword.isEmpty) ||
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

                      child: Text(
                        hasPassword ? 'เปลี่ยนรหัสผ่าน' : 'ตั้งรหัสผ่าน',
                      ),
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
        currentPassword: hasPassword ? result['current'] : null,

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

      if (response['status'] == true) loadSocialAccounts();
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
                    Text(
                      'ลบบัญชี',

                      style: TextStyle(
                        color: AppColors.danger,

                        fontSize: 21,

                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'ข้อมูลต่อไปนี้จะถูกลบถาวร และกู้คืนไม่ได้\n'
                      '• บัญชีและรูปโปรไฟล์\n'
                      '• การเป็นสมาชิกครอบครัวและตำแหน่ง\n'
                      '• โพสต์ ความคิดเห็น และกิจกรรมทั้งหมด\n'
                      '• ร้านค้า สินค้า และรูปทั้งหมด',

                      style: TextStyle(
                        color: AppColors.muted,

                        fontSize: 13,

                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 20),

                    TextField(
                      obscureText: hasPassword && hidePassword,

                      onChanged: (value) {
                        password = value;
                      },

                      decoration: InputDecoration(
                        // ไม่มีรหัสผ่าน (สมัครด้วย Google / LINE / Facebook) → พิมพ์ "ลบบัญชี"
                        labelText: hasPassword
                            ? 'ยืนยันด้วยรหัสผ่าน'
                            : 'พิมพ์คำว่า "ลบบัญชี" เพื่อยืนยัน',

                        prefixIcon: const Icon(Icons.lock_outline_rounded),

                        suffixIcon: !hasPassword
                            ? null
                            : IconButton(
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

                      title: Text(
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

                        disabledBackgroundColor: AppColors.danger.withValues(
                          alpha: 0.35,
                        ),

                        disabledForegroundColor: Colors.white,

                        minimumSize: const Size(double.infinity, 52),
                      ),

                      onPressed: confirmed
                          ? () {
                              if (password.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      hasPassword
                                          ? 'กรุณากรอกรหัสผ่าน'
                                          : 'กรุณาพิมพ์คำว่า "ลบบัญชี"',
                                    ),
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
      final response = hasPassword
          ? await ProfileService.deleteAccount(password: result)
          : await ProfileService.deleteAccount(confirmText: result.trim());

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
        SnackBar(content: Text(response['message'] ?? 'ลบบัญชีเรียบร้อยแล้ว')),
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
  // UI
  // =====================================================

  Widget buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // กล่องสีขาวที่รวมหลายแถว
  Widget buildGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: AppDecorations.cardBorder,
        boxShadow: AppDecorations.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: AppColors.border),
            children[i],
          ],
        ],
      ),
    );
  }

  // โหมดสี: ตามเครื่อง / สว่าง / มืด (เปลี่ยนทันที)
  Widget buildThemeSelector() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, child) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  buildIcon(Icons.contrast_rounded, AppColors.primary),
                  const SizedBox(width: 14),
                  Text(
                    'โหมดสี',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    backgroundColor: AppColors.fill,
                    selectedBackgroundColor: AppColors.primary,
                    selectedForegroundColor: Colors.white,
                    foregroundColor: AppColors.navy,
                    side: BorderSide(color: AppColors.border),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined, size: 18),
                      label: Text('ตามเครื่อง'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                      label: Text('สว่าง'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined, size: 18),
                      label: Text('มืด'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) {
                    ThemeController.set(selection.first);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildIcon(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget buildSwitchRow({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required bool value,
    required bool busy,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: busy ? null : onChanged,
      secondary: buildIcon(icon, color),
      contentPadding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
    );
  }

  Widget buildActionRow({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? color,
    bool danger = false,
    required VoidCallback onTap,
  }) {
    color ??= AppColors.primary;

    return ListTile(
      onTap: onTap,
      leading: buildIcon(icon, color),
      contentPadding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      title: Text(
        title,
        style: TextStyle(
          color: danger ? AppColors.danger : AppColors.navy,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.muted),
    );
  }

  List<Widget> buildPreferenceSections() {
    if (isLoading) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (loadError != null) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
          child: Column(
            children: [
              Text(
                loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.navy),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: loadSettings,
                child: const Text('ลองอีกครั้ง'),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      buildSectionTitle('ตำแหน่ง'),
      buildGroup([
        buildSwitchRow(
          icon: Icons.location_on_outlined,
          color: AppColors.success,
          title: 'แชร์ตำแหน่งกับครอบครัว',
          subtitle: locationSharing
              ? 'ครอบครัวเห็นตำแหน่งล่าสุดของคุณขณะเปิดแอป (ไม่ติดตามตอนปิดแอป)'
              : 'ปิดอยู่ ครอบครัวไม่เห็นตำแหน่งของคุณ',
          value: locationSharing,
          busy: savingKeys.contains('location_sharing'),
          onChanged: setLocationSharing,
        ),
      ]),
      buildSectionTitle('การแจ้งเตือน'),
      buildGroup([
        for (final option in notificationOptions)
          buildSwitchRow(
            icon: option.icon,
            color: AppColors.primary,
            title: option.title,
            value: notifications[option.type] ?? true,
            busy: savingKeys.contains(option.type),
            onChanged: (value) => setNotification(option.type, value),
          ),
      ]),
      Padding(
        padding: EdgeInsets.fromLTRB(6, 8, 6, 0),
        child: Text(
          'ผลการตรวจสอบร้านค้าจะแจ้งเสมอ',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่า')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          ...buildPreferenceSections(),
          buildSectionTitle('การแสดงผล'),
          buildGroup([buildThemeSelector()]),
          buildSectionTitle('ความเป็นส่วนตัว'),
          buildGroup([
            buildActionRow(
              icon: Icons.block_rounded,
              title: 'ผู้ใช้ที่บล็อก',
              subtitle: 'ดูและเลิกบล็อกผู้ใช้ในชุมชน',
              color: AppColors.muted,
              onTap: openBlockedUsers,
            ),
          ]),
          if (visibleSocialAccounts.isNotEmpty) ...[
            buildSectionTitle('บัญชีที่เชื่อมต่อ'),
            buildGroup([
              for (final account in visibleSocialAccounts)
                buildSocialRow(account),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(
                'เชื่อมแล้วเข้าสู่ระบบด้วยบัญชีนั้นได้ทันที โดยไม่ต้องใช้รหัสผ่าน',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ],
          buildSectionTitle('บัญชี'),
          buildGroup([
            buildActionRow(
              icon: Icons.password_rounded,
              title: hasPassword ? 'เปลี่ยนรหัสผ่าน' : 'ตั้งรหัสผ่าน',
              color: AppColors.warm,
              onTap: changePassword,
            ),
            buildActionRow(
              icon: Icons.logout_rounded,
              title: 'ออกจากระบบ',
              color: AppColors.danger,
              danger: true,
              onTap: logout,
            ),
            buildActionRow(
              icon: Icons.delete_forever_rounded,
              title: 'ลบบัญชี',
              subtitle: 'ลบบัญชีและข้อมูลทั้งหมดถาวร',
              color: AppColors.danger,
              danger: true,
              onTap: deleteAccount,
            ),
          ]),
          buildSectionTitle('เกี่ยวกับแอป'),
          buildGroup([
            buildActionRow(
              icon: Icons.privacy_tip_outlined,
              title: 'นโยบายความเป็นส่วนตัว',
              color: AppColors.sky,
              onTap: () => openPolicy(AppInfo.privacyUrl),
            ),
            buildActionRow(
              icon: Icons.description_outlined,
              title: 'ข้อกำหนดการใช้งาน',
              color: AppColors.sky,
              onTap: () => openPolicy(AppInfo.termsUrl),
            ),
            buildActionRow(
              icon: Icons.child_care_rounded,
              title: 'มาตรฐานความปลอดภัยของเด็ก',
              color: AppColors.sky,
              onTap: () => openPolicy(AppInfo.childSafetyUrl),
            ),
          ]),
          if (version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Text(
                '${AppInfo.name} เวอร์ชัน $version',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationOption {
  final String type;
  final String title;
  final IconData icon;

  const _NotificationOption({
    required this.type,
    required this.title,
    required this.icon,
  });
}
