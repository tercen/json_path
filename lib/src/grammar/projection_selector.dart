import 'package:tercen_json_path/src/node.dart';
import 'package:tercen_json_path/src/selector.dart';

/// Creates a selector that projects each input node (Map) to a partial object
/// containing only the specified [fieldPaths].
///
/// Each field path is a dot-separated string (e.g., 'name', 'acl.owner').
/// Deep paths preserve nested structure: 'acl.owner' → {"acl": {"owner": value}}.
/// Multiple deep paths with shared prefixes merge:
///   'acl.owner' + 'acl.permissions' → {"acl": {"owner": ..., "permissions": ...}}
Selector projectionSelector(List<String> fieldPaths) =>
    (NodeStream nodes) => MultiNodeStream((() async* {
          await for (final node in nodes) {
            final v = node.value;
            if (v is! Map) continue;

            final result = <String, dynamic>{};
            var hasAny = false;

            for (final path in fieldPaths) {
              final parts = path.split('.');
              final value = _resolve(v, parts);
              if (value != _absent) {
                _setNested(result, parts, value);
                hasAny = true;
              }
            }

            if (hasAny) {
              yield Node(result);
            }
          }
        })());

/// Resolves a dot-path against a nested map. Returns [_absent] if not found.
Object? _resolve(Map map, List<String> parts) {
  dynamic current = map;
  for (final part in parts) {
    if (current is Map && current.containsKey(part)) {
      current = current[part];
    } else {
      return _absent;
    }
  }
  return current;
}

/// Sets a value at a nested path, merging with existing maps.
void _setNested(
    Map<String, dynamic> target, List<String> parts, Object? value) {
  var current = target;
  for (var i = 0; i < parts.length - 1; i++) {
    current = current.putIfAbsent(parts[i], () => <String, dynamic>{})
        as Map<String, dynamic>;
  }
  current[parts.last] = value;
}

/// Sentinel value indicating a missing field.
const _absent = _Absent();

class _Absent {
  const _Absent();
}
