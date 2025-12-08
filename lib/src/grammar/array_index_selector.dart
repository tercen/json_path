import 'package:tercen_json_path/src/selector.dart';

Selector arrayIndexSelector(int offset) => (NodeStream nodes) {
  return MultiNodeStream((() async* {
    await for (final node in nodes) {
      final element = await node.element(offset);
      if (element != null) {
        yield element;
      }
    }
  })());
};
