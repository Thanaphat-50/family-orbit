import 'package:flutter/material.dart';

import '../services/activity_service.dart';
import '../theme/app_theme.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  bool isLoading = true;
  bool isCreating = false;

  bool hasFamily = false;

  List<dynamic> activities = [];

  String selectedFilter = 'all';

  @override
  void initState() {
    super.initState();

    loadActivities();
  }

  // =====================================================
  // LOAD
  // =====================================================

  Future<void> loadActivities() async {
    try {
      final result = await ActivityService.getActivities();

      if (!mounted) return;

      if (result['status'] == true) {
        final family = result['family'];

        setState(() {
          activities = result['activities'] ?? [];

          if (family is Map) {
            hasFamily = family['has_family'] == true;
          } else {
            hasFamily = false;
          }
        });
      } else {
        showMessage(result['message'] ?? 'โหลดกิจกรรมไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('โหลดกิจกรรมไม่สำเร็จ');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // =====================================================
  // HELPERS
  // =====================================================

  bool boolValue(dynamic value) {
    return value == true || value == 1 || value == '1';
  }

  bool canManage(Map<String, dynamic> activity) {
    return boolValue(activity['can_manage']);
  }

  bool isMine(Map<String, dynamic> activity) {
    return boolValue(activity['is_mine']);
  }

  bool isCompleted(Map<String, dynamic> activity) {
    return boolValue(activity['is_completed']);
  }

  String visibility(Map<String, dynamic> activity) {
    return activity['visibility']?.toString() ?? 'private';
  }

  String ownerName(Map<String, dynamic> activity) {
    final user = activity['user'];

    if (user is Map) {
      final name = user['name']?.toString().trim();

      if (name != null && name.isNotEmpty) {
        return name;
      }
    }

    return 'สมาชิก';
  }

  String? ownerImageUrl(Map<String, dynamic> activity) {
    final user = activity['user'];

    if (user is! Map) {
      return null;
    }

    const imageKeys = [
      'profile_image_url',
      'profile_image',
      'avatar_url',
      'avatar',
      'photo_url',
      'photo',
      'image_url',
      'image',
    ];

    String? imageUrl;

    for (final key in imageKeys) {
      final value = user[key]?.toString().trim();

      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        imageUrl = value;
        break;
      }
    }

    if (imageUrl == null) {
      return null;
    }

    // ถ้า backend ส่ง updated_at มาด้วย จะช่วยบังคับให้ Flutter
    // โหลดรูปใหม่หลังผู้ใช้เปลี่ยนรูป แม้ URL รูปเดิมจะไม่เปลี่ยน
    final version =
        user['profile_image_updated_at']?.toString().trim() ??
        user['updated_at']?.toString().trim();

    if (version == null || version.isEmpty || version.toLowerCase() == 'null') {
      return imageUrl;
    }

    final separator = imageUrl.contains('?') ? '&' : '?';

    return '$imageUrl${separator}v=${Uri.encodeQueryComponent(version)}';
  }

  String ownerInitial(String name) {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      return 'ส';
    }

    return cleanName.substring(0, 1).toUpperCase();
  }

  Widget buildOwnerAvatar({required String name, String? imageUrl}) {
    Widget fallback() {
      return Container(
        alignment: Alignment.center,
        color: AppColors.primary.withValues(alpha: 0.10),
        child: Text(
          ownerInitial(name),
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: 20,
        height: 20,
        child: imageUrl == null
            ? fallback()
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return fallback();
                },
              ),
      ),
    );
  }

  // =====================================================
  // FILTER
  // =====================================================

  List<Map<String, dynamic>> get filteredActivities {
    final items = <Map<String, dynamic>>[];

    for (final item in activities) {
      if (item is! Map) {
        continue;
      }

      final activity = Map<String, dynamic>.from(item);

      if (selectedFilter == 'mine' && !isMine(activity)) {
        continue;
      }

      if (selectedFilter == 'family' && visibility(activity) != 'family') {
        continue;
      }

      items.add(activity);
    }

    return items;
  }

  // =====================================================
  // CREATE SHEET
  // =====================================================

  Future<void> showCreateActivitySheet() async {
    String title = '';
    String description = '';

    String selectedVisibility = 'private';

    DateTime? selectedDateTime;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.transparent,

      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> selectDateTime() async {
              final now = DateTime.now();

              final date = await showDatePicker(
                context: context,

                initialDate: selectedDateTime ?? now,

                firstDate: DateTime(now.year - 1),

                lastDate: DateTime(now.year + 5),
              );

              if (date == null || !context.mounted) {
                return;
              }

              final time = await showTimePicker(
                context: context,

                initialTime: selectedDateTime != null
                    ? TimeOfDay.fromDateTime(selectedDateTime!)
                    : TimeOfDay.now(),
              );

              if (time == null) {
                return;
              }

              setSheetState(() {
                selectedDateTime = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            }

            return Container(
              margin: const EdgeInsets.only(top: 55),

              decoration: const BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),

              child: SafeArea(
                top: false,

                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    12,
                    22,
                    MediaQuery.of(context).viewInsets.bottom + 25,
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,

                    children: [
                      // =================================
                      // HANDLE
                      // =================================

                      Center(
                        child: Container(
                          width: 40,
                          height: 4,

                          decoration: BoxDecoration(
                            color: const Color(0xFFD8DBE5),

                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      // =================================
                      // HEADER
                      // =================================
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,

                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [AppColors.primary, Color(0xFF777CFF)],
                              ),

                              borderRadius: BorderRadius.circular(16),
                            ),

                            child: const Icon(
                              Icons.event_available_rounded,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(width: 13),

                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                Text(
                                  'เพิ่มกิจกรรม',
                                  style: TextStyle(
                                    color: AppColors.navy,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),

                                SizedBox(height: 3),

                                Text(
                                  'สร้างแผนของคุณหรือแชร์ให้ครอบครัว',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          IconButton(
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                            },

                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),

                      const SizedBox(height: 25),

                      // =================================
                      // TITLE
                      // =================================
                      const Text(
                        'ชื่อกิจกรรม',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextField(
                        autofocus: true,

                        textInputAction: TextInputAction.next,

                        onChanged: (value) {
                          title = value;
                        },

                        decoration: const InputDecoration(
                          hintText: 'เช่น กินข้าวเย็นด้วยกัน',

                          prefixIcon: Icon(Icons.edit_calendar_outlined),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // =================================
                      // DESCRIPTION
                      // =================================
                      const Text(
                        'รายละเอียด',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextField(
                        minLines: 3,
                        maxLines: 5,

                        onChanged: (value) {
                          description = value;
                        },

                        decoration: const InputDecoration(
                          hintText: 'รายละเอียดเพิ่มเติม...',

                          alignLabelWithHint: true,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // =================================
                      // VISIBILITY
                      // =================================
                      const Text(
                        'ใครสามารถเห็นกิจกรรมนี้?',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 5),

                      const Text(
                        'เลือกว่ากิจกรรมนี้เป็นเรื่องส่วนตัวหรือแชร์กับครอบครัว',
                        style: TextStyle(color: AppColors.muted, fontSize: 10),
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _VisibilityChoice(
                              icon: Icons.lock_outline_rounded,

                              title: 'ส่วนตัว',

                              subtitle: 'เฉพาะคุณ',

                              selected: selectedVisibility == 'private',

                              onTap: () {
                                setSheetState(() {
                                  selectedVisibility = 'private';
                                });
                              },
                            ),
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child: _VisibilityChoice(
                              icon: Icons.family_restroom_rounded,

                              title: 'ครอบครัว',

                              subtitle: hasFamily
                                  ? 'สมาชิกเห็นได้'
                                  : 'ยังไม่มี Family',

                              selected: selectedVisibility == 'family',

                              enabled: hasFamily,

                              onTap: () {
                                if (!hasFamily) {
                                  return;
                                }

                                setSheetState(() {
                                  selectedVisibility = 'family';
                                });
                              },
                            ),
                          ),
                        ],
                      ),

                      if (!hasFamily) ...[
                        const SizedBox(height: 10),

                        Container(
                          padding: const EdgeInsets.all(11),

                          decoration: BoxDecoration(
                            color: AppColors.warm.withValues(alpha: 0.10),

                            borderRadius: BorderRadius.circular(14),
                          ),

                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: AppColors.warm,
                                size: 18,
                              ),

                              SizedBox(width: 8),

                              Expanded(
                                child: Text(
                                  'เข้าร่วมหรือสร้างครอบครัวก่อน จึงจะแชร์กิจกรรมได้',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // =================================
                      // DATE
                      // =================================
                      const Text(
                        'วันและเวลา',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 8),

                      InkWell(
                        onTap: selectDateTime,

                        borderRadius: BorderRadius.circular(18),

                        child: Container(
                          padding: const EdgeInsets.all(15),

                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FD),

                            borderRadius: BorderRadius.circular(18),

                            border: Border.all(color: AppColors.border),
                          ),

                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,

                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.09,
                                  ),

                                  borderRadius: BorderRadius.circular(13),
                                ),

                                child: const Icon(
                                  Icons.calendar_month_rounded,
                                  color: AppColors.primary,
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Text(
                                  selectedDateTime == null
                                      ? 'เลือกวันและเวลา'
                                      : formatDateTime(selectedDateTime!),

                                  style: TextStyle(
                                    color: selectedDateTime == null
                                        ? AppColors.muted
                                        : AppColors.navy,

                                    fontSize: 12,

                                    fontWeight: selectedDateTime == null
                                        ? FontWeight.w500
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),

                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (selectedDateTime != null)
                        Align(
                          alignment: Alignment.centerRight,

                          child: TextButton(
                            onPressed: () {
                              setSheetState(() {
                                selectedDateTime = null;
                              });
                            },

                            child: const Text('ล้างวันและเวลา'),
                          ),
                        ),

                      const SizedBox(height: 23),

                      // =================================
                      // CREATE
                      // =================================
                      ElevatedButton.icon(
                        onPressed: () {
                          final cleanTitle = title.trim();

                          if (cleanTitle.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('กรุณาใส่ชื่อกิจกรรม'),
                              ),
                            );

                            return;
                          }

                          Navigator.of(sheetContext).pop({
                            'title': cleanTitle,

                            'description': description.trim(),

                            'activity_date': selectedDateTime,

                            'visibility': selectedVisibility,
                          });
                        },

                        icon: Icon(
                          selectedVisibility == 'family'
                              ? Icons.group_add_rounded
                              : Icons.add_task_rounded,
                        ),

                        label: Text(
                          selectedVisibility == 'family'
                              ? 'สร้างและแชร์กับครอบครัว'
                              : 'สร้างกิจกรรมส่วนตัว',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    await createActivity(
      title: result['title'].toString(),

      description: result['description']?.toString() ?? '',

      activityDate: result['activity_date'] as DateTime?,

      visibility: result['visibility']?.toString() ?? 'private',
    );
  }

  // =====================================================
  // CREATE API
  // =====================================================

  Future<void> createActivity({
    required String title,
    required String description,
    required String visibility,
    DateTime? activityDate,
  }) async {
    setState(() {
      isCreating = true;
    });

    try {
      final result = await ActivityService.createActivity(
        title: title,

        description: description.isEmpty ? null : description,

        activityDate: activityDate,

        visibility: visibility,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        await loadActivities();

        if (!mounted) return;

        showMessage(
          visibility == 'family'
              ? 'แชร์กิจกรรมกับครอบครัวแล้ว'
              : 'สร้างกิจกรรมส่วนตัวแล้ว',
        );
      } else {
        showMessage(result['message'] ?? 'เพิ่มกิจกรรมไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) {
        setState(() {
          isCreating = false;
        });
      }
    }
  }

  // =====================================================
  // TOGGLE
  // =====================================================

  Future<void> toggleActivity(Map<String, dynamic> activity) async {
    if (!canManage(activity)) {
      showMessage('เฉพาะผู้สร้างกิจกรรมเท่านั้นที่เปลี่ยนสถานะได้');

      return;
    }

    final id = activity['id'];

    if (id is! num) {
      return;
    }

    try {
      final result = await ActivityService.toggleActivity(id.toInt());

      if (!mounted) return;

      if (result['status'] == true) {
        await loadActivities();
      } else {
        showMessage(result['message'] ?? 'อัปเดตกิจกรรมไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  // =====================================================
  // CHANGE VISIBILITY
  // =====================================================

  Future<void> changeVisibility(
    Map<String, dynamic> activity,
    String newVisibility,
  ) async {
    if (!canManage(activity)) {
      showMessage('เฉพาะผู้สร้างกิจกรรมเท่านั้นที่เปลี่ยนการมองเห็นได้');

      return;
    }

    final id = activity['id'];

    if (id is! num) {
      return;
    }

    if (newVisibility == 'family' && !hasFamily) {
      showMessage('คุณต้องมีครอบครัวก่อนจึงจะแชร์กิจกรรมได้');

      return;
    }

    try {
      final result = await ActivityService.updateVisibility(
        activityId: id.toInt(),

        visibility: newVisibility,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        await loadActivities();

        if (!mounted) return;

        showMessage(
          newVisibility == 'family'
              ? 'แชร์กิจกรรมกับครอบครัวแล้ว'
              : 'เปลี่ยนเป็นกิจกรรมส่วนตัวแล้ว',
        );
      } else {
        showMessage(result['message'] ?? 'เปลี่ยนการมองเห็นไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  // =====================================================
  // DELETE
  // =====================================================

  Future<void> deleteActivity(Map<String, dynamic> activity) async {
    if (!canManage(activity)) {
      showMessage('เฉพาะผู้สร้างกิจกรรมเท่านั้นที่ลบได้');
      return;
    }

    final id = activity['id'];

    if (id is! num) {
      return;
    }

    final title = activity['title']?.toString() ?? 'กิจกรรม';

    final confirm = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.delete_outline_rounded,

            color: AppColors.danger,

            size: 38,
          ),

          title: const Text('ลบกิจกรรม?', textAlign: TextAlign.center),

          content: Text(
            'ต้องการลบ “$title” หรือไม่?',
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

              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));

    try {
      final result = await ActivityService.deleteActivity(id.toInt());

      if (!mounted) return;

      if (result['status'] == true) {
        await loadActivities();

        if (!mounted) return;

        showMessage('ลบกิจกรรมแล้ว');
      } else {
        showMessage(result['message'] ?? 'ลบกิจกรรมไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  // =====================================================
  // DATE
  // =====================================================

  static String formatDateTime(DateTime date) {
    const months = [
      '',
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.day} '
        '${months[date.month]} '
        '${date.year} • '
        '$hour:$minute น.';
  }

  DateTime? parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    try {
      return DateTime.parse(value.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String activityDateText(dynamic value) {
    final date = parseDate(value);

    if (date == null) {
      return 'ไม่กำหนดเวลา';
    }

    return formatDateTime(date);
  }

  // =====================================================
  // PLANNER HEADER
  // =====================================================

  Widget buildPlannerHeader() {
    final total = activities.length;

    final completed = activities.where((item) {
      if (item is! Map) {
        return false;
      }

      return boolValue(item['is_completed']);
    }).length;

    final familyCount = activities.where((item) {
      if (item is! Map) {
        return false;
      }

      return item['visibility'] == 'family';
    }).length;

    final progress = total == 0 ? 0.0 : completed / total;

    return Container(
      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172554), Color(0xFF4650D8), Color(0xFF656BFF)],
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

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),

                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),

                  borderRadius: BorderRadius.circular(99),
                ),

                child: const Text(
                  'FAMILY PLANNER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
              ),

              const Spacer(),

              Text(
                '${(progress * 100).round()}%',

                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          const Text(
            'ทุกแผนสำคัญ\nเมื่อทำไปด้วยกัน',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              height: 1.18,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 18),

          ClipRRect(
            borderRadius: BorderRadius.circular(99),

            child: LinearProgressIndicator(
              value: progress,

              minHeight: 8,

              backgroundColor: Colors.white.withValues(alpha: 0.14),

              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.warm),
            ),
          ),

          const SizedBox(height: 17),

          Row(
            children: [
              _PlannerStat(value: '$total', label: 'ทั้งหมด'),

              const SizedBox(width: 8),

              _PlannerStat(value: '$completed', label: 'สำเร็จ'),

              const SizedBox(width: 8),

              _PlannerStat(value: '$familyCount', label: 'แชร์แล้ว'),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================
  // FILTERS
  // =====================================================

  Widget buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,

      child: Row(
        children: [
          _FilterChip(
            text: 'ทั้งหมด',

            selected: selectedFilter == 'all',

            onTap: () {
              setState(() {
                selectedFilter = 'all';
              });
            },
          ),

          const SizedBox(width: 8),

          _FilterChip(
            text: 'ของฉัน',

            icon: Icons.person_rounded,

            selected: selectedFilter == 'mine',

            onTap: () {
              setState(() {
                selectedFilter = 'mine';
              });
            },
          ),

          const SizedBox(width: 8),

          _FilterChip(
            text: 'ครอบครัว',

            icon: Icons.family_restroom_rounded,

            selected: selectedFilter == 'family',

            onTap: () {
              setState(() {
                selectedFilter = 'family';
              });
            },
          ),
        ],
      ),
    );
  }

  // =====================================================
  // ACTIVITY CARD
  // =====================================================

  Widget buildActivityCard(Map<String, dynamic> activity) {
    final completed = isCompleted(activity);

    final mine = isMine(activity);

    final manageable = canManage(activity);

    final shared = visibility(activity) == 'family';

    final creator = ownerName(activity);

    final creatorImageUrl = ownerImageUrl(activity);

    final title = activity['title']?.toString() ?? 'กิจกรรม';

    final description = activity['description']?.toString() ?? '';

    return AnimatedOpacity(
      opacity: completed ? 0.72 : 1,

      duration: const Duration(milliseconds: 200),

      child: Container(
        margin: const EdgeInsets.only(bottom: 12),

        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(22),

          border: Border.all(color: AppColors.border),

          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.03),

              blurRadius: 18,

              offset: const Offset(0, 7),
            ),
          ],
        ),

        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // ===========================================
            // STATUS ICON
            // ===========================================

            InkWell(
              onTap: manageable
                  ? () {
                      toggleActivity(activity);
                    }
                  : null,

              borderRadius: BorderRadius.circular(99),

              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),

                width: 46,
                height: 46,

                decoration: BoxDecoration(
                  color: completed
                      ? AppColors.success
                      : shared
                      ? AppColors.sky.withValues(alpha: 0.12)
                      : AppColors.primary.withValues(alpha: 0.09),

                  shape: BoxShape.circle,
                ),

                child: Icon(
                  completed
                      ? Icons.check_rounded
                      : shared
                      ? Icons.family_restroom_rounded
                      : Icons.lock_outline_rounded,

                  color: completed
                      ? Colors.white
                      : shared
                      ? AppColors.sky
                      : AppColors.primary,
                ),
              ),
            ),

            const SizedBox(width: 13),

            // ===========================================
            // CONTENT
            // ===========================================
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,

                          style: TextStyle(
                            color: AppColors.navy,

                            fontSize: 15,

                            fontWeight: FontWeight.w800,

                            decoration: completed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),

                      _VisibilityBadge(family: shared),
                    ],
                  ),

                  const SizedBox(height: 7),

                  Row(
                    children: [
                      buildOwnerAvatar(
                        name: creator,
                        imageUrl: creatorImageUrl,
                      ),

                      const SizedBox(width: 7),

                      Expanded(
                        child: Text(
                          mine ? 'สร้างโดยคุณ' : 'สร้างโดย $creator',

                          maxLines: 1,

                          overflow: TextOverflow.ellipsis,

                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),

                    Text(
                      description,

                      style: const TextStyle(
                        color: AppColors.muted,

                        fontSize: 12,

                        height: 1.4,
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,

                        color: AppColors.muted,

                        size: 14,
                      ),

                      const SizedBox(width: 5),

                      Expanded(
                        child: Text(
                          activityDateText(activity['activity_date']),

                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (!manageable && shared) ...[
                    const SizedBox(height: 9),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),

                      decoration: BoxDecoration(
                        color: AppColors.sky.withValues(alpha: 0.07),

                        borderRadius: BorderRadius.circular(10),
                      ),

                      child: const Row(
                        mainAxisSize: MainAxisSize.min,

                        children: [
                          Icon(
                            Icons.visibility_outlined,

                            color: AppColors.sky,

                            size: 13,
                          ),

                          SizedBox(width: 5),

                          Text(
                            'กิจกรรมที่แชร์โดยสมาชิก',

                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ===========================================
            // OWNER MENU
            // ===========================================
            if (manageable)
              PopupMenuButton<String>(
                tooltip: 'จัดการ',

                onSelected: (value) {
                  if (value == 'toggle') {
                    toggleActivity(activity);
                  }

                  if (value == 'private') {
                    changeVisibility(activity, 'private');
                  }

                  if (value == 'family') {
                    changeVisibility(activity, 'family');
                  }

                  if (value == 'delete') {
                    deleteActivity(activity);
                  }
                },

                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',

                    child: Row(
                      children: [
                        Icon(
                          completed
                              ? Icons.restart_alt_rounded
                              : Icons.check_circle_outline_rounded,

                          color: AppColors.primary,
                        ),

                        const SizedBox(width: 10),

                        Text(completed ? 'ทำอีกครั้ง' : 'ทำเสร็จแล้ว'),
                      ],
                    ),
                  ),

                  if (shared)
                    const PopupMenuItem(
                      value: 'private',

                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,

                            color: AppColors.primary,
                          ),

                          SizedBox(width: 10),

                          Text('เปลี่ยนเป็นส่วนตัว'),
                        ],
                      ),
                    )
                  else
                    PopupMenuItem(
                      value: 'family',

                      enabled: hasFamily,

                      child: Row(
                        children: [
                          Icon(
                            Icons.family_restroom_rounded,

                            color: hasFamily ? AppColors.sky : AppColors.muted,
                          ),

                          const SizedBox(width: 10),

                          Text(
                            hasFamily ? 'แชร์กับครอบครัว' : 'ยังไม่มีครอบครัว',
                          ),
                        ],
                      ),
                    ),

                  const PopupMenuDivider(),

                  const PopupMenuItem(
                    value: 'delete',

                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,

                          color: AppColors.danger,
                        ),

                        SizedBox(width: 10),

                        Text('ลบกิจกรรม'),
                      ],
                    ),
                  ),
                ],
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 12, right: 8),

                child: Icon(
                  Icons.visibility_outlined,

                  color: AppColors.muted,

                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // EMPTY
  // =====================================================

  Widget buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 45),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(25),

        border: Border.all(color: AppColors.border),
      ),

      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,

            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),

              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.calendar_month_outlined,

              color: AppColors.primary,

              size: 37,
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'ยังไม่มีกิจกรรม',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 7),

          const Text(
            'สร้างกิจกรรมส่วนตัว หรือแชร์แผนให้ครอบครัวได้',

            textAlign: TextAlign.center,

            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: 210,

            child: ElevatedButton.icon(
              onPressed: showCreateActivitySheet,

              icon: const Icon(Icons.add_rounded),

              label: const Text('เพิ่มกิจกรรม'),
            ),
          ),
        ],
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
    final displayed = filteredActivities;

    return Scaffold(
      backgroundColor: Colors.transparent,

      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_activity',

        onPressed: isCreating ? null : showCreateActivitySheet,

        icon: isCreating
            ? const SizedBox(
                width: 18,
                height: 18,

                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.add_rounded),

        label: const Text('เพิ่มกิจกรรม'),
      ),

      body: RefreshIndicator(
        color: AppColors.primary,

        onRefresh: loadActivities,

        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.fromLTRB(17, 12, 17, 105),

          children: [
            buildPlannerHeader(),

            const SizedBox(height: 25),

            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        'กิจกรรม',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      SizedBox(height: 3),

                      Text(
                        'แผนส่วนตัวและกิจกรรมของครอบครัว',

                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),

                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.09),

                    borderRadius: BorderRadius.circular(99),
                  ),

                  child: Text(
                    '${displayed.length} รายการ',

                    style: const TextStyle(
                      color: AppColors.primary,

                      fontSize: 10,

                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            buildFilters(),

            const SizedBox(height: 15),

            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),

                child: Center(child: CircularProgressIndicator()),
              )
            else if (displayed.isEmpty)
              buildEmptyState()
            else
              ...displayed.map(buildActivityCard),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// VISIBILITY SELECTOR
// =======================================================

class _VisibilityChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  final bool selected;
  final bool enabled;

  final VoidCallback onTap;

  const _VisibilityChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,

      borderRadius: BorderRadius.circular(18),

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),

        padding: const EdgeInsets.all(14),

        decoration: BoxDecoration(
          color: !enabled
              ? const Color(0xFFF4F4F6)
              : selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.white,

          borderRadius: BorderRadius.circular(18),

          border: Border.all(
            color: selected && enabled ? AppColors.primary : AppColors.border,

            width: selected && enabled ? 1.5 : 1,
          ),
        ),

        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,

              decoration: BoxDecoration(
                color: selected && enabled
                    ? AppColors.primary
                    : const Color(0xFFF2F4F7),

                shape: BoxShape.circle,
              ),

              child: Icon(
                icon,

                color: selected && enabled ? Colors.white : AppColors.muted,

                size: 20,
              ),
            ),

            const SizedBox(height: 9),

            Text(
              title,

              style: TextStyle(
                color: enabled ? AppColors.navy : AppColors.muted,

                fontSize: 13,

                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 3),

            Text(
              subtitle,

              textAlign: TextAlign.center,

              style: const TextStyle(color: AppColors.muted, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// VISIBILITY BADGE
// =======================================================

class _VisibilityBadge extends StatelessWidget {
  final bool family;

  const _VisibilityBadge({required this.family});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 7),

      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),

      decoration: BoxDecoration(
        color: family
            ? AppColors.sky.withValues(alpha: 0.10)
            : AppColors.primary.withValues(alpha: 0.08),

        borderRadius: BorderRadius.circular(99),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(
            family ? Icons.family_restroom_rounded : Icons.lock_outline_rounded,

            color: family ? AppColors.sky : AppColors.primary,

            size: 11,
          ),

          const SizedBox(width: 4),

          Text(
            family ? 'ครอบครัว' : 'ส่วนตัว',

            style: TextStyle(
              color: family ? AppColors.sky : AppColors.primary,

              fontSize: 8,

              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// FILTER
// =======================================================

class _FilterChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.text,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(99),

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),

        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),

        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,

          borderRadius: BorderRadius.circular(99),

          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),

        child: Row(
          mainAxisSize: MainAxisSize.min,

          children: [
            if (icon != null) ...[
              Icon(
                icon,

                size: 15,

                color: selected ? Colors.white : AppColors.muted,
              ),

              const SizedBox(width: 5),
            ],

            Text(
              text,

              style: TextStyle(
                color: selected ? Colors.white : AppColors.muted,

                fontSize: 11,

                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// PLANNER STAT
// =======================================================

class _PlannerStat extends StatelessWidget {
  final String value;
  final String label;

  const _PlannerStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),

        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),

          borderRadius: BorderRadius.circular(15),
        ),

        child: Column(
          children: [
            Text(
              value,

              style: const TextStyle(
                color: Colors.white,

                fontSize: 18,

                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 2),

            Text(
              label,

              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.67),
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
