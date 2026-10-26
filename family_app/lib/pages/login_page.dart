import 'package:flutter/material.dart';

import '../config/app_info.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/orbit_background.dart';

import 'home_page.dart';
import 'register_page.dart';

class LoginPage
    extends StatefulWidget {
  const LoginPage({
    super.key,
  });

  @override
  State<LoginPage> createState() =>
      _LoginPageState();
}

class _LoginPageState
    extends State<LoginPage> {
  final emailController =
      TextEditingController();

  final passwordController =
      TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  Future<void> login() async {
    final email =
        emailController.text.trim();

    final password =
        passwordController.text;

    if (email.isEmpty ||
        password.isEmpty) {
      showMessage(
        'กรุณากรอก Email และ Password',
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final result =
          await AuthService.login(
        email: email,
        password: password,
      );

      if (!mounted) return;

      final bool success =
          result['status'] == true ||
              result['token'] != null;

      if (success) {
        final dynamic user =
            result['user'];

        String userName = 'User';

        if (user is Map) {
          userName =
              user['name']?.toString() ??
                  'User';
        }

        Navigator.of(context)
            .pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                HomePage(
              userName: userName,
            ),
          ),
          (route) => false,
        );
      } else {
        showMessage(
          result['message'] ??
              'Email หรือ Password ไม่ถูกต้อง',
        );
      }
    } catch (_) {
      if (!mounted) return;

      showMessage(
        'ไม่สามารถเชื่อมต่อ Server ได้',
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void showMessage(
    String message,
  ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.transparent,

      body: OrbitBackground(
        child: SafeArea(
          child:
              SingleChildScrollView(
            padding:
                const EdgeInsets
                    .fromLTRB(
              24,
              30,
              24,
              30,
            ),

            child: Center(
              child:
                  ConstrainedBox(
                constraints:
                    const BoxConstraints(
                  maxWidth: 480,
                ),

                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                  children: [
                    const SizedBox(
                      height: 15,
                    ),

                    // ===================================
                    // Brand
                    // ===================================

                    const Center(
                      child:
                          FamilyOrbitLogo(),
                    ),

                    const SizedBox(
                      height: 22,
                    ),

                    Text(
                      AppInfo.name,
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            AppColors.navy,
                        fontSize: 18,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    Text(
                      'อยู่ใกล้กัน\nไม่ว่าจะอยู่ที่ไหน',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            AppColors.navy,
                        fontSize: 30,
                        height: 1.18,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Text(
                      'เชื่อมต่อ พูดคุย แชร์กิจกรรม\nและดูแลสมาชิกในครอบครัวได้ในที่เดียว',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            AppColors.muted,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),

                    const SizedBox(
                      height: 32,
                    ),

                    // ===================================
                    // Login Card
                    // ===================================

                    Container(
                      padding:
                          const EdgeInsets
                              .all(22),

                      decoration:
                          BoxDecoration(
                        color: AppColors.surface
                            .withValues(
                          alpha: 0.92,
                        ),

                        borderRadius:
                            BorderRadius
                                .circular(
                          28,
                        ),

                        border:
                            Border.all(
                          color:
                              AppColors.surface,
                        ),

                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors
                                    .navy
                                    .withValues(
                              alpha:
                                  0.06,
                            ),
                            blurRadius:
                                35,
                            offset:
                                const Offset(
                              0,
                              14,
                            ),
                          ),
                        ],
                      ),

                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .stretch,
                        children: [
                          Text(
                            'ยินดีต้อนรับกลับมา',
                            style:
                                TextStyle(
                              color:
                                  AppColors
                                      .navy,
                              fontSize:
                                  20,
                              fontWeight:
                                  FontWeight
                                      .w800,
                            ),
                          ),

                          const SizedBox(
                            height: 5,
                          ),

                          Text(
                            'เข้าสู่บัญชี${AppInfo.name}ของคุณ',
                            style:
                                TextStyle(
                              color:
                                  AppColors
                                      .muted,
                              fontSize:
                                  13,
                            ),
                          ),

                          const SizedBox(
                            height: 24,
                          ),

                          TextField(
                            controller:
                                emailController,
                            keyboardType:
                                TextInputType
                                    .emailAddress,
                            textInputAction:
                                TextInputAction
                                    .next,
                            autofillHints:
                                const [
                              AutofillHints
                                  .email,
                            ],
                            decoration:
                                const InputDecoration(
                              labelText:
                                  'Email',
                              hintText:
                                  'example@email.com',
                              prefixIcon:
                                  Icon(
                                Icons
                                    .alternate_email_rounded,
                              ),
                            ),
                          ),

                          const SizedBox(
                            height: 15,
                          ),

                          TextField(
                            controller:
                                passwordController,
                            obscureText:
                                obscurePassword,
                            textInputAction:
                                TextInputAction
                                    .done,
                            autofillHints:
                                const [
                              AutofillHints
                                  .password,
                            ],
                            onSubmitted:
                                (_) {
                              if (!isLoading) {
                                login();
                              }
                            },
                            decoration:
                                InputDecoration(
                              labelText:
                                  'Password',
                              prefixIcon:
                                  const Icon(
                                Icons
                                    .lock_outline_rounded,
                              ),
                              suffixIcon:
                                  IconButton(
                                onPressed:
                                    () {
                                  setState(
                                    () {
                                      obscurePassword =
                                          !obscurePassword;
                                    },
                                  );
                                },
                                icon: Icon(
                                  obscurePassword
                                      ? Icons
                                          .visibility_outlined
                                      : Icons
                                          .visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(
                            height: 22,
                          ),

                          ElevatedButton(
                            onPressed:
                                isLoading
                                    ? null
                                    : login,
                            child:
                                isLoading
                                    ? const SizedBox(
                                        width:
                                            23,
                                        height:
                                            23,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth:
                                              2.4,
                                          color:
                                              Colors.white,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'เข้าสู่ระบบ',
                                          ),
                                          SizedBox(
                                            width:
                                                8,
                                          ),
                                          Icon(
                                            Icons
                                                .arrow_forward_rounded,
                                            size:
                                                19,
                                          ),
                                        ],
                                      ),
                          ),

                          const SizedBox(
                            height: 20,
                          ),

                          Row(
                            children: [
                              const Expanded(
                                child:
                                    Divider(),
                              ),

                              Padding(
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal:
                                      12,
                                ),
                                child: Text(
                                  'หรือ',
                                  style:
                                      TextStyle(
                                    color:
                                        Colors
                                            .grey
                                            .shade500,
                                  ),
                                ),
                              ),

                              const Expanded(
                                child:
                                    Divider(),
                              ),
                            ],
                          ),

                          const SizedBox(
                            height: 16,
                          ),

                          OutlinedButton(
                            onPressed:
                                isLoading
                                    ? null
                                    : () {
                                        Navigator.of(
                                          context,
                                        ).push(
                                          MaterialPageRoute(
                                            builder:
                                                (_) =>
                                                    const RegisterPage(),
                                          ),
                                        );
                                      },
                            child:
                                const Text(
                              'สร้างบัญชีใหม่',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(
                      height: 24,
                    ),

                    Text(
                      'Your family. Your circle.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            AppColors.muted,
                        fontSize: 12,
                        letterSpacing:
                            0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();

    super.dispose();
  }
}