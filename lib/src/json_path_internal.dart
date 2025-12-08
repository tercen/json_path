import 'package:tercen_json_path/src/json_path.dart';
import 'package:tercen_json_path/src/json_path_match.dart';
import 'package:tercen_json_path/src/node.dart';
import 'package:tercen_json_path/src/node_match.dart';
import 'package:tercen_json_path/src/selector.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_resolver.dart';
import 'package:tercen_json_path/src/virtual_hierarchy_plan.dart';

/// Internal implementation of [JsonPath].
class JsonPathInternal implements JsonPath {
  JsonPathInternal(
    this.expression,
    this.selector, {
    this.resolver,
    this.hierarchyPlan,
  });

  /// Selector
  final Selector selector;

  /// JSONPath expression.
  final String expression;

  /// Virtual hierarchy resolver
  final VirtualHierarchyResolver? resolver;

  /// Hierarchy plan for prefetching
  final VirtualHierarchyPlan? hierarchyPlan;

  /// Reads the given [json] object returning a Stream of all matches found.
  @override
  Stream<JsonPathMatch> read(json) async* {
    // Prefetch if we have a resolver and plan
    if (resolver != null && hierarchyPlan != null) {
      await resolver!.prefetchHierarchy(hierarchyPlan!, json);
    }

    // Create root node with resolver
    final rootNode = Node(
      json,
      resolver: resolver,
      context: VirtualHierarchyContext(),
    );

    // Evaluate
    yield* selector(SingularNodeStream(rootNode)).map(NodeMatch.new);
  }

  /// Reads the given [json] object returning a Stream of all values found.
  @override
  Stream<Object?> readValues(json) => read(json).map((node) => node.value);

  @override
  String toString() => expression;
}
