import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/app_theme.dart';
import 'router/app_router.dart';

class NirmanApp extends ConsumerWidget {
  const NirmanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Nirman CRM',
      theme: _buildTheme(),
      routerConfig: appRouter,
    );
  }
}

ThemeData _buildTheme() {
  final base = ThemeData(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surfaceBase,
    colorScheme: ColorScheme.light(
      primary:    AppColors.accentStrong,
      secondary:  AppColors.accent,
      surface:    AppColors.surfaceBase,
      onPrimary:  AppColors.surfaceBase,
      onSecondary: AppColors.surfaceBase,
      onSurface:  AppColors.inkPrimary,
      error:      AppColors.error,
    ),
    // Source Serif Pro for display headings; Inter (system) for body
    textTheme: GoogleFonts.sourceSerif4TextTheme(base.textTheme).copyWith(
      bodyMedium: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        color: AppColors.inkPrimary,
      ),
      bodySmall: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: AppColors.inkSecondary,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: AppColors.surfaceBase,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accentStrong,
      foregroundColor: AppColors.surfaceBase,
      elevation: 3,
    ),
    dividerColor: AppColors.borderHairline,
  );
}
