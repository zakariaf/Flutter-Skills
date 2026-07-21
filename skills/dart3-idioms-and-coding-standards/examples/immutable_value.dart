// Demonstrates: an immutable value type with a `const` ctor, `final` fields,
// `copyWith`, stable-id identity, and hand-written value equality (this type is
// used as a Set member / map key). Identity is the `id`, NOT equals-on-all-fields
// — two Products sharing a name and price are still two distinct products.

import 'package:meta/meta.dart';

@immutable
final class Product {
  const Product({
    required this.id,
    required this.name,
    required this.priceMinor,
    this.tags = const <String>[],
  });

  /// Stable identity, assigned once. List diffing and selection key off this.
  final String id;

  final String name;

  /// Canonical integer minor units — never a double for money. See
  /// value-objects-money-and-units for the full money discipline.
  final int priceMinor;

  final List<String> tags;

  Product copyWith({String? name, int? priceMinor, List<String>? tags}) =>
      Product(
        id: id,
        name: name ?? this.name,
        priceMinor: priceMinor ?? this.priceMinor,
        tags: tags ?? this.tags,
      );

  // Value equality: this type is used in a Set, so `==`/`hashCode` are defined
  // together and cover exactly the same fields. Identity is included via `id`.
  @override
  bool operator ==(Object other) =>
      other is Product &&
      other.id == id &&
      other.name == name &&
      other.priceMinor == priceMinor &&
      _sameTags(other.tags);

  bool _sameTags(List<String> other) {
    if (other.length != tags.length) return false;
    for (var i = 0; i < tags.length; i++) {
      if (other[i] != tags[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, name, priceMinor, Object.hashAll(tags));
}
