import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/state_change_record.dart';

/// Observer that can mirror timeline changes to remote transports (WebSocket, HTTP, etc.).
abstract class StateInspectorSyncDelegate {
  void onRecordAdded(StateChangeRecord record) {}

  void onRecordMutated(StateChangeRecord record) {}

  void onRecordsCleared() {}

  void onBulkImport(List<StateChangeRecord> records) {}
}

/// Helper that pushes serialized timeline updates into a [StreamSink].
class StreamSyncDelegate extends StateInspectorSyncDelegate {
  StreamSyncDelegate(this.sink);

  final StreamSink<Map<String, Object?>> sink;

  @override
  void onRecordAdded(StateChangeRecord record) {
    sink.add({
      'type': 'record',
      'payload': record.toJson(),
    });
  }

  @override
  void onRecordMutated(StateChangeRecord record) {
    sink.add({
      'type': 'record:update',
      'payload': record.toJson(),
    });
  }

  @override
  void onRecordsCleared() {
    sink.add(const <String, Object?>{
      'type': 'clear',
    });
  }

  @override
  void onBulkImport(List<StateChangeRecord> records) {
    sink.add({
      'type': 'bulkImport',
      'payload': records.map((record) => record.toJson()).toList(),
    });
  }
}

/// Sync delegate that pushes timeline events over a WebSocket connection.
class WebSocketSyncDelegate extends StateInspectorSyncDelegate {
  WebSocketSyncDelegate._(this._uri, this._socket, this._onStatusCallback) {
    _onStatusCallback?.call('connected to ${_uri.toString()}');
    final socket = _socket;
    socket?.done.then((_) => _handleDone(), onError: _handleError);
  }

  /// Establishes a WebSocket connection to [uri] and returns a delegate that
  /// mirrors timeline events to it. Optional [onStatus] callbacks are invoked
  /// during lifecycle transitions.
  static Future<WebSocketSyncDelegate> connect(
    Uri uri, {
    void Function(String status)? onStatus,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    onStatus?.call('connecting to ${uri.toString()}');
    try {
      final socket = await WebSocket.connect(uri.toString()).timeout(timeout,
          onTimeout: () {
        throw TimeoutException('Connection to $uri timed out after $timeout');
      });
      return WebSocketSyncDelegate._(uri, socket, onStatus);
    } catch (error) {
      onStatus?.call('connection failed: $error');
      rethrow;
    }
  }

  final Uri _uri;
  WebSocket? _socket;
  bool _closed = false;
  final void Function(String status)? _onStatusCallback;

  void _handleDone() {
    if (_closed) {
      return;
    }
    _onStatusCallback?.call('disconnected from ${_uri.toString()}');
    _closed = true;
    _socket = null;
  }

  void _handleError(Object error) {
    if (_closed) {
      return;
    }
    _onStatusCallback?.call('stream error: $error');
  }

  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null || _closed) {
      return;
    }
    try {
      socket.add(jsonEncode(message));
    } catch (error) {
      _handleError(error);
    }
  }

  @override
  void onRecordAdded(StateChangeRecord record) {
    _send({
      'type': 'record',
      'payload': record.toJson(),
    });
  }

  @override
  void onRecordMutated(StateChangeRecord record) {
    _send({
      'type': 'record:update',
      'payload': record.toJson(),
    });
  }

  @override
  void onRecordsCleared() {
    _send(const <String, Object?>{
      'type': 'clear',
    });
  }

  @override
  void onBulkImport(List<StateChangeRecord> records) {
    _send({
      'type': 'bulkImport',
      'payload': records.map((record) => record.toJson()).toList(),
    });
  }

  /// Closes the underlying WebSocket connection.
  Future<void> dispose() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _onStatusCallback?.call('disconnecting');
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }
}
