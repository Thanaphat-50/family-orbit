import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =======================================================
// ชุดสีของแอป (โหมดสว่าง / โหมดมืด)
//
// ทุกหน้าใช้สีผ่าน AppColors ซึ่งอ่านจากชุดสีปัจจุบัน
// สลับโหมดแล้ว main.dart สั่งให้ทุกหน้าวาดใหม่ด้วยชุดสีใหม่
// =======================================================

class AppPalette {
  final Brightness brightness;

  // ข้อความหลัก (ชื่อเดิม navy)
  final Color navy;

  // ข้อความรอง / ไอคอนจาง
  final Color muted;

  // ข้อความเนื้อหาเข้มกว่า muted
  final Color subtle;

  final Color primary;
  final Color primaryDark;
  final Color sky;
  final Color warm;
  final Color danger;
  final Color success;

  // พื้นหลังของหน้า
  final Color background;

  // การ์ด / แถบ / หน้าต่าง
  final Color surface;

  // พื้นเทาอ่อนในการ์ด (ช่องกรอก ฟองความคิดเห็น ชิป)
  final Color fill;

  final Color border;

  // พื้นสีอ่อนของสีหลัก
  final Color softPrimary;
  final Color softSky;
  final Color softWarm;
  final Color softDanger;

  // เงาของการ์ด
  final Color shadow;

  const AppPalette({
    required this.brightness,
    required this.navy,
    required this.muted,
    required this.subtle,
    required this.primary,
    required this.primaryDark,
    required this.sky,
    required this.warm,
    required this.danger,
    required this.success,
    required this.background,
    required this.surface,
    required this.fill,
    required this.border,
    required this.softPrimary,
    required this.softSky,
    required this.softWarm,
    required this.softDanger,
    required this.shadow,
  });

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    navy: Color(0xFF101828),
    muted: Color(0xFF667085),
    subtle: Color(0xFF344054),
    primary: Color(0xFF5B5FEF),
    primaryDark: Color(0xFF4246D9),
    sky: Color(0xFF2BB5E0),
    warm: Color(0xFFF79A3E),
    danger: Color(0xFFE5484D),
    success: Color(0xFF2E9D6A),
    background: Color(0xFFF5F6FA),
    surface: Color(0xFFFFFFFF),
    fill: Color(0xFFF2F4F7),
    border: Color(0xFFE9EBF1),
    softPrimary: Color(0xFFF0F1FF),
    softSky: Color(0xFFEAF7FC),
    softWarm: Color(0xFFFFF4E8),
    softDanger: Color(0xFFFFEEEE),
    shadow: Color(0x14101828),
  );

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    navy: Color(0xFFF2F4F7),
    muted: Color(0xFF98A2B3),
    subtle: Color(0xFFD0D5DD),
    primary: Color(0xFF8B8FFF),
    primaryDark: Color(0xFF6E73F7),
    sky: Color(0xFF5CCDF0),
    warm: Color(0xFFFFB46B),
    danger: Color(0xFFF97066),
    success: Color(0xFF4CC38A),
    background: Color(0xFF0F1115),
    surface: Color(0xFF191C22),
    fill: Color(0xFF23272F),
    border: Color(0xFF2B3039),
    softPrimary: Color(0xFF25274A),
    softSky: Color(0xFF14313B),
    softWarm: Color(0xFF3A2A18),
    softDanger: Color(0xFF3D1F20),
    shadow: Color(0x66000000),
  );
}

class AppColors {
  // ตั้งจาก main.dart ตามโหมดที่เลือก
  static AppPalette palette = AppPalette.light;

  static bool get isDark => palette.brightness == Brightness.dark;

  static Color get navy => palette.navy;
  static Color get muted => palette.muted;
  static Color get subtle => palette.subtle;
  static Color get primary => palette.primary;
  static Color get primaryDark => palette.primaryDark;
  static Color get sky => palette.sky;
  static Color get warm => palette.warm;
  static Color get danger => palette.danger;
  static Color get success => palette.success;
  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get fill => palette.fill;
  static Color get border => palette.border;
  static Color get softPrimary => palette.softPrimary;
  static Color get softSky => palette.softSky;
  static Color get softWarm => palette.softWarm;
  static Color get softDanger => palette.softDanger;
  static Color get shadow => palette.shadow;
}

