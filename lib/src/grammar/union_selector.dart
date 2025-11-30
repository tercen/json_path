import 'package:tercen_json_path/src/selector.dart';

Selector unionSelector(Iterable<Selector> selectors) => (NodeStream nodes) {
  return MultiNodeStream((() async* {
    // Convert to list first to allow multiple selectors to iterate over same nodes
    final nodeList = await nodes.toList();
    for (final selector in selectors) {
      yield* selector(MultiNodeStream.fromIterable(nodeList));
    }
  })());
};
