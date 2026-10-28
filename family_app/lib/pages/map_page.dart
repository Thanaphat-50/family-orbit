import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/chat_service.dart';
import '../services/location_service.dart';
import '../services/location_tracker.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'chat_room_page.dart';
import 'user_profile_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? mapController;

  StreamSubscription<Position>? positionSubscription;

  Timer? refreshTimer;

  Position? currentPosition;

  List<Map<String, dynamic>> familyLocations = [];

  // ชื่อสมาชิกคนอื่นที่ปิดการแชร์ตำแหน่งอยู่
  List<String> pausedNames = [];

  bool isTurningOnSharing = false;

  bool locationAllowed = false;

  bool isLoadingLocation = false;

  DateTime? lastRefresh;

  String? locationError;

  // สมาชิกที่กำลังดูรายละเอียด (วาดเส้นจากเราไปหา)
  int? focusedUserId;

  // แผ่นรายละเอียดเปิดอยู่ → ดันกล้องขึ้นไม่ให้จุดถูกบัง
  bool detailOpen = false;

  // เพิ่มทุกครั้งที่ตำแหน่งเปลี่ยน → แผ่นรายละเอียดคำนวณระยะทางใหม่
  final ValueNotifier<int> locationsVersion = ValueNotifier(0);

  // ตำแหน่งเกินเวลานี้ = อาจไม่ใช่ตำแหน่งปัจจุบัน (แอปของเขาอาจปิดอยู่)
  static const Duration staleAfter = Duration(minutes: 15);

  // ตำแหน่งตั้งต้นของ Map
  // ใช้ก่อน GPS โหลดเสร็จ
  static const LatLng defaultPosition = LatLng(37.3943833, -121.9658783);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      initializePage();
    });
  }

  // =====================================================
  // START
  // =====================================================

  Future<void> initializePage() async {
    startRefreshTimer();

    // โหลดสองระบบแยกจากกัน
    // Map จะไม่ต้องรอ
    loadFamilyLocations();
    prepareLocation();
  }

  // =====================================================
  // GPS / PERMISSION
  // =====================================================

  Future<void> prepareLocation() async {
    if (isLoadingLocation) {
      return;
    }

    isLoadingLocation = true;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        setState(() {
          locationError = 'กรุณาเปิด Location ของอุปกรณ์';
        });

        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (!mounted) return;

        setState(() {
          locationError = 'กรุณาอนุญาตการเข้าถึงตำแหน่ง';
        });

        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;

        setState(() {
          locationError = 'สิทธิ์ตำแหน่งถูกปิดถาวร กรุณาเปิดจาก Settings';
        });

        return;
      }

      if (!mounted) return;

      setState(() {
        locationAllowed = true;
        locationError = null;
      });

      const settings = LocationSettings(accuracy: LocationAccuracy.high);

      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );

      if (!mounted) return;

      setState(() {
        currentPosition = position;
      });

      // ส่งตำแหน่งนี้ทันที แล้วให้ LocationTracker ส่งต่อเองขณะเปิดแอป (ทุกแท็บ)
      await LocationTracker.start(current: position);

      await moveToMyLocation();

      startPositionStream();

      // โหลดข้อมูลใหม่หลังเราเพิ่งส่ง
      // Location ของตัวเอง
      await loadFamilyLocations();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        locationError = 'ไม่สามารถอ่านตำแหน่งได้';
      });
    } finally {
      isLoadingLocation = false;
    }
  }

  // =====================================================
  // LOCATION STREAM
  // =====================================================

  void startPositionStream() {
    positionSubscription?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,

      // ส่งใหม่เมื่อขยับประมาณ 10 เมตร
      distanceFilter: 10,
    );

    positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings)
            .listen((position) {
              if (!mounted) return;

              // ใช้แสดงจุดของเราบนแผนที่เท่านั้น
              // (LocationTracker เป็นคนส่งตำแหน่งให้ครอบครัว)
              setState(() {
                currentPosition = position;
              });

              locationsVersion.value++;
            });
  }

  // =====================================================
  // LOAD FAMILY LOCATIONS
  // =====================================================

  Future<void> loadFamilyLocations() async {
    try {
      final result = await LocationService.getFamilyLocations();

      if (!mounted) return;

      if (result['status'] == true) {
        final rawLocations = result['locations'];

        final List<Map<String, dynamic>> locations = [];

        if (rawLocations is List) {
          for (final item in rawLocations) {
            if (item is Map) {
              locations.add(Map<String, dynamic>.from(item));
            }
          }
        }

        final dynamic rawPaused = result['paused'];

        setState(() {
          familyLocations = locations;

          pausedNames = rawPaused is List
              ? rawPaused
                    .whereType<Map>()
                    .map((member) => member['name']?.toString() ?? '')
                    .where((name) => name.isNotEmpty)
                    .toList()
              : [];

          lastRefresh = DateTime.now();
        });

        locationsVersion.value++;
      }
    } catch (_) {
      // Timer จะลองใหม่อีกรอบ
    }
  }

  // เปิดการแชร์ตำแหน่งอีกครั้ง (จากแถบแจ้งบนแผนที่)
  Future<void> turnOnSharing() async {
    setState(() => isTurningOnSharing = true);

    try {
      final result = await SettingsService.updateSettings(
        locationSharing: true,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        await prepareLocation();

        // ถ้าหน้านี้กำลังอ่าน GPS อยู่ตอนกดเปิด prepareLocation จะไม่ทำซ้ำ
        // → สั่งเริ่มส่งตรงนี้ด้วย (ถ้าเริ่มไปแล้วจะไม่ส่งซ้ำ)
        await LocationTracker.start();
      } else {
        showSnack(result['message']?.toString() ?? 'เปิดการแชร์ไม่สำเร็จ');
      }
    } catch (e) {
      if (mounted) showSnack(e.toString());
    } finally {
      if (mounted) setState(() => isTurningOnSharing = false);
    }
  }

  void showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // REFRESH ทุก 10 วินาที
  // =====================================================

  void startRefreshTimer() {
    refreshTimer?.cancel();

    refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      loadFamilyLocations();
    });
  }

  // =====================================================
  // HELPERS
  // =====================================================

  double? toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  String getMemberName(Map<String, dynamic> location) {
    final user = location['user'];

    if (user is Map) {
      return user['name']?.toString() ?? 'สมาชิก';
    }

    return 'สมาชิก';
  }

  String? getProfileImageUrl(Map<String, dynamic> location) {
    final user = location['user'];

    if (user is! Map) {
      return null;
    }

    const keys = [
      'profile_image_url',
      'profile_photo_url',
      'avatar_url',
      'photo_url',
      'image_url',
      'profile_image',
      'avatar',
      'photo',
      'image',
    ];

    for (final key in keys) {
      final rawValue = user[key];

      if (rawValue == null) {
        continue;
      }

      final value = rawValue.toString().trim();

      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return null;
  }

  String getInitial(String name) {
    final value = name.trim();

    if (value.isEmpty) {
      return '?';
    }

    return value.characters.first.toUpperCase();
  }

  // =====================================================
  // เวลาอัปเดต
  // =====================================================

  String formatLastSeen(dynamic value) {
    if (value == null) {
      return 'ยังไม่มีข้อมูลเวลา';
    }

    try {
      final date = DateTime.parse(value.toString()).toLocal();

      final difference = DateTime.now().difference(date);

      if (difference.isNegative || difference.inMinutes < 1) {
        return 'เมื่อสักครู่';
      }

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} นาทีที่แล้ว';
      }

      if (difference.inHours < 24) {
        return '${difference.inHours} ชั่วโมงที่แล้ว';
      }

      return '${difference.inDays} วันที่แล้ว';
    } catch (_) {
      return 'มีข้อมูลตำแหน่ง';
    }
  }

  bool isMe(Map<String, dynamic> location) => location['is_me'] == true;

  int? userIdOf(Map<String, dynamic> location) {
    final dynamic id = location['user_id'];

    return id is num ? id.toInt() : int.tryParse(id?.toString() ?? '');
  }

  Map<String, dynamic>? locationOf(int userId) {
    for (final location in familyLocations) {
      if (userIdOf(location) == userId) return location;
    }

    return null;
  }

  DateTime? lastSeenOf(Map<String, dynamic> location) {
    return DateTime.tryParse(location['last_seen_at']?.toString() ?? '')
        ?.toLocal();
  }

  bool isStale(Map<String, dynamic> location) {
    final DateTime? lastSeen = lastSeenOf(location);

    return lastSeen == null || DateTime.now().difference(lastSeen) > staleAfter;
  }

  // ระยะทางเส้นตรงจากเรา (เมตร) / ยังไม่รู้ตำแหน่งเรา → null
  double? distanceTo(Map<String, dynamic> location) {
    final Position? me = currentPosition;

    final latitude = toDouble(location['latitude']);

    final longitude = toDouble(location['longitude']);

    if (me == null || latitude == null || longitude == null) return null;

    return Geolocator.distanceBetween(
      me.latitude,
      me.longitude,
      latitude,
      longitude,
    );
  }

  static String formatDistance(double meters) {
    if (meters < 1000) {
      // ใกล้มาก ๆ ปัดเป็นสิบเมตร อ่านง่ายกว่า
      final int rounded = meters < 100
          ? meters.round()
          : (meters / 10).round() * 10;

      return '$rounded ม.';
    }

    final double km = meters / 1000;

    return km < 10 ? '${km.toStringAsFixed(1)} กม.' : '${km.round()} กม.';
  }

  // 14:32 น.
  static String formatClock(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')} น.';
  }

  // อัปเดตวันนี้ / อัปเดตเมื่อวาน / อัปเดต 26 ต.ค.
  static String formatUpdatedDay(DateTime date) {
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

    final DateTime now = DateTime.now();

    final DateTime today = DateTime(now.year, now.month, now.day);

    final DateTime day = DateTime(date.year, date.month, date.day);

    if (day == today) return 'อัปเดตวันนี้';

    if (day == today.subtract(const Duration(days: 1))) {
      return 'อัปเดตเมื่อวาน';
    }

    return 'อัปเดต ${date.day} ${months[date.month]}';
  }

  // บรรทัดสั้นใต้ชื่อ: "1.2 กม. · 3 นาทีที่แล้ว"
  String memberSummary(Map<String, dynamic> location) {
    final String lastSeen = formatLastSeen(location['last_seen_at']);

    if (isMe(location)) return 'คุณ · $lastSeen';

    final double? distance = distanceTo(location);

    return distance == null
        ? lastSeen
        : '${formatDistance(distance)} · $lastSeen';
  }

  String getSyncText() {
    if (lastRefresh == null) {
      return 'กำลังซิงก์';
    }

    final difference = DateTime.now().difference(lastRefresh!);

    if (difference.inSeconds < 15) {
      return 'อัปเดตล่าสุด';
    }

    if (difference.inMinutes < 1) {
      return '${difference.inSeconds} วินาทีที่แล้ว';
    }

    return '${difference.inMinutes} นาทีที่แล้ว';
  }

  // =====================================================
  // MARKERS
  // =====================================================

  Set<Marker> buildMarkers() {
    final Set<Marker> markers = {};

    for (int index = 0; index < familyLocations.length; index++) {
      final location = familyLocations[index];

      final latitude = toDouble(location['latitude']);

      final longitude = toDouble(location['longitude']);

      if (latitude == null || longitude == null) {
        continue;
      }

      final userId = location['user_id']?.toString() ?? '$index';

      final name = getMemberName(location);

      markers.add(
        Marker(
          markerId: MarkerId('family_$userId'),

          position: LatLng(latitude, longitude),

          icon: BitmapDescriptor.defaultMarkerWithHue(
            index.isEven
                ? BitmapDescriptor.hueViolet
                : BitmapDescriptor.hueAzure,
          ),

          infoWindow: InfoWindow(
            title: isMe(location) ? '$name (คุณ)' : name,

            snippet: memberSummary(location),
          ),

          onTap: () => openMember(location),
        ),
      );
    }

    return markers;
  }

  // เส้นประจากเราไปหาสมาชิกที่กำลังดู
  Set<Polyline> buildPolylines() {
    final int? userId = focusedUserId;

    final Position? me = currentPosition;

    if (userId == null || me == null) return {};

    final Map<String, dynamic>? location = locationOf(userId);

    final latitude = location == null ? null : toDouble(location['latitude']);

    final longitude = location == null ? null : toDouble(location['longitude']);

    if (latitude == null || longitude == null) return {};

    return {
      Polyline(
        polylineId: const PolylineId('to_member'),
        points: [
          LatLng(me.latitude, me.longitude),
          LatLng(latitude, longitude),
        ],
        color: AppColors.primary,
        width: 4,
        patterns: [PatternItem.dash(18), PatternItem.gap(12)],
      ),
    };
  }

  // =====================================================
  // MOVE TO MEMBER
  // =====================================================

  Future<void> moveToMember(Map<String, dynamic> location) async {
    if (mapController == null) {
      return;
    }

    final latitude = toDouble(location['latitude']);

    final longitude = toDouble(location['longitude']);

    if (latitude == null || longitude == null) {
      return;
    }

    await mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(latitude, longitude), zoom: 16),
      ),
    );
  }

  // =====================================================
  // MEMBER DETAILS
  // ระยะทางจากเรา เวลาอัปเดต ความแม่นยำ + นำทาง / แชท / โปรไฟล์
  // =====================================================

  // เห็นทั้งเราและสมาชิกบนแผนที่ (เหนือแผ่นรายละเอียด)
  Future<void> showMeAndMember(Map<String, dynamic> location) async {
    final controller = mapController;

    final Position? me = currentPosition;

    final latitude = toDouble(location['latitude']);

    final longitude = toDouble(location['longitude']);

    if (controller == null || latitude == null || longitude == null) return;

    if (me == null) {
      await moveToMember(location);
      return;
    }

    final double south = latitude < me.latitude ? latitude : me.latitude;
    final double north = latitude < me.latitude ? me.latitude : latitude;
    final double west = longitude < me.longitude ? longitude : me.longitude;
    final double east = longitude < me.longitude ? me.longitude : longitude;

    // อยู่ใกล้กันมาก → ซูมที่สมาชิกแทน
    if ((north - south).abs() < 0.0005 && (east - west).abs() < 0.0005) {
      await moveToMember(location);
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(south, west),
            northeast: LatLng(north, east),
          ),
          60,
        ),
      );
    } catch (_) {
      await moveToMember(location);
    }
  }

  Future<void> openMember(Map<String, dynamic> location) async {
    final int? userId = userIdOf(location);

    // จุดของเราเอง → เลื่อนไปที่ตัวเราอย่างเดียว
    if (isMe(location) || userId == null) {
      await moveToMember(location);
      return;
    }

    setState(() {
      focusedUserId = userId;
      detailOpen = true;
    });

    // รอให้แผนที่รับระยะขอบใหม่ก่อน แล้วค่อยเลื่อนกล้อง
    await Future<void>.delayed(const Duration(milliseconds: 150));

    if (!mounted) return;

    showMeAndMember(location);

    final String? action = await showModalBottomSheet<String>(
      context: context,

      showDragHandle: true,

      isScrollControlled: true,

      barrierColor: Colors.black.withValues(alpha: 0.08),

      builder: (sheetContext) {
        return ValueListenableBuilder<int>(
          valueListenable: locationsVersion,

          builder: (context, _, _) {
            // ใช้ตำแหน่งล่าสุด (รีเฟรชทุก 10 วินาที) ถ้าหาไม่เจอใช้อันเดิม
            final Map<String, dynamic> latest = locationOf(userId) ?? location;

            return buildMemberSheet(sheetContext, latest);
          },
        );
      },
    );

    if (!mounted) return;

    setState(() {
      focusedUserId = null;
      detailOpen = false;
    });

    if (action == 'chat') {
      await openChatWith(userId);
    } else if (action == 'profile') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              UserProfilePage(userId: userId, name: getMemberName(location)),
        ),
      );
    }
  }

  // เปิด Google Maps นำทางไปหาสมาชิก (บอกเส้นทางและเวลาเดินทางจริง)
  Future<void> openDirections(Map<String, dynamic> location) async {
    final latitude = toDouble(location['latitude']);

    final longitude = toDouble(location['longitude']);

    if (latitude == null || longitude == null) return;

    final Uri uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$latitude,$longitude',
    });

    bool opened = false;

    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }

    if (!opened) showMessage('เปิด Google Maps ไม่ได้');
  }

  Future<void> openChatWith(int userId) async {
    try {
      final result = await ChatService.openChat(userId);

      if (!mounted) return;

      final dynamic room = result['conversation'];

      if (result['status'] == true && room is Map && room['id'] is num) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatRoomPage(
              conversationId: (room['id'] as num).toInt(),
              user: room['user'] is Map
                  ? Map<String, dynamic>.from(room['user'])
                  : null,
            ),
          ),
        );
      } else {
        showMessage(result['message']?.toString() ?? 'เปิดแชทไม่สำเร็จ');
      }
    } catch (e) {
      showMessage(e.toString());
    }
  }

  Widget buildMemberSheet(
    BuildContext sheetContext,
    Map<String, dynamic> location,
  ) {
    final String name = getMemberName(location);

    final double? distance = distanceTo(location);

    final DateTime? lastSeen = lastSeenOf(location);

    final bool stale = isStale(location);

    final double? accuracy = toDouble(location['accuracy']);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [
            Row(
              children: [
                _MemberProfileAvatar(
                  imageUrl: getProfileImageUrl(location),
                  name: name,
                  size: 54,
                ),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        name,

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,

                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,

                            decoration: BoxDecoration(
                              color: stale ? AppColors.warm : AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),

                          const SizedBox(width: 6),

                          Expanded(
                            child: Text(
                              stale
                                  ? 'ตำแหน่งล่าสุด ${formatLastSeen(location['last_seen_at'])}'
                                  : 'อัปเดต ${formatLastSeen(location['last_seen_at'])}',

                              style: TextStyle(
                                color: stale ? AppColors.warm : AppColors.muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: _MemberInfoTile(
                    icon: Icons.social_distance_rounded,
                    label: 'ห่างจากคุณ',
                    value: distance == null ? '—' : formatDistance(distance),
                    color: AppColors.primary,
                  ),
                ),

                const SizedBox(width: 9),

                Expanded(
                  child: _MemberInfoTile(
                    icon: Icons.schedule_rounded,
                    label: lastSeen == null
                        ? 'อัปเดตเมื่อ'
                        : formatUpdatedDay(lastSeen),
                    value: lastSeen == null ? '—' : formatClock(lastSeen),
                    color: AppColors.sky,
                  ),
                ),

                const SizedBox(width: 9),

                Expanded(
                  child: _MemberInfoTile(
                    icon: Icons.gps_fixed_rounded,
                    label: 'ความแม่นยำ',
                    value: accuracy == null
                        ? '—'
                        : '±${formatDistance(accuracy)}',
                    color: AppColors.success,
                  ),
                ),
              ],
            ),

            if (distance == null) ...[
              const SizedBox(height: 10),

              Text(
                'เปิดตำแหน่งของคุณเพื่อดูระยะทาง',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],

            if (stale) ...[
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(12),

                decoration: BoxDecoration(
                  color: AppColors.softWarm,
                  borderRadius: BorderRadius.circular(14),
                ),

                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.warm,
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: Text(
                        'อาจไม่ใช่ตำแหน่งปัจจุบัน ตำแหน่งจะอัปเดต'
                        'เมื่อ $name เปิดแอปใกล้กัน',

                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            FilledButton.icon(
              onPressed: () => openDirections(location),

              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),

              icon: const Icon(Icons.directions_rounded),

              label: const Text('นำทางด้วย Google Maps'),
            ),

            const SizedBox(height: 6),

            Text(
              'ระยะทางเป็นเส้นตรง เส้นทางและเวลาเดินทางจริงดูใน Google Maps',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11.5),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop('chat'),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('แชท'),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop('profile'),
                    icon: const Icon(Icons.person_outline_rounded),
                    label: const Text('โปรไฟล์'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // MY LOCATION
  // =====================================================

  Future<void> moveToMyLocation() async {
    if (currentPosition == null) {
      if (!locationAllowed) {
        await prepareLocation();
      }

      return;
    }

    if (mapController == null) {
      return;
    }

    final position = currentPosition!;

    await mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 16,
        ),
      ),
    );
  }

  // =====================================================
  // SHOW ALL MEMBERS
  // =====================================================

  Future<void> showAllMembers() async {
    if (mapController == null) {
      return;
    }

    final List<LatLng> points = [];

    for (final location in familyLocations) {
      final latitude = toDouble(location['latitude']);

      final longitude = toDouble(location['longitude']);

      if (latitude != null && longitude != null) {
        points.add(LatLng(latitude, longitude));
      }
    }

    if (points.isEmpty) {
      showMessage('ยังไม่มีข้อมูลตำแหน่งสมาชิก');

      return;
    }

    // มีคนเดียว
    if (points.length == 1) {
      await mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 15.5),
        ),
      );

      return;
    }

    double minLat = points.first.latitude;

    double maxLat = points.first.latitude;

    double minLng = points.first.longitude;

    double maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude < minLat) {
        minLat = point.latitude;
      }

      if (point.latitude > maxLat) {
        maxLat = point.latitude;
      }

      if (point.longitude < minLng) {
        minLng = point.longitude;
      }

      if (point.longitude > maxLng) {
        maxLng = point.longitude;
      }
    }

    // ทุกคนอยู่พิกัดเดียวกัน
    if (minLat == maxLat && minLng == maxLng) {
      await mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 15.5),
        ),
      );

      return;
    }

    try {
      await mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),

            northeast: LatLng(maxLat, maxLng),
          ),
          70,
        ),
      );
    } catch (_) {}
  }

  // =====================================================
  // SNACKBAR
  // =====================================================

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // TOP FAMILY MAP CARD
  // =====================================================

  Widget buildMapHeader() {
    return Positioned(
      top: 14,
      left: 14,
      right: 14,

      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 9, 12),

        decoration: BoxDecoration(
          color: AppColors.surface,

          borderRadius: BorderRadius.circular(21),

          border: AppDecorations.cardBorder,

          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.10),

              blurRadius: 25,

              offset: const Offset(0, 8),
            ),
          ],
        ),

        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,

              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, Color(0xFF777CFF)],
                ),

                borderRadius: BorderRadius.circular(15),
              ),

              child: const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),

            const SizedBox(width: 11),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Family Map',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(width: 7),

                      Container(
                        width: 7,
                        height: 7,

                        decoration: BoxDecoration(
                          color: locationAllowed
                              ? AppColors.success
                              : AppColors.warm,

                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 2),

                  Text(
                    '${familyLocations.length} สมาชิก • ${getSyncText()}',
                    style: TextStyle(color: AppColors.muted, fontSize: 10),
                  ),
                ],
              ),
            ),

            IconButton(
              tooltip: 'รีเฟรช',

              onPressed: () async {
                await loadFamilyLocations();
              },

              icon: Icon(Icons.refresh_rounded, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // LOCATION ERROR
  // =====================================================

  Widget buildLocationError() {
    if (locationError == null) {
      return buildSharingNotice();
    }

    return Positioned(
      top: 88,
      left: 14,
      right: 14,

      child: Container(
        padding: const EdgeInsets.all(12),

        decoration: BoxDecoration(
          color: AppColors.softWarm,

          borderRadius: BorderRadius.circular(17),

          border: Border.all(color: AppColors.warm.withValues(alpha: 0.4)),
        ),

        child: Row(
          children: [
            Icon(
              Icons.location_disabled_rounded,
              color: AppColors.warm,
              size: 21,
            ),

            const SizedBox(width: 9),

            Expanded(
              child: Text(
                locationError!,
                style: TextStyle(color: AppColors.navy, fontSize: 11),
              ),
            ),

            TextButton(
              onPressed: () async {
                final permission = await Geolocator.checkPermission();

                if (permission == LocationPermission.deniedForever) {
                  await Geolocator.openAppSettings();
                } else {
                  await prepareLocation();
                }
              },

              child: const Text('แก้ไข'),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // แถบแจ้งการปิดแชร์ตำแหน่ง
  // - เราปิดอยู่: มีปุ่มเปิดแชร์อีกครั้ง
  // - คนอื่นปิดอยู่: บอกชื่อ ครอบครัวจะได้รู้ว่าทำไมไม่เห็น
  // =====================================================

  Widget buildSharingNotice() {
    return ValueListenableBuilder<bool?>(
      valueListenable: SettingsService.locationSharing,
      builder: (context, sharing, child) {
        final bool selfPaused = sharing == false;

        if (!selfPaused && pausedNames.isEmpty) {
          return const SizedBox.shrink();
        }

        final String message = selfPaused
            ? 'คุณปิดการแชร์ตำแหน่งอยู่ ครอบครัวจะไม่เห็นตำแหน่งของคุณ'
            : 'ปิดการแชร์ตำแหน่งอยู่: ${pausedNames.join(', ')}';

        return Positioned(
          top: 88,
          left: 14,
          right: 14,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(17),
              border: AppDecorations.cardBorder,
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_off_outlined,
                  color: AppColors.muted,
                  size: 21,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                if (selfPaused)
                  TextButton(
                    onPressed: isTurningOnSharing ? null : turnOnSharing,
                    child: Text(isTurningOnSharing ? 'กำลังเปิด' : 'เปิดแชร์'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =====================================================
  // MAP ACTION BUTTONS
  // =====================================================

  Widget buildMapButtons() {
    return Positioned(
      right: 14,
      bottom: 166,

      child: Column(
        children: [
          _FamilyMapButton(
            icon: Icons.groups_rounded,

            tooltip: 'ดูสมาชิกทั้งหมด',

            onPressed: showAllMembers,
          ),

          const SizedBox(height: 10),

          _FamilyMapButton(
            icon: Icons.my_location_rounded,

            tooltip: 'ตำแหน่งของฉัน',

            primary: true,

            onPressed: moveToMyLocation,
          ),
        ],
      ),
    );
  }

  // =====================================================
  // MEMBER PANEL
  // =====================================================

  Widget buildMemberPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,

      child: Container(
        height: 150,

        decoration: BoxDecoration(
          color: AppColors.surface,

          borderRadius: const BorderRadius.vertical(top: Radius.circular(27)),

          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.11),

              blurRadius: 28,

              offset: const Offset(0, -8),
            ),
          ],
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 9),

            Center(
              child: Container(
                width: 38,
                height: 4,

                decoration: BoxDecoration(
                  color: AppColors.border,

                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),

              child: Row(
                children: [
                  Text(
                    'สมาชิกในแผนที่',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const Spacer(),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),

                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.09),

                      borderRadius: BorderRadius.circular(99),
                    ),

                    child: Text(
                      '${familyLocations.length} คน',

                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: familyLocations.isEmpty
                  ? Center(
                      child: Text(
                        'ยังไม่มีตำแหน่งของสมาชิกในครอบครัว',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,

                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),

                      itemCount: familyLocations.length,

                      separatorBuilder: (_, _) => const SizedBox(width: 9),

                      itemBuilder: (context, index) {
                        final location = familyLocations[index];

                        final name = getMemberName(location);

                        final profileImageUrl = getProfileImageUrl(location);

                        return InkWell(
                          borderRadius: BorderRadius.circular(17),

                          onTap: () {
                            openMember(location);
                          },

                          child: Container(
                            width: 178,

                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 8,
                            ),

                            decoration: BoxDecoration(
                              color: AppColors.fill,

                              borderRadius: BorderRadius.circular(17),

                              border: Border.all(color: AppColors.border),
                            ),

                            child: Row(
                              children: [
                                _MemberProfileAvatar(
                                  imageUrl: profileImageUrl,
                                  name: name,
                                ),

                                const SizedBox(width: 9),

                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isMe(location) ? '$name (คุณ)' : name,

                                        maxLines: 1,

                                        overflow: TextOverflow.ellipsis,

                                        style: TextStyle(
                                          color: AppColors.navy,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),

                                      const SizedBox(height: 3),

                                      Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,

                                            decoration: BoxDecoration(
                                              color: isStale(location)
                                                  ? AppColors.warm
                                                  : AppColors.success,
                                              shape: BoxShape.circle,
                                            ),
                                          ),

                                          const SizedBox(width: 5),

                                          Expanded(
                                            child: Text(
                                              memberSummary(location),

                                              maxLines: 1,

                                              overflow: TextOverflow.ellipsis,

                                              style: TextStyle(
                                                color: AppColors.muted,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,

      children: [
        // =================================================
        // GOOGLE MAP
        // =================================================

        GoogleMap(
          mapType: MapType.normal,

          // โหมดมืด: แผนที่สีเข้ม
          style: AppColors.isDark ? darkMapStyle : null,

          initialCameraPosition: const CameraPosition(
            target: defaultPosition,
            zoom: 15,
          ),

          onMapCreated: (controller) {
            mapController = controller;

            if (currentPosition != null) {
              moveToMyLocation();
            }
          },

          markers: buildMarkers(),

          polylines: buildPolylines(),

          myLocationEnabled: locationAllowed,

          myLocationButtonEnabled: false,

          zoomControlsEnabled: false,

          mapToolbarEnabled: false,

          compassEnabled: false,

          buildingsEnabled: true,

          // แผ่นรายละเอียดเปิด → เว้นด้านล่างมากขึ้น ให้จุดอยู่เหนือแผ่น
          padding: EdgeInsets.only(top: 90, bottom: detailOpen ? 430 : 155),
        ),

        // =================================================
        // FAMILY ORBIT UI
        // =================================================
        buildMapHeader(),

        buildLocationError(),

        buildMapButtons(),

        buildMemberPanel(),
      ],
    );
  }

  // =====================================================
  // DISPOSE
  // =====================================================

  @override
  void dispose() {
    refreshTimer?.cancel();

    positionSubscription?.cancel();

    locationsVersion.dispose();

    super.dispose();
  }
}

// =======================================================
// MEMBER PROFILE AVATAR
// =======================================================

class _MemberProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;

  const _MemberProfileAvatar({
    required this.imageUrl,
    required this.name,
    this.size = 41,
  });

  String get initial {
    final value = name.trim();

    if (value.isEmpty) {
      return '?';
    }

    return value.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: url == null || url.isEmpty
          ? _buildFallback()
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildFallback();
              },
            ),
    );
  }

  Widget _buildFallback() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF767BFF)],
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.37,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// =======================================================
// MEMBER INFO TILE (ระยะทาง / เวลา / ความแม่นยำ)
// =======================================================

class _MemberInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MemberInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 8, 11),

      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(16),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(icon, size: 19, color: color),

          const SizedBox(height: 8),

          Text(
            value,

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: TextStyle(
              color: AppColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            label,

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// MAP BUTTON
// =======================================================

class _FamilyMapButton extends StatelessWidget {
  final IconData icon;

  final String tooltip;

  final bool primary;

  final VoidCallback onPressed;

  const _FamilyMapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.primary : AppColors.surface,

      elevation: 4,

      shadowColor: AppColors.navy.withValues(alpha: 0.16),

      borderRadius: BorderRadius.circular(16),

      child: InkWell(
        onTap: onPressed,

        borderRadius: BorderRadius.circular(16),

        child: Tooltip(
          message: tooltip,

          child: SizedBox(
            width: 48,
            height: 48,

            child: Icon(
              icon,

              color: primary ? Colors.white : AppColors.primary,

              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// สีแผนที่สำหรับโหมดมืด (Google Maps JSON style)
const String darkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#1d2026"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#98a2b3"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#1d2026"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#23272f"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1b2a22"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#2b3039"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#1d2026"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#3a404b"}]},
  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#23272f"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#0f1a2b"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#5c6b80"}]}
]
''';
