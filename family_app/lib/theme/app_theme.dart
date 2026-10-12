import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class AppColors {
  static const Color navy =
      Color(0xFF111827);

  static const Color primary =
      Color(0xFF5B5FEF);

  static const Color primaryDark =
      Color(0xFF4246D9);

  static const Color sky =
      Color(0xFF4CC9F0);

  static const Color warm =
      Color(0xFFFFB86B);

  static const Color background =
      Color(0xFFF6F7FB);

  static const Color surface =
      Colors.white;

  static const Color border =
      Color(0xFFE7E9F2);

  static const Color muted =
      Color(0xFF667085);

  static const Color danger =
      Color(0xFFE5484D);

  static const Color success =
      Color(0xFF2E9D6A);

  static const Color softPrimary =
      Color(0xFFF0F1FF);

  static const Color softSky =
      Color(0xFFEDF9FD);

  static const Color softWarm =
      Color(0xFFFFF6EC);
}

class AppTheme {
  static ThemeData light() {
    final ColorScheme colorScheme =
        ColorScheme.fromSeed(
      seedColor:
          AppColors.primary,
      brightness:
          Brightness.light,
    ).copyWith(
      primary:
          AppColors.primary,
      secondary:
          AppColors.sky,
      surface:
          Colors.white,
      error:
          AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,

      colorScheme:
          colorScheme,

      scaffoldBackgroundColor:
          AppColors.background,

      // =================================================
      // TYPOGRAPHY
      // =================================================

      textTheme:
          const TextTheme(
        headlineLarge:
            TextStyle(
          color:
              AppColors.navy,
          fontSize: 30,
          fontWeight:
              FontWeight.w800,
          height: 1.15,
        ),

        headlineMedium:
            TextStyle(
          color:
              AppColors.navy,
          fontSize: 24,
          fontWeight:
              FontWeight.w800,
          height: 1.2,
        ),

        titleLarge:
            TextStyle(
          color:
              AppColors.navy,
          fontSize: 20,
          fontWeight:
              FontWeight.w800,
        ),

        titleMedium:
            TextStyle(
          color:
              AppColors.navy,
          fontSize: 16,
          fontWeight:
              FontWeight.w700,
        ),

        bodyLarge:
            TextStyle(
          color:
              AppColors.navy,
          fontSize: 15,
          height: 1.5,
        ),

        bodyMedium:
            TextStyle(
          color:
              AppColors.muted,
          fontSize: 13,
          height: 1.45,
        ),

        bodySmall:
            TextStyle(
          color:
              AppColors.muted,
          fontSize: 11,
          height: 1.4,
        ),
      ),

      // =================================================
      // APP BAR
      // =================================================

      appBarTheme:
          const AppBarTheme(
        backgroundColor:
            AppColors.background,

        foregroundColor:
            AppColors.navy,

        elevation: 0,

        scrolledUnderElevation: 0,

        centerTitle: false,

        surfaceTintColor:
            Colors.transparent,

        titleTextStyle:
            TextStyle(
          color:
              AppColors.navy,
          fontSize: 20,
          fontWeight:
              FontWeight.w800,
        ),
      ),

      // =================================================
      // INPUT
      // =================================================

      inputDecorationTheme:
          InputDecorationTheme(
        filled: true,

        fillColor:
            Colors.white,

        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 17,
          vertical: 17,
        ),

        labelStyle:
            const TextStyle(
          color:
              AppColors.muted,
          fontSize: 13,
          fontWeight:
              FontWeight.w500,
        ),

        floatingLabelStyle:
            const TextStyle(
          color:
              AppColors.primary,
          fontWeight:
              FontWeight.w700,
        ),

        hintStyle:
            const TextStyle(
          color:
              Color(
            0xFF98A2B3,
          ),
          fontSize: 13,
        ),

        helperStyle:
            const TextStyle(
          color:
              AppColors.muted,
          fontSize: 10,
        ),

        prefixIconColor:
            AppColors.muted,

        suffixIconColor:
            AppColors.muted,

        border:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          borderSide:
              const BorderSide(
            color:
                AppColors.border,
          ),
        ),

        enabledBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          borderSide:
              const BorderSide(
            color:
                AppColors.border,
          ),
        ),

        focusedBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          borderSide:
              const BorderSide(
            color:
                AppColors.primary,
            width: 1.7,
          ),
        ),

        errorBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          borderSide:
              const BorderSide(
            color:
                AppColors.danger,
          ),
        ),

        focusedErrorBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          borderSide:
              const BorderSide(
            color:
                AppColors.danger,
            width: 1.7,
          ),
        ),
      ),

      // =================================================
      // ELEVATED BUTTON
      // =================================================

      elevatedButtonTheme:
          ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
          backgroundColor:
              AppColors.primary,

          foregroundColor:
              Colors.white,

          disabledBackgroundColor:
              AppColors.primary
                  .withValues(
            alpha: 0.35,
          ),

          disabledForegroundColor:
              Colors.white70,

          elevation: 0,

          minimumSize:
              const Size(
            double.infinity,
            56,
          ),

          padding:
              const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 15,
          ),

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              18,
            ),
          ),

          textStyle:
              const TextStyle(
            fontSize: 15,
            fontWeight:
                FontWeight.w700,
          ),
        ),
      ),

      // =================================================
      // FILLED BUTTON
      // =================================================

      filledButtonTheme:
          FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
          backgroundColor:
              AppColors.primary,

          foregroundColor:
              Colors.white,

          elevation: 0,

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              15,
            ),
          ),

          textStyle:
              const TextStyle(
            fontWeight:
                FontWeight.w700,
          ),
        ),
      ),

      // =================================================
      // OUTLINED BUTTON
      // =================================================

      outlinedButtonTheme:
          OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
          foregroundColor:
              AppColors.primary,

          minimumSize:
              const Size(
            double.infinity,
            54,
          ),

          side:
              const BorderSide(
            color:
                AppColors.border,
          ),

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              18,
            ),
          ),

          textStyle:
              const TextStyle(
            fontSize: 14,
            fontWeight:
                FontWeight.w700,
          ),
        ),
      ),

      // =================================================
      // TEXT BUTTON
      // =================================================

      textButtonTheme:
          TextButtonThemeData(
        style:
            TextButton.styleFrom(
          foregroundColor:
              AppColors.primary,

          textStyle:
              const TextStyle(
            fontWeight:
                FontWeight.w700,
          ),
        ),
      ),

      // =================================================
      // CARD
      // =================================================

      cardTheme:
          CardThemeData(
        elevation: 0,

        color:
            Colors.white,

        surfaceTintColor:
            Colors.transparent,

        margin:
            const EdgeInsets.symmetric(
          vertical: 6,
        ),

        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(
            22,
          ),

          side:
              const BorderSide(
            color:
                AppColors.border,
          ),
        ),
      ),

      // =================================================
      // NAVIGATION BAR
      // =================================================

      navigationBarTheme:
          NavigationBarThemeData(
        height: 72,

        elevation: 0,

        backgroundColor:
            Colors.white,

        surfaceTintColor:
            Colors.transparent,

        indicatorColor:
            AppColors.primary
                .withValues(
          alpha: 0.12,
        ),

        iconTheme:
            WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(
              WidgetState.selected,
            )) {
              return const IconThemeData(
                color:
                    AppColors.primary,
                size: 24,
              );
            }

            return const IconThemeData(
              color:
                  AppColors.muted,
              size: 22,
            );
          },
        ),

        labelTextStyle:
            WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(
              WidgetState.selected,
            )) {
              return const TextStyle(
                color:
                    AppColors.navy,
                fontSize: 11,
                fontWeight:
                    FontWeight.w800,
              );
            }

            return const TextStyle(
              color:
                  AppColors.muted,
              fontSize: 10,
              fontWeight:
                  FontWeight.w600,
            );
          },
        ),
      ),

      // =================================================
      // FLOATING BUTTON
      // =================================================

      floatingActionButtonTheme:
          const FloatingActionButtonThemeData(
        backgroundColor:
            AppColors.primary,

        foregroundColor:
            Colors.white,

        elevation: 4,

        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(
            Radius.circular(
              18,
            ),
          ),
        ),
      ),

      // =================================================
      // DIALOG
      // =================================================

      dialogTheme:
          DialogThemeData(
        backgroundColor:
            Colors.white,

        surfaceTintColor:
            Colors.transparent,

        elevation: 8,

        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(
            28,
          ),
        ),

        titleTextStyle:
            const TextStyle(
          color:
              AppColors.navy,
          fontSize: 19,
          fontWeight:
              FontWeight.w800,
        ),

        contentTextStyle:
            const TextStyle(
          color:
              AppColors.muted,
          fontSize: 13,
          height: 1.5,
        ),
      ),

      // =================================================
      // BOTTOM SHEET
      // =================================================

      bottomSheetTheme:
          const BottomSheetThemeData(
        backgroundColor:
            Colors.white,

        surfaceTintColor:
            Colors.transparent,

        showDragHandle: false,

        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(
            top:
                Radius.circular(
              30,
            ),
          ),
        ),
      ),

      // =================================================
      // PROGRESS
      // =================================================

      progressIndicatorTheme:
          const ProgressIndicatorThemeData(
        color:
            AppColors.primary,

        linearTrackColor:
            AppColors.softPrimary,
      ),

      // =================================================
      // DIVIDER
      // =================================================

      dividerTheme:
          const DividerThemeData(
        color:
            AppColors.border,

        thickness: 1,

        space: 1,
      ),

      // =================================================
      // SNACKBAR
      // =================================================

      snackBarTheme:
          SnackBarThemeData(
        behavior:
            SnackBarBehavior.floating,

        backgroundColor:
            AppColors.navy,

        contentTextStyle:
            const TextStyle(
          color:
              Colors.white,

          fontSize: 13,

          fontWeight:
              FontWeight.w500,
        ),

        elevation: 5,

        insetPadding:
            const EdgeInsets.all(
          14,
        ),

        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(
            16,
          ),
        ),
      ),

      // =================================================
      // POPUP MENU
      // =================================================

      popupMenuTheme:
          PopupMenuThemeData(
        color:
            Colors.white,

        surfaceTintColor:
            Colors.transparent,

        elevation: 5,

        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(
            18,
          ),
        ),

        textStyle:
            const TextStyle(
          color:
              AppColors.navy,
          fontSize: 13,
          fontWeight:
              FontWeight.w600,
        ),
      ),

      // =================================================
      // DATE PICKER
      // =================================================

      datePickerTheme:
          DatePickerThemeData(
        backgroundColor:
            Colors.white,

        surfaceTintColor:
            Colors.transparent,

        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(
            28,
          ),
        ),

        headerBackgroundColor:
            AppColors.primary,

        headerForegroundColor:
            Colors.white,
      ),

      // =================================================
      // PAGE TRANSITIONS
      // =================================================

      pageTransitionsTheme:
          const PageTransitionsTheme(
        builders: {
          TargetPlatform.android:
              ZoomPageTransitionsBuilder(),

          TargetPlatform.iOS:
              CupertinoPageTransitionsBuilder(),

          TargetPlatform.windows:
              ZoomPageTransitionsBuilder(),

          TargetPlatform.macOS:
              CupertinoPageTransitionsBuilder(),

          TargetPlatform.linux:
              ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}