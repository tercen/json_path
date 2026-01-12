import 'package:tercen_json_path/src/virtual_property_resolver.dart';

/// Resolves step graph navigation properties within Workflow documents.
///
/// Supports the following virtual properties on Step nodes:
/// - `parentSteps`: Immediate parent steps (steps whose outputs connect to this step's inputs)
/// - `childSteps`: Immediate child steps (steps whose inputs connect to this step's outputs)
/// - `ancestorSteps`: All ancestor steps (transitive closure of parentSteps)
/// - `descendantSteps`: All descendant steps (transitive closure of childSteps)
///
/// Example JSONPath queries:
/// ```
/// $.steps[?@.id == "step1"].parentSteps[*]
/// $.steps[?@.id == "step1"].ancestorSteps[*].name
/// $.steps[?@.kind == "DataStep"].childSteps[?@.kind == "TableStep"]
/// ```
class StepGraphResolver implements VirtualPropertyResolver {
  /// Virtual properties supported by this resolver
  static const virtualProperties = [
    'parentSteps',
    'childSteps',
    'ancestorSteps',
    'descendantSteps',
  ];

  /// Step kinds that are considered valid Step types
  static const _stepKinds = {
    'Step',
    'ModelStep',
    'RelationStep',
    'DataStep',
    'TableStep',
    'JoinStep',
    'GroupStep',
    'InStep',
    'OutStep',
    'WizardStep',
    'CrosstabStep',
    'MeltStep',
    'ExportStep',
    'ViewStep',
    'RenameStep',
    'NamespaceStep',
    'SimpleRelationStep',
  };

  @override
  bool isVirtualProperty(String propertyName) =>
      virtualProperties.contains(propertyName);

  @override
  Future<dynamic> resolveProperty(
    Map<String, dynamic> currentNode,
    Map<String, dynamic> rootNode,
    String propertyName,
  ) async {
    // Verify we're on a Step node
    final kind = currentNode['kind'] as String?;
    if (!_isStepKind(kind)) return null;

    // Get workflow data from root
    final links = rootNode['links'] as List? ?? [];
    final steps = rootNode['steps'] as List? ?? [];

    switch (propertyName) {
      case 'parentSteps':
        return _resolveParentSteps(currentNode, links, steps);
      case 'childSteps':
        return _resolveChildSteps(currentNode, links, steps);
      case 'ancestorSteps':
        return _resolveAncestorSteps(currentNode, links, steps);
      case 'descendantSteps':
        return _resolveDescendantSteps(currentNode, links, steps);
      default:
        return null;
    }
  }

  /// Check if a kind string represents a Step type
  bool _isStepKind(String? kind) {
    if (kind == null) return false;
    return _stepKinds.contains(kind);
  }

