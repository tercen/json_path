import 'package:tercen_json_path/src/selector.dart';

Selector arraySliceSelector({int? start, int? stop, int? step}) =>
    (nodes) async* {
      await for (final node in nodes) {
        final slice = node.slice(start: start, stop: stop, step: step);
        if (slice != null) {
          yield* slice;
        }
      }
    };
