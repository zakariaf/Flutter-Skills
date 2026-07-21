// Demonstrates the tokens -> theme -> shapes layering: primitives named by
// MEASURED value, semantic ThemeExtensions read through an asserting of(context),
// a hand-authored ColorScheme (never ColorScheme.fromSeed), honest copyWith/lerp,
// and one-shot injection at the composition root. All hex/radii are illustrative
// placeholders owned by your design source of truth; this file lives in lib/theme/,
// the ONLY directory where a raw aesthetic value may appear.
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// TIER 1 — primitives. Named by measured value (here: OKLCH lightness x100),
// never by rank ("grey700"), appearance ("darkGrey"), or brand ("brandPrimary").
// ---------------------------------------------------------------------------
abstract final class Primitives {
  static const neutral08 = Color(0xFF141414); // L .08 — ink
  static const neutral40 = Color(0xFF636363);
  static const neutral88 = Color(0xFFDCDCDC);
  static const neutral96 = Color(0xFFF4F4F4); // L .96 — paper
  static const accent45 = Color(0xFF3A6FF0);
  static const accent62 = Color(0xFF7CA2F7);
  static const danger45 = Color(0xFFC1362B);
  static const danger62 = Color(0xFFE98177);
}

// ---------------------------------------------------------------------------
// TIER 2 — semantic color slots. Widgets read THESE, never a primitive.
// ---------------------------------------------------------------------------
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surface,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.accent,
    required this.danger,
    required this.hairline,
    required this.hairlineWidth,
  });

  final Color surface;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color accent;
  final Color danger;
  final Color hairline;
  final double hairlineWidth;

  /// Assert, never `?? fallback`: a fallback ships a theme no test verified.
  static AppColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppColors>();
    assert(ext != null, 'AppColors missing. Build ThemeData via buildAppTheme().');
    return ext!;
  }

  @override
  AppColors copyWith({
    Color? surface,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? accent,
    Color? danger,
    Color? hairline,
    double? hairlineWidth,
  }) {
    return AppColors(
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      accent: accent ?? this.accent,
      danger: danger ?? this.danger,
      hairline: hairline ?? this.hairline,
      hairlineWidth: hairlineWidth ?? this.hairlineWidth,
    );
  }

  /// Interpolate every color and double; a forgotten field here is the classic
  /// design-system rot, so list them all.
  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      surface: Color.lerp(surface, other.surface, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineWidth: lerpDouble(hairlineWidth, other.hairlineWidth, t)!,
    );
  }
}

// Light and dark are two Tier-2 instances built from the same primitive pool.
// Dark is hand-tuned (note the raised-luminance accent/danger), never auto-flipped.
const _lightColors = AppColors(
  surface: Primitives.neutral96,
  onSurface: Primitives.neutral08,
  onSurfaceMuted: Primitives.neutral40,
  accent: Primitives.accent45,
  danger: Primitives.danger45,
  hairline: Primitives.neutral88,
  hairlineWidth: 1,
);

const _darkColors = AppColors(
  surface: Primitives.neutral08,
  onSurface: Primitives.neutral96,
  onSurfaceMuted: Primitives.neutral88,
  accent: Primitives.accent62, // raised luminance to survive AA on dark
  danger: Primitives.danger62,
  hairline: Primitives.neutral40,
  hairlineWidth: 1,
);

// ---------------------------------------------------------------------------
// SHAPES — factories, not per-widget radii. A component asks for a silhouette.
// ---------------------------------------------------------------------------
@immutable
class AppShapes extends ThemeExtension<AppShapes> {
  const AppShapes({required this.radiusSmall, required this.radiusCard, required this.spacingUnit});

  final double radiusSmall;
  final double radiusCard;
  final double spacingUnit;

  static AppShapes of(BuildContext context) {
    final ext = Theme.of(context).extension<AppShapes>();
    assert(ext != null, 'AppShapes missing. Build ThemeData via buildAppTheme().');
    return ext!;
  }

  /// The card silhouette — components call this instead of naming a radius, so a
  /// re-shape of the whole system is one edit here.
  RoundedRectangleBorder cardShape({BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard), side: side);

  @override
  AppShapes copyWith({double? radiusSmall, double? radiusCard, double? spacingUnit}) => AppShapes(
        radiusSmall: radiusSmall ?? this.radiusSmall,
        radiusCard: radiusCard ?? this.radiusCard,
        spacingUnit: spacingUnit ?? this.spacingUnit,
      );

  @override
  AppShapes lerp(covariant AppShapes? other, double t) {
    if (other == null) return this;
    return AppShapes(
      radiusSmall: lerpDouble(radiusSmall, other.radiusSmall, t)!,
      radiusCard: lerpDouble(radiusCard, other.radiusCard, t)!,
      spacingUnit: lerpDouble(spacingUnit, other.spacingUnit, t)!,
    );
  }
}

const _shapes = AppShapes(radiusSmall: 8, radiusCard: 16, spacingUnit: 8);

// ---------------------------------------------------------------------------
// THEME BUILDER — folds slots into a hand-authored ColorScheme + attaches every
// extension. Called for BOTH brightnesses; injected once at the root.
// ---------------------------------------------------------------------------
ThemeData buildAppTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? _darkColors : _lightColors;

  // Hand-authored: state every role you read, keep the M3 names so Material
  // widgets theme themselves. NEVER ColorScheme.fromSeed for identity — its
  // per-role overrides do not propagate.
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.surface,
    secondary: c.accent,
    onSecondary: c.surface,
    surface: c.surface,
    onSurface: c.onSurface,
    surfaceContainerHighest: c.surface,
    onSurfaceVariant: c.onSurfaceMuted,
    outline: c.hairline,
    outlineVariant: c.hairline,
    error: c.danger,
    onError: c.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.surface,
    extensions: [c, _shapes], // every extension on BOTH ThemeData instances
  );
}

// ---------------------------------------------------------------------------
// INJECTION — once, at the composition root. themeMode comes from the restored
// setting (see app-startup-and-bootstrap); the theme is never flavor-dependent.
// ---------------------------------------------------------------------------
class App extends StatelessWidget {
  const App({super.key, required this.themeMode});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: themeMode,
      home: const _Demo(),
    );
  }
}

// A consumer widget: every value is a slot read — no raw literal survives.
class _Demo extends StatelessWidget {
  const _Demo();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shapes = AppShapes.of(context);
    return Card(
      shape: shapes.cardShape(side: BorderSide(color: colors.hairline, width: colors.hairlineWidth)),
      child: Padding(
        padding: EdgeInsets.all(shapes.spacingUnit * 2),
        child: Text('Item', style: TextStyle(color: colors.onSurface)),
      ),
    );
  }
}
