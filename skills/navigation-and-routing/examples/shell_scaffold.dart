// An adaptive tab-shell scaffold for a StatefulShellRoute.indexedStack: it picks
// NavigationRail vs NavigationBar by the Material 3 window size class, preserves
// each branch's state, and shows a reduced-motion-aware transition + PopScope.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The shell chrome. Receives the [StatefulNavigationShell] from the router's
/// StatefulShellRoute.indexedStack builder; branch state is preserved for free.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = <_Dest>[
    _Dest(Icons.home_outlined, Icons.home, 'Home'),
    _Dest(Icons.inventory_2_outlined, Icons.inventory_2, 'Items'),
    _Dest(Icons.person_outline, Icons.person, 'Account'),
  ];

  void _goBranch(int index) => navigationShell.goBranch(
        index,
        // Re-tapping the active tab returns that branch to its root.
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    // Structural Material 3 size class — not a design token.
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 600; // adaptive-layout owns this breakpoint

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _goBranch,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// A reduced-motion-aware page factory to hand a GoRoute.pageBuilder.
/// Collapses the slide to a plain child when the platform requests reduced motion.
Page<void> buildAdaptivePage(BuildContext context, Widget child, LocalKey key) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionsBuilder: (context, animation, secondary, child) {
      if (reduceMotion) return child;
      return SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
  );
}

/// An edit screen that blocks an accidental back with unsaved changes.
/// Uses PopScope (WillPopScope is removed) and guards context across the await.
class EditItemScreen extends StatefulWidget {
  const EditItemScreen({super.key, required this.itemId});
  final String itemId;
  @override
  State<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  bool _dirty = false;

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_dirty, // clean form => system back works normally
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return; // already popped; nothing to intercept
        final leave = await _confirmDiscard();
        if (leave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Edit ${widget.itemId}')),
        // Spacing/padding come from the design system's tokens (owned by
        // design-system-structure) — omitted here to keep the focus on navigation.
        body: TextField(
          onChanged: (_) => setState(() => _dirty = true),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
      ),
    );
  }
}
