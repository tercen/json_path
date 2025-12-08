import 'package:tercen_json_path/src/ref_id_resolver.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';

/// Extended resolver that supports virtual hierarchy fetching
abstract class VirtualHierarchyResolver extends RefIdResolver {
  /// Pre-fetch all collections required by the hierarchy plan
  /// Called once before JSONPath evaluation begins
  Future<void> prefetchHierarchy(VirtualHierarchyPlan plan, dynamic rootJson);

  /// Resolve a collection with context
  /// Called during JSONPath evaluation when a collection is accessed
  Future<List<Map<String, dynamic>>> resolveCollection(
    String collection,
    VirtualHierarchyContext context,
  );
}

/// Context for resolving a collection
class VirtualHierarchyContext {
  final String? parentCollection; // Parent collection name
  final String? parentId; // Parent document ID
  final Map<String, dynamic> metadata; // Additional context

  VirtualHierarchyContext({
    this.parentCollection,
    this.parentId,
    this.metadata = const {},
  });

  @override
  String toString() =>
      'VirtualHierarchyContext(parent: $parentCollection/$parentId)';
}
