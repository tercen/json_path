import 'package:tercen_json_path/src/grammar/parser_ext.dart';
import 'package:tercen_json_path/src/selector.dart';
import 'package:petitparser/petitparser.dart';

final wildcard = char('*').value((NodeStream nodes) {
  return MultiNodeStream((() async* {
    await for (final node in nodes) {
      yield* node.children;
    }
  })());
});
