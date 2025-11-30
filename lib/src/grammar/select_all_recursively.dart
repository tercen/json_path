import 'package:tercen_json_path/src/node.dart';
import 'package:tercen_json_path/src/selector.dart';

// Per-node recursive descent
Stream<Node> _selectAllRecursivelyPerNode(Node node) async* {
  yield node;
  await for (final child in node.children) {
    yield* _selectAllRecursivelyPerNode(child);
  }
}

// Selector that applies recursive descent to each input node
Selector selectAllRecursively = (NodeStream nodes) {
  return MultiNodeStream((() async* {
    await for (final node in nodes) {
      yield* _selectAllRecursivelyPerNode(node);
    }
  })());
};
