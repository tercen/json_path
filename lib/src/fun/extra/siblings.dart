import 'package:tercen_json_path/fun_sdk.dart';

/// Returns all siblings of the given nodes.
class Siblings implements Fun1<NodeList, NodeList> {
  const Siblings();

  @override
  final name = 'siblings';

  @override
  NodeList call(NodeList nodes) {
    return MultiNodeStream((() async* {
      await for (final node in nodes) {
        final parent = node.parent;
        if (parent != null) {
          await for (final sibling in parent.children) {
            if (sibling != node) {
              yield sibling;
            }
          }
        }
      }
    })());
  }
}