  /// Get all input port IDs from a step
  Set<String> _getInputPortIds(Map<String, dynamic> step) {
    final inputs = step['inputs'] as List? ?? [];
    return inputs
        .map((port) => (port as Map<String, dynamic>)['id'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// Get all output port IDs from a step
  Set<String> _getOutputPortIds(Map<String, dynamic> step) {
    final outputs = step['outputs'] as List? ?? [];
    return outputs
        .map((port) => (port as Map<String, dynamic>)['id'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// Find a step that has an input port with the given ID
  Map<String, dynamic>? _findStepByInputPortId(List steps, String? portId) {
    if (portId == null) return null;
    for (final step in steps) {
      final stepMap = step as Map<String, dynamic>;
      final inputs = stepMap['inputs'] as List? ?? [];
      for (final port in inputs) {
        if ((port as Map<String, dynamic>)['id'] == portId) {
          return stepMap;
        }
      }
    }
    return null;
  }

  /// Find a step that has an output port with the given ID
  Map<String, dynamic>? _findStepByOutputPortId(List steps, String? portId) {
    if (portId == null) return null;
    for (final step in steps) {
      final stepMap = step as Map<String, dynamic>;
      final outputs = stepMap['outputs'] as List? ?? [];
      for (final port in outputs) {
        if ((port as Map<String, dynamic>)['id'] == portId) {
          return stepMap;
        }
      }
    }
    return null;
  }

  /// Resolve parent steps (immediate parents only)
  ///
  /// Parent steps are steps whose output ports are connected to this step's
  /// input ports via links.
  List<Map<String, dynamic>> _resolveParentSteps(
    Map<String, dynamic> step,
    List links,
    List steps,
  ) {
    final inputPortIds = _getInputPortIds(step);
    final parentSteps = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    for (final link in links) {
      final linkMap = link as Map<String, dynamic>;
      final inputId = linkMap['inputId'] as String?;
      final outputId = linkMap['outputId'] as String?;

      // If this link connects to one of our input ports, find the parent step
      if (inputId != null && inputPortIds.contains(inputId)) {
        final parentStep = _findStepByOutputPortId(steps, outputId);
        if (parentStep != null) {
          final parentId = parentStep['id'] as String?;
          // Avoid duplicates (a step might have multiple links to same parent)
          if (parentId != null && !seenIds.contains(parentId)) {
            seenIds.add(parentId);
            parentSteps.add(parentStep);
          }
        }
      }
    }

    return parentSteps;
  }

  /// Resolve child steps (immediate children only)
  ///
  /// Child steps are steps whose input ports are connected to this step's
  /// output ports via links.
  List<Map<String, dynamic>> _resolveChildSteps(
    Map<String, dynamic> step,
    List links,
    List steps,
  ) {
    final outputPortIds = _getOutputPortIds(step);
    final childSteps = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    for (final link in links) {
      final linkMap = link as Map<String, dynamic>;
      final inputId = linkMap['inputId'] as String?;
      final outputId = linkMap['outputId'] as String?;

      // If this link comes from one of our output ports, find the child step
      if (outputId != null && outputPortIds.contains(outputId)) {
        final childStep = _findStepByInputPortId(steps, inputId);
        if (childStep != null) {
          final childId = childStep['id'] as String?;
          // Avoid duplicates
          if (childId != null && !seenIds.contains(childId)) {
            seenIds.add(childId);
            childSteps.add(childStep);
          }
        }
      }
    }

    return childSteps;
  }

  /// Resolve ancestor steps (transitive closure of parents)
  ///
  /// Uses BFS to traverse all ancestors, preventing cycles via visited set.
  List<Map<String, dynamic>> _resolveAncestorSteps(
    Map<String, dynamic> step,
    List links,
    List steps,
  ) {
    final ancestors = <Map<String, dynamic>>[];
    final visited = <String>{};
    final currentStepId = step['id'] as String?;

    // Add starting step to visited to exclude from results
    if (currentStepId != null) {
      visited.add(currentStepId);
    }

    // BFS queue
    final queue = <Map<String, dynamic>>[step];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final parents = _resolveParentSteps(current, links, steps);

      for (final parent in parents) {
        final parentId = parent['id'] as String?;
        if (parentId != null && !visited.contains(parentId)) {
          visited.add(parentId);
          ancestors.add(parent);
          queue.add(parent);
        }
      }
    }

    return ancestors;
  }

  /// Resolve descendant steps (transitive closure of children)
  ///
  /// Uses BFS to traverse all descendants, preventing cycles via visited set.
  List<Map<String, dynamic>> _resolveDescendantSteps(
    Map<String, dynamic> step,
    List links,
    List steps,
  ) {
    final descendants = <Map<String, dynamic>>[];
    final visited = <String>{};
    final currentStepId = step['id'] as String?;

    // Add starting step to visited to exclude from results
    if (currentStepId != null) {
      visited.add(currentStepId);
    }

    // BFS queue
    final queue = <Map<String, dynamic>>[step];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final children = _resolveChildSteps(current, links, steps);

      for (final child in children) {
        final childId = child['id'] as String?;
        if (childId != null && !visited.contains(childId)) {
          visited.add(childId);
          descendants.add(child);
          queue.add(child);
        }
      }
    }

    return descendants;
  }
}
