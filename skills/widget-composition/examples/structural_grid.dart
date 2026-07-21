// Demonstrates structural layout: a full-bleed background behind the system bars,
// interactive content in SafeArea, computed cell sizing via the grid delegate
// (no hardcoded/floored tile size), the correct GridView cross/main-axis spacing,
// EdgeInsetsDirectional insets, and resizeToAvoidBottomInset for a fixed layout.
//
// No specific spacing/radius/color VALUES are prescribed here — pull them from the
// theme / a ThemeExtension (see design-system-structure). The constants below are
// illustrative structure, not a design.

import 'package:flutter/material.dart';

class ProductGridScreen extends StatelessWidget {
  const ProductGridScreen({required this.products, super.key});

  final List<ProductTileData> products;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Background paints full-bleed, behind status and nav bars — no SafeArea above.
      backgroundColor: Theme.of(context).colorScheme.surface,
      // A fixed grid must not reflow under the keyboard; overlay instead of squash.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        // The margin is a design choice INSIDE the safe area, not a platform inset.
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16), // logical, RTL-safe
          child: GridView.builder(
            // Size-driven delegate: column count adapts to width; the CELL size is
            // computed, never hardcoded and never floored.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              crossAxisSpacing: 12, // COLUMN gap in a vertical grid (the axis trap)
              mainAxisSpacing: 16,  // ROW gap
              childAspectRatio: 3 / 4,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) => ProductTile(data: products[i]),
          ),
        ),
      ),
    );
  }
}

@immutable
class ProductTileData {
  const ProductTileData({required this.id, required this.name, required this.price});

  final String id;
  final String name;  // already-localized
  final String price; // already-formatted
}

class ProductTile extends StatelessWidget {
  const ProductTile({required this.data, super.key});

  final ProductTileData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The constraint is that the label FITS at any text scale — not a min tile size.
    // No radius/elevation VALUE is baked in here: the surface is a plain color fill;
    // pull a corner shape off the theme (e.g. cardTheme.shape) or a ThemeExtension
    // when you need one. See design-system-structure.
    return ColoredBox( // cheapest widget for a single color fill — no Container
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(data.name, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(data.price, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
