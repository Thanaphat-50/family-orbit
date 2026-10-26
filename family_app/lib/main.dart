import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'config/app_info.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';

import 'services/api_helper.dart';
import 'services/auth_service.dart';

import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'pages/splash_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await setUpFirebase();

  // ===============================================
  // Token หมดอายุ
  // ===============================================

  ApiHelper.onUnauthorized = () async {
    await AuthService.clearToken();

    final navigator = navigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
  };

  // โหมดสีที่เลือกไว้ (ตามเครื่อง / สว่าง / มืด)
  await ThemeController.load();

  runApp(const FamilyOrbitApp());
}

// =======================================================
// Firebase: แจ้งเตือนเด้ง + รายงานแอปเด้ง (Crashlytics)
// ตั้งค่าไม่สำเร็จ → แอปยังใช้งานได้ปกติ แค่ไม่มี 2 อย่างนี้
// =======================================================

Future<void> setUpFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
    return;
  }

  // ส่งรายงานเฉพาะแอปจริง (release) ตอนพัฒนาไม่ส่ง
  if (kDebugMode) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
    return;
  }

  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

  // Error ใน Flutter (เช่น หน้าจอวาดไม่ได้)
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Error ที่ไม่มีใครจับ (async)
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);

    return true;
  };
}

class FamilyOrbitApp extends StatefulWidget {
  const FamilyOrbitApp({super.key});

  @override
  State<FamilyOrbitApp> createState() => _FamilyOrbitAppState();
}

// สลับโหมดสี: ตั้งชุดสีของ AppColors ใหม่ แล้วสั่งทุกหน้าวาดใหม่
// (หน้าที่เปิดค้างอยู่ใช้สีใหม่ทันที ไม่ต้องปิดแอป)
class _FamilyOrbitAppState extends State<FamilyOrbitApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    ThemeController.mode.addListener(onThemeChanged);

    applyPalette();
  }

  // เครื่องเปลี่ยนโหมดสว่าง/มืด (ใช้เมื่อเลือก "ตามเครื่อง")
  @override
  void didChangePlatformBrightness() {
    onThemeChanged();
  }

  Brightness get effectiveBrightness {
    switch (ThemeController.mode.value) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  void applyPalette() {
    AppColors.palette = effectiveBrightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
  }

  void onThemeChanged() {
    final AppPalette before = AppColors.palette;

    applyPalette();

    if (!mounted) return;

    setState(() {});

    if (!identical(before, AppColors.palette)) {
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    }
  }

  @override
  void dispose() {
    ThemeController.mode.removeListener(onThemeChanged);

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,

      debugShowCheckedModeBanner: false,

      title: AppInfo.name,

      theme: AppTheme.light(),

      darkTheme: AppTheme.dark(),

      themeMode: ThemeController.mode.value,

      home: const SplashPage(nextPage: AuthCheckPage()),

      routes: {
        '/login': (context) => const LoginPage(),

        '/register': (context) => const RegisterPage(),
      },
    );
  }
}

// =======================================================
// ตรวจ Login ตอนเปิดแอป
// =======================================================

class AuthCheckPage extends StatefulWidget {
  const AuthCheckPage({super.key});

  @override
  State<AuthCheckPage> createState() => _AuthCheckPageState();
}

class _AuthCheckPageState extends State<AuthCheckPage> {
  bool isChecking = true;

  Map<String, dynamic>? user;

  @override
  void initState() {
    super.initState();

    checkLogin();
  }

  Future<void> checkLogin() async {
    final token = await AuthService.getToken();

    if (token == null) {
      if (!mounted) return;

      setState(() {
        isChecking = false;
        user = null;
      });

      return;
    }

    final currentUser = await AuthService.getCurrentUser();

    if (!mounted) return;

    setState(() {
      user = currentUser;
      isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isChecking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.family_restroom, size: 62, color: AppColors.primary),

              const SizedBox(height: 20),

              Text(
                AppInfo.name,
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 24),

              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
    }

    if (user == null) {
      return const LoginPage();
    }

    final String userName = user?['name']?.toString() ?? 'User';

    return HomePage(userName: userName);
  }
}
