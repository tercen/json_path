import 'package:tercen_json_path/src/node.dart';
import 'package:tercen_json_path/src/ref_id_resolver.dart';
import 'package:tercen_json_path/src/selector.dart';

/// Creates a selector that dereferences a RefId field to its target object.
///
/// The @ operator syntax: `fieldName@TargetKind`
///
/// Example:
/// ```dart
/// // $.workflows[*].steps[*].operatorId@Operator
/// // For each step, get operatorId value, dereference it as an Operator
/// ```
///
/// Parameters:
/// - [fieldName]: The field containing the RefId (e.g., "operatorId")
/// - [targetKind]: The expected kind of the target document (e.g., "Operator")
/// - [resolver]: The RefIdResolver to use for lookups
///
/// Returns a Selector that:
/// 1. Extracts the RefId value from the specified field
/// 2. Calls resolver.dereference(refId, targetKind) asynchronously
/// 3. Yields the resolved object as a new Node
Selector dereferenceSelector(
  String fieldName,
  String targetKind,
  RefIdResolver? resolver,
) {
  return (Stream<Node> nodes) async* {
    if (resolver == null) {
      // No resolver available - skip dereferencing
      // This allows parsing @ syntax without requiring a resolver
      return;
    }

    await for (final node in nodes) {
      if (node.value is! Map) {
        continue; // Can only dereference from objects
      }

      final map = node.value as Map;
      final refIdValue = map[fieldName];

      if (refIdValue == null) {
        continue; // Field doesn't exist
      }

      if (refIdValue is! String) {
        continue; // RefId must be a string
      }

      // Perform async dereference
      try {
        final targetObject = await resolver.dereference(refIdValue, targetKind);

        if (targetObject != null) {
          // Create a new node for the dereferenced object
          // The parent is the original node, key is the @ dereference notation
          yield Node._(
            targetObject,
            node,
            key: '$fieldName@$targetKind',
          );
        }
        // If null, the document wasn't found - skip it
      } catch (e) {
        // If dereference fails, skip this node
        // Could log error here in production
        continue;
      }
    }
  };
}
