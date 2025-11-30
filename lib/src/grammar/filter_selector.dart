import 'package:tercen_json_path/src/expression/expression.dart';
import 'package:tercen_json_path/src/selector.dart';

Selector filterSelector(Expression<bool> filter) => (nodes) async* {
      await for (final node in nodes) {
        await for (final child in node.children) {
          if (await filter.call(child)) {
            yield child;
          }
        }
      }
    };
