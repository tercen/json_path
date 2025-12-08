import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';

/// Analyzes JSONPath expressions to extract hierarchy requirements
class VirtualHierarchyAnalyzer {
  /// Analyze a JSONPath expression and extract what collections need to be fetched
  VirtualHierarchyPlan analyze(String expression) {
    final requirements = <CollectionRequirement>[];

    // Pattern: .collection[filter] or .collection[*]
    // Examples:
    // - .projects[?@.id == 'proj_456']
    // - .workflows[*]
    // - .teams[?@.name == 'Test']
    // Matches: .collection[*] or .collection[?@.prop == 'value']
    final segmentPattern = RegExp(
      r"\.(\w+)\[(?:(\*)|(?:\?@\.(\w+)\s*(==|!=|>|<|>=|<=)\s*'([^']+)'))?]",
    );

    String? prevCollection;
    int depth = 0;

    for (final match in segmentPattern.allMatches(expression)) {
      final collection = match.group(1)!;
      final isWildcard = match.group(2) != null;
      final filterProperty = match.group(3);
      final filterOperator = match.group(4);
      final filterValue = match.group(5);

      final filters = <FilterExpression>[];
      if (!isWildcard && filterProperty != null && filterOperator != null) {
        filters.add(FilterExpression(
          property: filterProperty,
          operator: filterOperator,
          value: filterValue,
        ));
      }

      // Only add if it's a known collection type
      if (_isVirtualCollection(collection)) {
        requirements.add(CollectionRequirement(
          collection: collection,
          parentCollection: prevCollection,
          filters: filters,
          depth: depth,
        ));

        prevCollection = collection;
        depth++;
      }
    }

    return VirtualHierarchyPlan(requirements);
  }

  bool _isVirtualCollection(String key) {
    return const [
      'projects',
      'teams',
      'workflows',
      'schemas',
      'files',
      'folders',
      'operators',
      'tasks',
      'users',
    ].contains(key);
  }
}
