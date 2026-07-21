// Shows: an adaptive app shell that picks its navigation affordance purely from
// window width (NavigationBar -> NavigationRail -> NavigationDrawer), using the
// shared WindowSizeClass enum and MediaQuery.sizeOf (never Platform checks).
// Domain: a generic Product browser with a few top-level destinations.

import 'package:flutter/material.dart';

/// STANDARD Material 3 window size classes — structural breakpoints, not tokens.
enum WindowSizeClass { compact, medium, expanded, large, extraLarge }

WindowSizeClass windowSizeClassFor(double width) => switch (width) {
      < 600 => WindowSizeClass.compact,
      < 840 => WindowSizeClass.medium,
      < 1200 => WindowSizeClass.expanded,
      < 1600 => WindowSizeClass.large,
      _ => WindowSizeClass.extraLarge,
    };

extension WindowSizeClassX on WindowSizeClass {
  bool get canShowTwoPanes => index >= WindowSizeClass.expanded.index;
}

@immutable
class NavItem {
  const NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// One shell, one width->affordance decision. Screens never pick their own nav.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.body,
  });

  final List<NavItem> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    // sizeOf: rebuilds only when the window SIZE changes, not on every
    // keyboard/textScale/rotation MediaQuery change.
    final sizeClass = windowSizeClassFor(MediaQuery.sizeOf(context).width);

    return switch (sizeClass) {
      WindowSizeClass.compact => Scaffold(
          body: SafeArea(bottom: false, child: body),
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelect,
            destinations: [
              for (final d in destinations)
                NavigationDestination(icon: Icon(d.icon), label: d.label),
            ],
          ),
        ),
      WindowSizeClass.medium ||
      WindowSizeClass.expanded =>
        Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  extended: sizeClass == WindowSizeClass.expanded,
                  labelType: sizeClass == WindowSizeClass.expanded
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelect,
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      WindowSizeClass.large ||
      WindowSizeClass.extraLarge =>
        Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationDrawer(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelect,
                  children: [
                    for (final d in destinations)
                      NavigationDrawerDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
    };
  }
}

/// Demonstrates the shell hosting a width-capped body so text stays readable
/// even on an extra-large desktop window.
class ProductShellDemo extends StatefulWidget {
  const ProductShellDemo({super.key});

  @override
  State<ProductShellDemo> createState() => _ProductShellDemoState();
}

class _ProductShellDemoState extends State<ProductShellDemo> {
  int _index = 0;

  static const _destinations = [
    NavItem(icon: Icons.storefront_outlined, label: 'Catalog'),
    NavItem(icon: Icons.receipt_long_outlined, label: 'Orders'),
    NavItem(icon: Icons.account_circle_outlined, label: 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      destinations: _destinations,
      selectedIndex: _index,
      onSelect: (i) => setState(() => _index = i),
      body: Center(
        // Cap the readable measure; never full-bleed body text on desktop.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            // Placeholder spacing — real spacing tokens come from
            // `design-system-structure`; only the width cap here is structural.
            padding: const EdgeInsets.all(16),
            children: [
              Text('Section ${_destinations[_index].label}',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16), // placeholder spacing
              for (var i = 0; i < 12; i++)
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('Product #$i'),
                  // No fixed height: the tile grows with the text scale.
                  subtitle: const Text('A short description of the product.'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
