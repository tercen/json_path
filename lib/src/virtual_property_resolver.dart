/// Interface for resolving virtual (computed) properties on JSON nodes.
///
/// Unlike [VirtualHierarchyResolver] which fetches external documents from
/// a database, [VirtualPropertyResolver] resolves properties computed from
/// data already present in the document (intra-document relationships).
///
/// Example use case: Step graph navigation within a Workflow document,
/// where `parentSteps`, `childSteps`, etc. are computed from the `links`
/// and `steps` arrays in the same Workflow.
abstract class VirtualPropertyResolver {
  /// Check if a property name is a virtual property handled by this resolver.
  bool isVirtualProperty(String propertyName);

  /// Resolve a virtual property value.
  ///
  /// [currentNode] - The node on which the property is being accessed
  /// [rootNode] - The root document node (for accessing related data)
  /// [propertyName] - The virtual property being accessed
  ///
  /// Returns the computed property value (typically a List for navigation
  /// properties), or null if the property cannot be resolved for this node.
  Future<dynamic> resolveProperty(
    Map<String, dynamic> currentNode,
    Map<String, dynamic> rootNode,
    String propertyName,
  );
}
