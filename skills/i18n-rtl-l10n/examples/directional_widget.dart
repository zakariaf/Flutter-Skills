// Demonstrates: an RTL-safe feature widget that mirrors BY CONSTRUCTION when the
// resolved locale is RTL — directional-only geometry, an ICU/localized string, a
// bidi-isolated strong-LTR technical ID, native-digit number formatting at the edge,
// and correct icon mirroring. No per-widget direction conditionals for layout.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// In a real app these come from your generated l10n + a shared l10n helper library.
// Shown inline here so the file is self-contained.

const _lri = '⁦'; // LEFT-TO-RIGHT ISOLATE
const _pdi = '⁩'; // POP DIRECTIONAL ISOLATE

/// Isolate a run whose direction is known to be LTR (codes, references, numbers).
String isolateLtr(String s) => '$_lri$s$_pdi';

/// Stands in for the generated `l10n.orderRef(ref)` — ARB message "Ref: {ref}".
/// The isolated value arrives as a PLACEHOLDER; it is never hard-spliced into a
/// literal at the call site (which would fail the no-literal-in-Text discipline).
String orderRefLine(String ref) => 'Ref: $ref';

/// One formatter per locale. intl emits native digits from each locale's own symbol
/// data (it drops a `-u-nu-` extension), so format with a locale it ships symbols for;
/// ckb has none, so borrow fa — the same arabext digit block.
NumberFormat numberFormatFor(Locale locale) => switch (locale.languageCode) {
      'fa' => NumberFormat.decimalPattern('fa'),
      'ckb' => NumberFormat.decimalPattern('fa'),
      'ar' => NumberFormat.decimalPattern('ar'),
      _ => NumberFormat.decimalPattern('en'),
    };

/// A summary card for an order. Reads correctly under LTR and RTL with no conditionals.
class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({
    super.key,
    required this.title, // user content — preserved verbatim
    required this.reference, // strong-LTR technical ID (e.g. "ORD-2026-014")
    required this.itemCount,
    required this.onOpen,
  });

  final String title;
  final String reference;
  final int itemCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final fmt = numberFormatFor(locale);

    return Padding(
      // GOOD: logical start/end — never EdgeInsets.only(left/right).
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8, top: 12, bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, textAlign: TextAlign.start), // never .left
                // The reference is LTR even inside an RTL card — isolate it, then pass
                // it as a PLACEHOLDER to the localized line (stub here; l10n.orderRef in
                // a real app). Never hard-splice an isolated run into a Text literal.
                Text(
                  orderRefLine(isolateLtr(reference)),
                  textAlign: TextAlign.start,
                ),
                // Count in native digits, formatted at the edge.
                Text(
                  fmt.format(itemCount),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
          // Directional nav icon — auto-mirrors in RTL.
          IconButton(
            icon: Icon(Icons.adaptive.arrow_forward),
            onPressed: onOpen,
          ),
          // A custom directional glyph not in Icons.adaptive — flip manually.
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(
              Directionality.of(context) == TextDirection.rtl ? math.pi : 0,
            ),
            child: const Icon(Icons.trending_up),
          ),
        ],
      ),
    );
  }
}
