import 'dart:convert';
import 'dart:io';

/// Simple CLI companion that receives timeline events from the
/// [WebSocketSyncDelegate] and prints them to the console.
Future<void> main(List<String> arguments) async {
  final port =
      arguments.isNotEmpty ? int.tryParse(arguments.first) ?? 8787 : 8787;
  final host = arguments.length > 1 ? arguments[1] : '127.0.0.1';

  InternetAddress? bindAddress;
  try {
    bindAddress = InternetAddress.tryParse(host);
    if (bindAddress == null) {
      final resolved = await InternetAddress.lookup(host);
      if (resolved.isNotEmpty) {
        bindAddress = resolved.first;
      }
    }
  } catch (_) {
    // ignore and fall back to loopback
  }
  bindAddress ??= InternetAddress.loopbackIPv4;

  final server = await HttpServer.bind(bindAddress, port);

  final networkIps = <String>{};
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (!addr.isLoopback) {
          networkIps.add(addr.address);
        }
      }
    }
  } catch (_) {
    // Ignore interface discovery errors; companion still works on loopback.
  }

  stdout.writeln('🛰  Enterprise State Inspector companion listening on '
      'ws://${server.address.address}:$port/timeline');
  stdout.writeln(
      '    Open the example app, set the companion URL, and tap "Connect companion".\n');
  if (networkIps.isNotEmpty) {
    stdout.writeln('📡  同區網裝置可改用以下網址連線：');
    for (final ip in networkIps) {
      stdout.writeln('     ws://$ip:$port/timeline');
    }
    stdout.writeln();
  }

  await for (final request in server) {
    if (request.uri.path != '/timeline') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Expected WebSocket upgrade at /timeline')
        ..close();
      continue;
    }

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket upgrade required')
        ..close();
      continue;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    final clientId = socket.hashCode;
    stdout.writeln('✅ Companion connected to client #$clientId');

    socket.listen(
      (dynamic data) {
        if (data is! String) {
          stdout.writeln('⚠️  Non-string payload from client #$clientId');
          return;
        }
        try {
          final map = jsonDecode(data) as Map<String, dynamic>;
          _handleMessage(clientId, map);
        } catch (error) {
          stdout.writeln('⚠️  Failed to decode payload: $error');
        }
      },
      onDone: () => stdout.writeln('👋 Client #$clientId disconnected'),
      onError: (Object error) =>
          stdout.writeln('⚠️  Client #$clientId error: $error'),
      cancelOnError: true,
    );
  }
}

void _handleMessage(int clientId, Map<String, dynamic> message) {
  final type = message['type'] as String? ?? 'unknown';
  switch (type) {
    case 'record':
    case 'record:update':
      final payload = message['payload'] as Map<String, dynamic>?;
      if (payload == null) {
        stdout.writeln('[$clientId] $type (no payload)');
        return;
      }
      final origin = payload['origin'];
      final summary = payload['summary'];
      final timestamp = payload['timestamp'];
      stdout.writeln(
        "[${payload['id']}] $origin • ${payload['kind']} • $summary (@$timestamp)",
      );
      final tags = payload['tags'];
      if (tags is List && tags.isNotEmpty) {
        stdout.writeln('    tags: ${tags.join(', ')}');
      }
      final diffs = payload['diffs'];
      if (diffs is List && diffs.isNotEmpty) {
        final firstDiff = diffs.first as Map<String, dynamic>?;
        if (firstDiff != null) {
          stdout.writeln(
            "    diff: ${firstDiff['path'] ?? firstDiff['pathAsString']}",
          );
        }
      }
      break;
    case 'bulkImport':
      final payload = message['payload'];
      final count = payload is List ? payload.length : 0;
      stdout.writeln('[$clientId] Bulk import of $count records received');
      break;
    case 'clear':
      stdout.writeln('[$clientId] Timeline cleared');
      break;
    default:
      stdout.writeln('[$clientId] $type ${jsonEncode(message['payload'])}');
  }
}
