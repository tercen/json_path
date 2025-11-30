import 'package:tercen_json_path/fun_sdk.dart';

/// Returns the key under which the node referenced by the argument
/// is found in the parent object.
/// If the parent is not an object, returns [Nothing].
/// Requires a singular node stream (compile-time validated).
class Key implements Fun1<Maybe, SingularNodeStream> {
  const Key();

  @override
  final name = 'key';

  @override
  Future<Maybe> call(SingularNodeStream nodes) async {
    // Type system guarantees exactly one node!
    final node = nodes.node;
    return Just(node.key).type<String>();
  }
}
