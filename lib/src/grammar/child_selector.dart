import 'package:tercen_json_path/fun_sdk.dart';
import 'package:tercen_json_path/src/selector.dart';

Selector childSelector(String key) {
  if (key.runes.any(
    (r) => r < 0 || r > 0x10FFFF || (r >= 0xD800 && r <= 0xDFFF),
  )) {
    throw const FormatException('Invalid UTF code units in childSelector.');
  }
  return (NodeStream nodes) {
    return MultiNodeStream((() async* {
      await for (final node in nodes) {
        final child = node.child(key);
        if (child != null) {
          yield child;
        }
      }
    })());
  };
}
