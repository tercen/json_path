import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';

/// Analyzes JSONPath expressions to extract hierarchy requirements
class VirtualHierarchyAnalyzer {
  /// Analyze a JSONPath expression and extract what collections need to be fetched
  VirtualHierarchyPlan analyze(String expression) {
    final requirements = <CollectionRequirement>[];

    // Pattern: .collection[filter] or .collection[*]
    // This pattern captures the entire filter content for further parsing
    // Examples:
    // - .projects[?@.id == 'proj_456']
    // - .workflows[*]
    // - .teams[?@.name == 'Test']
    // - .projectDocuments[?@.id=='xxx' || @.id=='yyy']
    final segmentPattern = RegExp(
      r"\.(\w+)\[(\*|\?[^\]]+)?]",
    );

    // Pattern for individual filter conditions
    final filterConditionPattern = RegExp(
      r"@\.(\w+)\s*(==|!=|>|<|>=|<=)\s*'([^']+)'",
    );

    String? prevCollection;
    int depth = 0;

    for (final match in segmentPattern.allMatches(expression)) {
      final collection = match.group(1)!;
      final filterContent = match.group(2);

      final isWildcard = filterContent == '*';
      final filters = <FilterExpression>[];
      var logicalOperator = FilterLogicalOperator.and;

      if (!isWildcard && filterContent != null && filterContent.startsWith('?')) {
        // Remove the leading '?' to get the filter expression
        final filterExpr = filterContent.substring(1);

        // Check if this is an OR expression
        if (filterExpr.contains('||')) {
          logicalOperator = FilterLogicalOperator.or;
        }

        // Parse all filter conditions (handles both single and OR'ed conditions)
        for (final condMatch in filterConditionPattern.allMatches(filterExpr)) {
          filters.add(FilterExpression(
            property: condMatch.group(1)!,
            operator: condMatch.group(2)!,
            value: condMatch.group(3),
          ));
        }
      }

      // Only add if it's a known collection type
      if (_isVirtualCollection(collection)) {
        requirements.add(CollectionRequirement(
          collection: collection,
          parentCollection: prevCollection,
          filters: filters,
          filterOperator: logicalOperator,
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
      'projectDocuments',
    ].contains(key);
  }
}
