import 'dart:io';

import 'package:astral/data/kernel/core_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parseInstallState', () {
    test('parses service status lines', () {
      expect(
        parseInstallState(
          'running (qualified=dev.astral.core script=astral-core)',
        ),
        CoreInstallState.running,
      );
      expect(parseInstallState('stopped'), CoreInstallState.stopped);
      expect(
        parseInstallState('not-installed (qualified=dev.astral.core)'),
        CoreInstallState.notInstalled,
      );
      expect(parseInstallState(''), CoreInstallState.unknown);
      expect(parseInstallState('garbage'), CoreInstallState.unknown);
    });
  });

  group('parseListenPort', () {
    test('parses host:port', () {
      expect(parseListenPort('127.0.0.1:50051'), 50051);
      expect(parseListenPort('[::1]:50051'), 50051);
      expect(parseListenPort(''), isNull);
      expect(parseListenPort('no-port'), isNull);
    });
  });

  group('parseCoreVersion', () {
    test('extracts semver from --version output', () {
      expect(parseCoreVersion('astral-core 0.1.0'), '0.1.0');
      expect(parseCoreVersion('astral-core v1.2.3'), 'v1.2.3');
      expect(parseCoreVersion('1.0.0-beta.1'), '1.0.0');
      expect(parseCoreVersion(''), isNull);
    });
  });

  group('CoreInstallState', () {
    test('isInstalled only when running or stopped', () {
      expect(CoreInstallState.running.isInstalled, isTrue);
      expect(CoreInstallState.stopped.isInstalled, isTrue);
      expect(CoreInstallState.notInstalled.isInstalled, isFalse);
      expect(CoreInstallState.missingBinary.isInstalled, isFalse);
    });
  });

  group('CoreHost defaults', () {
    test('listens on loopback', () {
      expect(CoreHost.listenAddress, '127.0.0.1:50051');
    });

    test('uses fixed service name', () {
      expect(CoreHost.serviceQualifiedName, 'dev.astral.core');
    });

    test('lists windows sidecars', () {
      expect(CoreHost.windowsSidecars, contains('wintun.dll'));
      expect(CoreHost.windowsSidecars, contains('Packet.dll'));
    });
  });

  group('CoreCliResult helpers', () {
    test('detects not-installed and already-running', () {
      expect(
        CoreHost.looksLikeNotInstalled(
          const CoreCliResult(exitCode: 1, stdout: 'not-installed', stderr: ''),
        ),
        isTrue,
      );
      expect(
        CoreHost.looksLikeAlreadyRunning(
          const CoreCliResult(
            exitCode: 1,
            stdout: '',
            stderr: 'Service already running',
          ),
        ),
        isTrue,
      );
    });

    test('detects protocol mismatch resets', () {
      expect(
        CoreHost.looksLikeProtocolMismatch(
          'ClientException with SocketException: Write failed '
          '(OS Error: 远程主机强迫关闭了一个现有的连接。, errno = 10054)',
        ),
        isTrue,
      );
      expect(CoreHost.looksLikeProtocolMismatch('timeout'), isFalse);
    });
  });

  group('binariesMatch', () {
    test('same bytes match, different bytes do not', () async {
      final dir = await Directory.systemTemp.createTemp('astral-hash-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final a = File(p.join(dir.path, 'a.bin'));
      final b = File(p.join(dir.path, 'b.bin'));
      final c = File(p.join(dir.path, 'c.bin'));
      await a.writeAsBytes(const [1, 2, 3, 4, 5]);
      await b.writeAsBytes(const [1, 2, 3, 4, 5]);
      await c.writeAsBytes(const [1, 2, 3, 4, 6]);
      final host = CoreHost();
      expect(await host.binariesMatch(a.path, b.path), isTrue);
      expect(await host.binariesMatch(a.path, c.path), isFalse);
      expect(
        await CoreHost.sha256File(a.path),
        await CoreHost.sha256File(b.path),
      );
    });
  });
}
