// Demonstrates redundant encoding: a canonical status value object where COLOR IS
// DERIVED LAST and every meaning carries >=3 grayscale-legible signals
// (icon + label + border weight/shape), so state survives color-blindness,
// greyscale, and reduced motion. Depends on AppColors from app_theme.dart.
import 'package:flutter/material.dart';

import 'app_theme.dart';

enum OrderStatus { pending, active, blocked }

extension OrderStatusView on OrderStatus {
  // Signal 1 — glyph. The icons differ in SILHOUETTE, not just hue, so they read
  // in greyscale.
  IconData get icon => switch (this) {
        OrderStatus.pending => Icons.schedule,
        OrderStatus.active => Icons.play_arrow,
        OrderStatus.blocked => Icons.error_outline,
      };

  // Signal 2 — the word. In a real app this routes through gen-l10n; kept literal
  // here so the example is self-contained.
  String get label => switch (this) {
        OrderStatus.pending => 'Pending',
        OrderStatus.active => 'Active',
        OrderStatus.blocked => 'Blocked',
      };

  // Signal 3 — border weight, MONOTONIC with severity: a fully color-blind user
  // reads severity from the heavier outline.
  double get borderWidth => this == OrderStatus.blocked ? 2 : 1;

  // Color is DECORATION, derived LAST from the enum — never the source of truth.
  Color color(AppColors c) => switch (this) {
        OrderStatus.pending => c.onSurfaceMuted,
        OrderStatus.active => c.accent,
        OrderStatus.blocked => c.danger,
      };
}

/// Renders all three non-color signals plus color as a supporting fourth. Strip
/// the color and the icon + word + weight still convey the state.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shapes = AppShapes.of(context);
    final tint = status.color(colors);

    return MergeSemantics(
      child: Semantics(
        label: 'Order status',
        value: status.label,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: shapes.spacingUnit, vertical: shapes.spacingUnit / 2),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(shapes.radiusSmall),
            border: Border.all(color: tint, width: status.borderWidth),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(status.icon, size: 16, color: tint),
              SizedBox(width: shapes.spacingUnit / 2),
              Text(status.label, style: TextStyle(color: colors.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}
