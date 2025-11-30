import 'package:tercen_json_path/src/node.dart';
import 'package:tercen_json_path/src/expression/node_stream.dart';
import 'package:maybe_just_nothing/maybe_just_nothing.dart';

// Re-export NodeStream types so they're available through fun_sdk
export 'package:tercen_json_path/src/expression/node_stream.dart';

typedef NodeList = NodeStream;

// Helper class to wrap a stream with sync-accessible metadata
class _StreamWithInfo {
  _StreamWithInfo(this.stream, {required this.isEmpty});
  final Stream<Node> stream;
  final bool isEmpty;
}

extension NodeListExt on NodeList {
  // For filter expressions we need sync access
  // This works because our streams are synchronous generators over in-memory data
  // The stream completes immediately without I/O
  Maybe get asValue {
    // HACK: Use sync* iteration to materialize the stream
    // This only works for synchronous streams (no real async I/O)
    final list = <Node>[];
    // Convert async stream to sync by collecting (blocks until complete)
    // This is safe ONLY because our selectors are sync* generators
    // Once we add @ dereferencing with real async I/O, this will need refactoring
    try {
      // For now, we can't actually do this synchronously with Dart streams
      // We'll need to refactor to use sync Iterables alongside async Streams
      throw UnimplementedError(
        'Sync asValue not possible with async streams. Need dual sync/async paths.',
      );
    } catch (e) {
      return const Nothing();
    }
  }

  bool get asLogical {
    throw UnimplementedError(
      'Sync asLogical not possible with async streams. Need dual sync/async paths.',
    );
  }

  // Async versions (for when we have real async I/O)
  Future<bool> get asLogicalAsync => isEmpty.then((v) => !v);

  Future<Maybe> get asValueAsync async {
    final list = await toList();
    return list.length == 1 ? Just(list.single.value) : const Nothing();
  }
}
