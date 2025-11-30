import 'dart:async';

import 'package:tercen_json_path/src/node.dart';

/// Base class for all node streams in JSONPath expressions.
/// This provides a type hierarchy for compile-time validation of query singularity.
abstract class NodeStream extends Stream<Node> {
  /// Returns the number of nodes in this stream.
  Future<int> get length;

  /// Returns the first node or null if stream is empty.
  Future<Node?> get firstOrNull async {
    try {
      return await first;
    } catch (_) {
      return null;
    }
  }

  /// Attempts to convert this stream to a singular stream.
  /// Throws StateError if stream doesn't have exactly one node.
  Future<SingularNodeStream> toSingular() async {
    final nodes = await toList();
    if (nodes.length != 1) {
      throw StateError(
        'Expected exactly 1 node for singular query, got ${nodes.length}',
      );
    }
    return SingularNodeStream(nodes.first);
  }

  /// Converts this stream to a list of nodes.
  @override
  Future<List<Node>> toList();
}

/// A stream guaranteed to contain exactly one node at compile time.
/// Used for queries that are statically known to return a single node (e.g., @ in filters).
class SingularNodeStream extends NodeStream {
  final Node _node;

  SingularNodeStream(this._node);

  /// Direct access to the single node without async overhead.
  Node get node => _node;

  @override
  Future<int> get length async => 1;

  @override
  Future<Node?> get firstOrNull async => _node;

  @override
  Future<SingularNodeStream> toSingular() async => this;

  @override
  Future<List<Node>> toList() async => [_node];

  @override
  StreamSubscription<Node> listen(
    void Function(Node)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<Node>();

    // Emit the single node
    scheduleMicrotask(() {
      controller.add(_node);
      controller.close();
    });

    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// A stream that can contain zero or more nodes.
/// Used for queries that may return multiple results (e.g., $.*, $[*], ..).
class MultiNodeStream extends NodeStream {
  final Stream<Node> _stream;

  MultiNodeStream(this._stream);

  /// Creates a MultiNodeStream from an iterable of nodes.
  factory MultiNodeStream.fromIterable(Iterable<Node> nodes) {
    return MultiNodeStream(Stream.fromIterable(nodes));
  }

  /// Creates a MultiNodeStream from an async generator.
  factory MultiNodeStream.fromGenerator(
    Stream<Node> Function() generator,
  ) {
    return MultiNodeStream(generator());
  }

  @override
  Future<int> get length => _stream.length;

  @override
  Future<List<Node>> toList() => _stream.toList();

  @override
  StreamSubscription<Node> listen(
    void Function(Node)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
