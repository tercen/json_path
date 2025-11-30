import 'package:tercen_json_path/fun_sdk.dart';

/// Returns the key under which the node referenced by the argument
/// is found in the parent object.
/// If the parent is not an object, returns [Nothing].
/// If the argument does not reference a single node, returns [Nothing].
class Key implements Fun1<Maybe, NodeList> {
  const Key();

  @override
  final name = 'key';

  @override
  Future<Maybe> call(NodeList nodes) async {
    final list = await nodes.toList();
    if (list.length != 1) return const Nothing();
    final node = list.first;
    return Just(node.key).type<String>();
  }
}
