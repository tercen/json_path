import 'package:tercen_json_path/fun_sdk.dart';
import 'package:tercen_json_path/src/selector.dart';

SingularSelector arrayIndexSelector(int offset) => (nodes) async* {
      await for (final node in nodes) {
        final element = node.element(offset);
        if (element != null) {
          yield element;
        }
      }
    };
