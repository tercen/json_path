import 'package:tercen_json_path/src/selector.dart';

Selector unionSelector(Iterable<Selector> selectors) => (nodes) async* {
      for (final selector in selectors) {
        yield* selector(nodes);
      }
    };
