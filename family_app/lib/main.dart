import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';

import 'services/api_helper.dart';
import 'services/auth_service.dart';

import 'theme/app_theme.dart';
import 'pages/splash_page.dart';

final GlobalKey<NavigatorState>
    navigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding
      .ensureInitialized();

  // ===============================================
  // Token หมดอายุ
  // ===============================================

  ApiHelper.onUnauthorized =
      () async {
    await AuthService.clearToken();

    final navigator =
        navigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    navigator.pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  };

  runApp(
    const FamilyOrbitApp(),
  );
}

class FamilyOrbitApp
    extends StatelessWidget {
  const FamilyOrbitApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey:
          navigatorKey,

      debugShowCheckedModeBanner:
          false,

      title: 'Family Orbit',

      theme: AppTheme.light(),

      home:
          const SplashPage(
        nextPage:
          AuthCheckPage(),
          ),

      routes: {
        '/login': (context) =>
            const LoginPage(),

        '/register': (context) =>
            const RegisterPage(),
      },
    );
  }
}

// =======================================================
// ตรวจ Login ตอนเปิดแอป
// =======================================================

class AuthCheckPage
    extends StatefulWidget {
  const AuthCheckPage({
    super.key,
  });

  @override
  State<AuthCheckPage>
      createState() =>
          _AuthCheckPageState();
}

class _AuthCheckPageState
    extends State<AuthCheckPage> {
  bool isChecking = true;

  Map<String, dynamic>? user;

  @override
  void initState() {
    super.initState();

    checkLogin();
  }

  Future<void>
      checkLogin() async {
    final token =
        await AuthService.getToken();

    if (token == null) {
      if (!mounted) return;

      setState(() {
        isChecking = false;
        user = null;
      });

      return;
    }

    final currentUser =
        await AuthService
            .getCurrentUser();

    if (!mounted) return;

    setState(() {
      user = currentUser;
      isChecking = false;
    });
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (isChecking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons
                    .family_restroom,
                size: 62,
                color:
                    AppColors.primary,
              ),

              const SizedBox(
                height: 20,
              ),

              const Text(
                'FAMILY ORBIT',
                style:
                    TextStyle(
                  color:
                      AppColors.navy,
                  fontWeight:
                      FontWeight.w800,
                  letterSpacing:
                      2,
                ),
              ),

              const SizedBox(
                height: 24,
              ),

              const SizedBox(
                width: 26,
                height: 26,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (user == null) {
      return const LoginPage();
    }

    final String userName =
        user?['name']?.toString() ??
            'User';

    return HomePage(
      userName: userName,
    );
  }
}