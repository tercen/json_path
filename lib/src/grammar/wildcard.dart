import 'package:tercen_json_path/src/grammar/parser_ext.dart';
import 'package:tercen_json_path/src/node.dart';
import 'package:petitparser/petitparser.dart';

final wildcard = char('*').value((Stream<Node> nodes) async* {
      await for (final node in nodes) {
        yield* node.children;
      }
    });
