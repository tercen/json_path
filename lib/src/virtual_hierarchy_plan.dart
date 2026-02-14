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

/// How multiple filters should be combined
enum FilterLogicalOperator {
  and, // All filters must match (default)
  or, // Any filter can match
  single, // Only one filter condition
}

/// Represents one collection that needs to be fetched
class CollectionRequirement {
  final String collection; // 'projects', 'workflows', 'teams'
  final String? parentCollection; // Parent collection in hierarchy
  final List<FilterExpression> filters; // Filters from [?@.property == value]
  final FilterLogicalOperator filterOperator; // How filters are combined
  final int depth; // Depth in hierarchy (0 = root)

  CollectionRequirement({
    required this.collection,
    this.parentCollection,
    this.filters = const [],
    this.filterOperator = FilterLogicalOperator.and,
    required this.depth,
  });

  /// Check if this requirement has filters beyond just ID
  bool get hasNonIdFilters => filters.any((f) => f.property != 'id');

  /// Check if this requirement uses OR logic for filters
  bool get hasOrFilters => filterOperator == FilterLogicalOperator.or;

  /// Get ID filter value if it exists (single ID case)
  String? get idFilter => filters
      .where((f) => f.property == 'id' && f.operator == '==')
      .map((f) => f.value as String?)
      .firstOrNull;

  /// Get all ID filter values (for OR queries with multiple IDs)
  List<String> get idFilters => filters
      .where((f) => f.property == 'id' && f.operator == '==')
      .map((f) => f.value as String)
      .toList();

  @override
  String toString() =>
      'CollectionRequirement($collection, parent: $parentCollection, filters: $filters, operator: $filterOperator, depth: $depth)';
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
