import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashPage extends StatefulWidget {
  final Widget nextPage;

  const SplashPage({
    super.key,
    required this.nextPage,
  });

  @override
  State<SplashPage> createState() =>
      _SplashPageState();
}

class _SplashPageState
    extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController
      _controller;

  late final Animation<double>
      _fadeAnimation;

  late final Animation<double>
      _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        milliseconds: 850,
      ),
    );

    _fadeAnimation =
        CurvedAnimation(
      parent: _controller,
      curve:
          Curves.easeOut,
    );

    _scaleAnimation =
        Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve:
            Curves.easeOutBack,
      ),
    );

    _startSplash();
  }

  Future<void> _startSplash() async {
    await _controller.forward();

    await Future<void>.delayed(
      const Duration(
        milliseconds: 700,
      ),
    );

    if (!mounted) return;

    Navigator.of(context)
        .pushReplacement(
      PageRouteBuilder(
        transitionDuration:
            const Duration(
          milliseconds: 420,
        ),

        pageBuilder: (
          context,
          animation,
          secondaryAnimation,
        ) {
          return widget.nextPage;
        },

        transitionsBuilder: (
          context,
          animation,
          secondaryAnimation,
          child,
        ) {
          return FadeTransition(
            opacity:
                animation,
            child:
                child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AnnotatedRegion<
        SystemUiOverlayStyle>(
      value:
          SystemUiOverlayStyle.light,

      child: Scaffold(
        body: Container(
          width:
              double.infinity,

          height:
              double.infinity,

          decoration:
              const BoxDecoration(
            gradient:
                LinearGradient(
              begin:
                  Alignment.topLeft,

              end:
                  Alignment.bottomRight,

              colors: [
                Color(
                  0xFF111827,
                ),
                Color(
                  0xFF172554,
                ),
                Color(
                  0xFF3730A3,
                ),
                Color(
                  0xFF5B5FEF,
                ),
              ],

              stops: [
                0.0,
                0.28,
                0.66,
                1.0,
              ],
            ),
          ),

          child: Stack(
            children: [
              // ==========================================
              // ORBIT BACKGROUND 1
              // ==========================================

              Positioned(
                top: -150,
                right: -130,

                child:
                    Container(
                  width:
                      360,
                  height:
                      360,

                  decoration:
                      BoxDecoration(
                    shape:
                        BoxShape.circle,

                    border:
                        Border.all(
                      color:
                          Colors.white
                              .withValues(
                        alpha:
                            0.08,
                      ),

                      width:
                          1.3,
                    ),
                  ),
                ),
              ),

              // ==========================================
              // ORBIT BACKGROUND 2
              // ==========================================

              Positioned(
                bottom: -180,
                left: -150,

                child:
                    Container(
                  width:
                      420,
                  height:
                      420,

                  decoration:
                      BoxDecoration(
                    shape:
                        BoxShape.circle,

                    border:
                        Border.all(
                      color:
                          const Color(
                            0xFF4CC9F0,
                          )
                              .withValues(
                        alpha:
                            0.10,
                      ),

                      width:
                          1.5,
                    ),
                  ),
                ),
              ),

              // ==========================================
              // LIGHT GLOW
              // ==========================================

              Positioned(
                top:
                    MediaQuery.of(
                          context,
                        )
                        .size
                        .height *
                    0.18,

                left: -80,

                child:
                    Container(
                  width:
                      220,
                  height:
                      220,

                  decoration:
                      BoxDecoration(
                    shape:
                        BoxShape.circle,

                    gradient:
                        RadialGradient(
                      colors: [
                        const Color(
                          0xFF4CC9F0,
                        )
                            .withValues(
                          alpha:
                              0.18,
                        ),

                        Colors
                            .transparent,
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 40,
                right: -70,

                child:
                    Container(
                  width:
                      230,
                  height:
                      230,

                  decoration:
                      BoxDecoration(
                    shape:
                        BoxShape.circle,

                    gradient:
                        RadialGradient(
                      colors: [
                        const Color(
                          0xFFA855F7,
                        )
                            .withValues(
                          alpha:
                              0.20,
                        ),

                        Colors
                            .transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ==========================================
              // MAIN CONTENT
              // ==========================================

              SafeArea(
                child:
                    Center(
                  child:
                      FadeTransition(
                    opacity:
                        _fadeAnimation,

                    child:
                        ScaleTransition(
                      scale:
                          _scaleAnimation,

                      child:
                          Padding(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal:
                              24,
                        ),

                        child:
                            Column(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .center,

                          children: [
                            const Spacer(
                              flex: 3,
                            ),

                            // ============================
                            // LOGO
                            // ============================

                            Image.asset(
                              'assets/branding/splash_logo.png',

                              width:
                                  MediaQuery.of(
                                            context,
                                          )
                                          .size
                                          .width *
                                      0.88,

                              fit:
                                  BoxFit.contain,
                            ),

                            const SizedBox(
                              height: 18,
                            ),

                            Text(
                              'Stay connected with the people who matter.',

                              textAlign:
                                  TextAlign
                                      .center,

                              style:
                                  TextStyle(
                                color:
                                    Colors
                                        .white
                                        .withValues(
                                  alpha:
                                      0.70,
                                ),

                                fontSize:
                                    13,

                                height:
                                    1.5,

                                letterSpacing:
                                    0.2,
                              ),
                            ),

                            const Spacer(
                              flex: 3,
                            ),

                            // ============================
                            // LOADING
                            // ============================

                            SizedBox(
                              width:
                                  25,
                              height:
                                  25,

                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2.2,

                                color:
                                    Colors
                                        .white
                                        .withValues(
                                  alpha:
                                      0.90,
                                ),

                                backgroundColor:
                                    Colors
                                        .white
                                        .withValues(
                                  alpha:
                                      0.10,
                                ),
                              ),
                            ),

                            const SizedBox(
                              height: 13,
                            ),

                            Text(
                              'FAMILY ORBIT',

                              style:
                                  TextStyle(
                                color:
                                    Colors
                                        .white
                                        .withValues(
                                  alpha:
                                      0.55,
                                ),

                                fontSize:
                                    9,

                                fontWeight:
                                    FontWeight
                                        .w700,

                                letterSpacing:
                                    2.4,
                              ),
                            ),

                            const SizedBox(
                              height: 30,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}