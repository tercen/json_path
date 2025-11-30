import 'package:tercen_json_path/src/expression/nodes.dart';
import 'package:tercen_json_path/src/node.dart';
import 'package:tercen_json_path/src/selector.dart';

// Compose multiple selectors into a Selector (stream→stream)
Selector sequenceSelectorComposed(Iterable<Selector> selectors) {
  return (NodeStream nodes) {
    NodeStream current = nodes;

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
  return (Node node) => composed(SingularNodeStream(node));
}

// Singular version converts SingularSelectors to regular Selectors
// SingularSelector: SingularNodeStream -> SingularNodeStream
// Selector: NodeStream -> NodeStream
// We can safely treat SingularNodeStream as NodeStream
NodeList Function(Node) singularSequenceSelector(
  Iterable<SingularSelector> selectors,
) {
  // Convert SingularSelectors to Selectors by widening the type
  final regularSelectors = selectors.map<Selector>((singularSel) {
    return (NodeStream nodes) {
      // If nodes is singular, apply the singular selector
      if (nodes is SingularNodeStream) {
        return singularSel(nodes);
      }
      // Otherwise, wrap in MultiNodeStream (shouldn't happen in practice)
      return MultiNodeStream((() async* {
        await for (final node in nodes) {
          yield* singularSel(SingularNodeStream(node));
        }
      })());
    };
  });
  return sequenceSelector(regularSelectors);
}