// =======================================================
// รูปทรงที่ใช้ซ้ำ (การ์ดขาวเงาบาง ไม่มีเส้นขอบ)
// =======================================================

class AppDecorations {
  // โหมดสว่าง: ไม่มีเส้นขอบ ใช้เงาบาง / โหมดมืด: เส้นขอบบาง ไม่มีเงา
  static BoxBorder? get cardBorder =>
      AppColors.isDark ? Border.all(color: AppColors.border) : null;

  static List<BoxShadow>? get cardShadow => AppColors.isDark
      ? null
      : [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ];

  static BoxDecoration card({double radius = 22, Color? color}) {
    return BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: cardBorder,
      boxShadow: cardShadow,
    );
  }
}

class AppTheme {
  static ThemeData light() => build(AppPalette.light);

  static ThemeData dark() => build(AppPalette.dark);

  static ThemeData build(AppPalette p) {
    final bool dark = p.brightness == Brightness.dark;

    final ColorScheme colorScheme =
        ColorScheme.fromSeed(
          seedColor: p.primary,
          brightness: p.brightness,
        ).copyWith(
          primary: p.primary,
          onPrimary: Colors.white,
          secondary: p.sky,
          surface: p.surface,
          onSurface: p.navy,
          error: p.danger,
          outline: p.border,
        );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      cardColor: p.surface,
      dividerColor: p.border,
      iconTheme: IconThemeData(color: p.navy),

      // =================================================
      // TYPOGRAPHY
      // =================================================
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: p.navy,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
        headlineMedium: TextStyle(
          color: p.navy,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          color: p.navy,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: p.navy,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: p.navy, fontSize: 15, height: 1.5),
        bodyMedium: TextStyle(color: p.muted, fontSize: 13, height: 1.45),
        bodySmall: TextStyle(color: p.muted, fontSize: 11, height: 1.4),
      ),

      // =================================================
      // APP BAR (กลืนกับพื้นหลัง ไม่มีเงา)
      // =================================================
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: p.navy,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        systemOverlayStyle:
            (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: p.background,
                  systemNavigationBarIconBrightness: dark
                      ? Brightness.light
                      : Brightness.dark,
                ),
      ),

      // =================================================
      // INPUT (พื้นเทาอ่อน ไม่มีเส้นขอบ จนกว่าจะกด)
      // =================================================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 17,
          vertical: 16,
        ),
        labelStyle: TextStyle(
          color: p.muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: p.primary,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: p.muted.withValues(alpha: 0.8),
          fontSize: 13.5,
        ),
        helperStyle: TextStyle(color: p.muted, fontSize: 10),
        prefixIconColor: p.muted,
        suffixIconColor: p.muted,
        border: inputBorder(Colors.transparent),
        enabledBorder: inputBorder(Colors.transparent),
        focusedBorder: inputBorder(p.primary, 1.6),
        errorBorder: inputBorder(p.danger),
        focusedErrorBorder: inputBorder(p.danger, 1.6),
      ),

      // =================================================
      // BUTTONS
      // =================================================
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.primary.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          minimumSize: const Size(double.infinity, 52),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      // =================================================
      // CARD (ไม่มีเส้นขอบ)
      // =================================================
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),

      listTileTheme: ListTileThemeData(iconColor: p.muted, textColor: p.navy),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : p.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.primary : p.fill,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : p.border,
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: p.fill,
        selectedColor: p.softPrimary,
        side: BorderSide.none,
        labelStyle: TextStyle(color: p.navy, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),

      // =================================================
      // NAVIGATION BAR (หน้าหลักใช้แถบลอยของตัวเอง)
      // =================================================
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primary.withValues(alpha: 0.13),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: TextStyle(
          color: p.navy,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          color: p.muted,
          fontSize: 13.5,
          height: 1.5,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        dragHandleColor: p.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.softPrimary,
      ),

      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF2B3039)
            : const Color(0xFF101828),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: const Color(0xFFB4B7FF),
        elevation: 5,
        insetPadding: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: TextStyle(
          color: p.navy,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        headerBackgroundColor: p.primary,
        headerForegroundColor: Colors.white,
      ),

      timePickerTheme: TimePickerThemeData(backgroundColor: p.surface),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
