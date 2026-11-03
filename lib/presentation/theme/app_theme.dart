import 'app_icons.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Core Palette ─────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF7C3AED); // Deep violet
  static const Color primaryLight = Color(0xFFA855F7); // Soft violet
  static const Color accent = Color(0xFF06B6D4); // Cyan accent

  // Semantic
  static const Color income = Color(0xFF15803D);
  static const Color expense = Color(0xFFBE123C);

  // ── Legacy aliases (so existing code compiles unchanged) ─────────────────
  static const Color primaryColor = primary;
  static const Color secondaryColor = primaryLight;
  static const Color accentColor = accent;
  static const Color successColor = income;
  static const Color errorColor = expense;

  // Dark palette
  static const Color darkBg = Color(0xFF09090B); // Zinc-950
  static const Color darkSurface = Color(0xFF18181B); // Zinc-900
  static const Color darkElevated = Color(
    0xFF27272A,
  ); // Zinc-800 (chips, pills)
  static const Color darkBorder = Color(0xFF3F3F46); // Zinc-700
  static const Color darkTextPrimary = Color(0xFFFAFAFA);
  static const Color darkTextSecondary = Color(0xFFA1A1AA); // Zinc-400
  static const Color darkTextMuted = Color(0xFF94949E); // Zinc-500

  // Light palette
  static const Color lightBg = Color(0xFFF4F4F5); // Zinc-100
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFE4E4E7); // Zinc-200
  static const Color lightBorder = Color(0xFFD4D4D8); // Zinc-300
  static const Color lightTextPrimary = Color(0xFF09090B);
  static const Color lightTextSecondary = Color(0xFF52525B);
  static const Color lightTextMuted = Color(0xFF62626B);

  static ThemeData get darkTheme => _build(Brightness.dark);
  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    // Inter weights are bundled with the app; typography never needs a network request.
    GoogleFonts.config.allowRuntimeFetching = false;
    final dark = brightness == Brightness.dark;
    final bg = dark ? darkBg : lightBg;
    final surface = dark ? darkSurface : lightSurface;
    final border = dark ? darkBorder : lightBorder;
    final textPrimary = dark ? darkTextPrimary : lightTextPrimary;
    final textSecondary = dark ? darkTextSecondary : lightTextSecondary;
    final actionText = dark ? const Color(0xFFC4B5FD) : primary;

    // Inter — tight, legible, designed for data UIs
    final baseText = GoogleFonts.interTextTheme(
      dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      primaryColor: primary,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: Colors.white,
        secondary: primaryLight,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        background: bg,
        onBackground: textPrimary,
        error: expense,
        onError: Colors.white,
        // Expose as surfaceVariant for "chip/pill" surfaces
        surfaceVariant: dark ? darkElevated : lightElevated,
        onSurfaceVariant: textSecondary,
      ),
      textTheme: baseText.copyWith(
        // Hero number (balance)
        displayLarge: GoogleFonts.inter(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.5,
          color: textPrimary,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          color: textPrimary,
        ),
        displaySmall: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: textPrimary,
        ),
        // Section headers
        headlineMedium: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        // Labels
        titleLarge: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textPrimary,
          letterSpacing: 0.1,
        ),
        // Body
        bodyLarge: GoogleFonts.inter(fontSize: 15, color: textPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: textPrimary),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          color: textSecondary,
          letterSpacing: 0.2,
        ),
        // Captions
        labelLarge: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: textSecondary,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFFE4E4E7)
            : const Color(0xFF27272A),
        contentTextStyle: baseText.bodyMedium?.copyWith(
          color: dark ? const Color(0xFF18181B) : Colors.white,
        ),
        actionTextColor: dark
            ? const Color(0xFF6D28D9)
            : const Color(0xFFD8B4FE),
        showCloseIcon: true,
        closeIconColor: dark ? const Color(0xFF18181B) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: baseText.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: baseText.bodyMedium?.copyWith(color: textSecondary),
      ),

      // Cards — sharp, minimal
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: 1),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: actionText,
          side: BorderSide(color: border),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          iconSize: AppIcons.actionSize,
          foregroundColor: actionText,
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: .12),
        position: PopupMenuPosition.under,
        menuPadding: const EdgeInsets.all(6),
        iconColor: textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border.withValues(alpha: .65)),
        ),
        textStyle: baseText.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
      ),

      // Bottom nav
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primary
                : textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.inter(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? primary
                : textSecondary,
          ),
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        padding: EdgeInsets.zero,
      ),

      // App bar
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(
          color: textSecondary,
          size: AppIcons.actionSize,
        ),
      ),

      // Dividers
      dividerTheme: DividerThemeData(color: border, thickness: 0.5, space: 0),

      // Chips (source badges)
      chipTheme: ChipThemeData(
        backgroundColor: dark ? darkElevated : lightElevated,
        labelStyle: GoogleFonts.inter(
          fontSize: 10,
          color: textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),

      // Input fields — compact
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? darkElevated : const Color(0xFFF9F9FC),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: textSecondary),
        labelStyle: GoogleFonts.inter(fontSize: 13, color: textSecondary),
      ),

      // Elevated button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: actionText,
          minimumSize: const Size(48, 48),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: CircleBorder(),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? primary.withOpacity(0.3)
              : null,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        headerBackgroundColor: primary.withValues(alpha: .07),
        headerForegroundColor: textPrimary,
        headerHeadlineStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        dayStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        weekdayStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
        dayShape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : states.contains(WidgetState.disabled)
              ? textSecondary.withValues(alpha: .4)
              : textPrimary,
        ),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : actionText,
        ),
        todayBorder: BorderSide(color: actionText),
        rangePickerBackgroundColor: surface,
        rangePickerHeaderBackgroundColor: primary.withValues(alpha: .07),
        rangePickerHeaderForegroundColor: textPrimary,
        rangePickerHeaderHeadlineStyle: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        rangeSelectionBackgroundColor: primary.withValues(
          alpha: dark ? .25 : .12,
        ),
        yearStyle: GoogleFonts.inter(fontSize: 14),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: textSecondary),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: actionText,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ─── Shared UI helpers ────────────────────────────────────────────────────────

/// Thin coloured left-bar used on transaction rows
class BarIndicator extends StatelessWidget {
  final Color color;
  const BarIndicator({super.key, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 3,
    height: 36,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// Monochrome icon container for transaction categories
class TxnIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const TxnIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: size * 0.50, color: color),
    );
  }
}

/// Compact stat tile used in summary rows
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final IconData icon;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: valueColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Legacy alias kept so existing code referencing GlassContainer compiles
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? height;
  final double? width;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 12,
    this.opacity = 0.1,
    this.borderRadius,
    this.padding,
    this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(10),
        border: Border.all(
          color: (dark ? Colors.white : Colors.black).withOpacity(0.12),
          width: 1,
        ),
        color: (dark ? Colors.white : Colors.black).withOpacity(0.06),
      ),
      child: child,
    );
  }
}
