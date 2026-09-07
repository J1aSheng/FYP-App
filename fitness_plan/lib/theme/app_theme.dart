import 'package:flutter/material.dart';

/// Centralized design tokens for the Diet & Workout Planner.
///
/// Everything visual on the home screen (colors, radii, spacing, the
/// repeated "white card" surface) is pulled from here instead of being
/// hardcoded inline. This means:
///   1. Restyling the app (rebrand, dark mode, etc.) is a one-file change.
///   2. Every card/section looks visually consistent by construction —
///      you can't accidentally give one card a slightly different shadow.

class AppColors {
  AppColors._();

  // Brand / primary
  static const primary = Color(0xFF2E7D32);
  static const primaryLight = Color(0xFFE8F5E9);
  static const accentGreen = Color(0xFF8BC34A);
  static const gradientStart = Color(0xFF1B5E20);
  static const gradientEnd = Color(0xFF4CAF50);

  // Water tracker accent
  static const water = Color(0xFF5C7CFA);
  static const waterLight = Color(0xFFEDF2FF);

  // Status
  static const danger = Colors.redAccent;
  static const warning = Colors.orangeAccent;
  static const info = Colors.blueAccent;

  // Neutral
  static const surface = Colors.white;
  static const background = Color(0xFFF7F8FA);
  static const textPrimary = Colors.black;
  static const textMuted = Colors.grey;
}

class AppRadius {
  AppRadius._();
  static const sm = 12.0;
  static const md = 15.0;
  static const lg = 20.0;
  static const xl = 25.0;
  static const xxl = 30.0;
}

class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const xl = 25.0;
  static const xxl = 30.0;
}

class AppShadows {
  AppShadows._();
  static List<BoxShadow> card = [
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];
}

class AppText {
  AppText._();

  static const sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const sectionSub = TextStyle(
    color: AppColors.primary,
    fontSize: 12,
    fontWeight: FontWeight.bold,
  );

  static const cardTitle = TextStyle(fontWeight: FontWeight.bold, fontSize: 16);

  static const muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
}

/// The single reusable "white surface" card used across the home screen
/// (calorie card, meal rows, water tracker, workout rows, activity rows).
/// Change padding/radius/shadow here and every card updates together.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Border? border;
  final EdgeInsetsGeometry? margin;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadius.xl,
    this.border,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.card,
        border: border,
      ),
      child: child,
    );
  }
}

/// Consistent section header: bold title + small colored eyebrow/subtitle,
/// spaced apart. Used for "Calorie History", "AI Activity Suggestions", etc.
class AppSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const AppSectionHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppText.sectionTitle),
        Text(subtitle, style: AppText.sectionSub),
      ],
    );
  }
}

/// Simple centered empty-state block for lists that can legitimately be
/// empty (no meals logged yet, no AI suggestions available, etc.).
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const AppEmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.muted,
          ),
        ],
      ),
    );
  }
}
