import 'package:tercen_json_path/src/expression/nodes.dart';
import 'package:tercen_json_path/src/node.dart';
import 'package:tercen_json_path/src/selector.dart';

// Compose multiple selectors into a Selector (stream→stream)
Selector sequenceSelectorComposed(Iterable<Selector> selectors) {
  return (Stream<Node> nodes) {
    Stream<Node> current = nodes;

    // Apply each selector in sequence
    for (final selector in selectors) {
      current = selector(current);
    }

    return current;
  };
}

// Compose multiple selectors into a per-node function (node→stream)
// Used by grammar to build Expression<NodeList>
NodeList Function(Node) sequenceSelector(Iterable<Selector> selectors) {
  final composed = sequenceSelectorComposed(selectors);
  return (Node node) => composed(Stream.value(node));
}

// Singular version is same as regular (no distinction in stream world)
NodeList Function(Node) singularSequenceSelector(
  Iterable<SingularSelector> selectors,
) =>
    sequenceSelector(selectors);
