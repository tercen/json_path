/// Represents the hierarchy fetching requirements for a JSONPath query
class VirtualHierarchyPlan {
  final List<CollectionRequirement> requirements;

  VirtualHierarchyPlan(this.requirements);

  /// Check if this plan requires virtual hierarchy support
  bool get needsVirtualHierarchy => requirements.isNotEmpty;

  @override
  String toString() =>
      'VirtualHierarchyPlan(${requirements.length} requirements)';
}

/// Represents one collection that needs to be fetched
class CollectionRequirement {
  final String collection; // 'projects', 'workflows', 'teams'
  final String? parentCollection; // Parent collection in hierarchy
  final List<FilterExpression> filters; // Filters from [?@.property == value]
  final int depth; // Depth in hierarchy (0 = root)

  CollectionRequirement({
    required this.collection,
    this.parentCollection,
    this.filters = const [],
    required this.depth,
  });

  /// Check if this requirement has filters beyond just ID
  bool get hasNonIdFilters => filters.any((f) => f.property != 'id');

  /// Get ID filter value if it exists
  String? get idFilter => filters
      .where((f) => f.property == 'id' && f.operator == '==')
      .map((f) => f.value as String?)
      .firstOrNull;

  @override
  String toString() =>
      'CollectionRequirement($collection, parent: $parentCollection, filters: $filters, depth: $depth)';
}

/// Represents a filter extracted from JSONPath
class FilterExpression {
  final String property; // Property name: 'id', 'name', 'status'
  final String operator; // Operator: '==', '!=', '>', '<', 'in'
  final dynamic value; // Filter value

  FilterExpression({
    required this.property,
    required this.operator,
    required this.value,
  });

  @override
  String toString() => '$property $operator $value';

  @override
  bool operator ==(Object other) =>
      other is FilterExpression &&
      other.property == property &&
      other.operator == operator &&
      other.value == value;

  @override
  int get hashCode => Object.hash(property, operator, value);
}

extension _IterableExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
