import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:astral/data/kernel/core_service_health.dart';

enum CoreInstallState {
  missingBinary,
  notInstalled,
  stopped,
  running,
  unknown;

  String get label => switch (this) {
    CoreInstallState.missingBinary => '未找到内核',
    CoreInstallState.notInstalled => '未安装',
    CoreInstallState.stopped => '已停止',
    CoreInstallState.running => '运行中',
    CoreInstallState.unknown => '未知',
  };

  bool get isInstalled =>
      this == CoreInstallState.running || this == CoreInstallState.stopped;
}

class CoreCliResult {
  const CoreCliResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;

  String get output {
    final text = '$stdout\n$stderr'.trim();
    return text;
  }
}

/// 定位 / 拉起 / 安装本机 astral-core。
class CoreHost {
  /// OS 服务限定名（Windows SCM / systemd / launchd）。
  static const serviceQualifiedName = 'dev.astral.core';

  /// 旧版服务名（迁移清理用）。
  static const legacyServiceQualifiedName = 'dev.astral.core-default';

  /// 服务代际标记。
  static const serviceGeneration = 'core-v2';

  /// 本机 JSON-RPC 监听地址。
  static const listenAddress = '127.0.0.1:50051';

  static const windowsSidecars = ['wintun.dll', 'Packet.dll'];

  /// Linux / macOS 走用户级服务，无需 root；Windows 为系统服务（必要时 UAC）。
  static bool get useUserService => !Platform.isWindows;

  static String get binaryName =>
      Platform.isWindows ? 'astral-core.exe' : 'astral-core';

  String dataRoot() {
    if (Platform.isWindows) {
      // 与 astral-core `config::paths::discover()` 对齐：C:\ProgramData\nextAstral
      final programData =
          Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
      return p.join(programData, 'nextAstral');
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return p.join(
        home,
        'Library',
        'Application Support',
        'dev.Astral.astral-core',
      );
    }
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final home = Platform.environment['HOME'] ?? '';
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : p.join(home, '.local', 'share');
    return p.join(base, 'astral-core');
  }

  /// 后台服务运行数据目录（与 astral-core `--data-dir` 默认一致）。
  String runtimeDataDir() => dataRoot();

  /// 与 astral-core `layout::default_install_root` 对齐。
  String defaultInstallRoot() {
    if (Platform.isWindows) {
      // 与 astral-core `layout::default_install_root()` 对齐：C:\Program Files\nextAstral
      final programFiles =
          Platform.environment['PROGRAMFILES'] ?? r'C:\Program Files';
      return p.join(programFiles, 'nextAstral');
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return p.join(
        home,
        'Library',
        'Application Support',
        'dev.Astral.astral-core',
        'app',
      );
    }
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final home = Platform.environment['HOME'] ?? '';
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : p.join(home, '.local', 'share');
    return p.join(base, 'astral-core', 'app');
  }

  String currentProgramPath() =>
      p.join(defaultInstallRoot(), 'current', binaryName);

  String currentEntryPath() => p.join(defaultInstallRoot(), 'current');

  /// 发行包 / `flutter run` 输出目录里，与 GUI 并排的内核。
  String bundledProgramPath() =>
      p.join(File(Platform.resolvedExecutable).parent.path, binaryName);

  List<String> _devCheckoutBinaries() {
    final out = <String>[];
    final starts = <String>[
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
    ];
    for (final start in starts) {
      var dir = Directory(start);
      for (var i = 0; i < 8; i++) {
        for (final profile in const ['debug', 'release']) {
          out.add(
            p.join(dir.path, 'astral-core', 'target', profile, binaryName),
          );
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return out;
  }

  List<String> sidecarSearchDirs(String? nearProgram) {
    return [
      if (nearProgram != null && nearProgram.trim().isNotEmpty)
        File(nearProgram.trim()).parent.path,
      File(bundledProgramPath()).parent.path,
      p.join(Directory.current.path, 'dlls'),
    ];
  }

  /// 把签名过的 wintun / Packet 拷到内核 exe 旁（服务进程从这里 LoadLibrary）。
  ///
  /// 不要创建 `{install_root}/current`：那是内核用目录结指向版本目录的入口。
  Future<void> ensureRuntimeSidecars({String? nearProgram}) async {
    if (!Platform.isWindows) return;
    await repairBrokenCurrentEntry();
    final destDirs = <String>{
      File(bundledProgramPath()).parent.path,
      if (nearProgram != null && nearProgram.trim().isNotEmpty)
        File(nearProgram.trim()).parent.path,
      ..._existingVersionProgramDirs(),
    };
    if (File(currentProgramPath()).existsSync()) {
      destDirs.add(File(currentProgramPath()).parent.path);
    }
    for (final name in windowsSidecars) {
      final src = _findSidecar(name, nearProgram);
      if (src == null) continue;
      for (final destDir in destDirs) {
        try {
          await Directory(destDir).create(recursive: true);
        } on FileSystemException {
          continue;
        }
        final dest = p.join(destDir, name);
        if (p.equals(src, dest)) continue;
        await _copySidecarReplacing(src, dest);
      }
    }
  }

  List<String> _existingVersionProgramDirs() {
    final root = Directory(defaultInstallRoot());
    if (!root.existsSync()) return const [];
    final out = <String>[];
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name == 'current') continue;
      if (File(p.join(entity.path, binaryName)).existsSync()) {
        out.add(entity.path);
      }
    }
    return out;
  }

  /// 若 `current` 被建成普通目录且没有内核 exe，删掉它，好让 astral-core 重建目录结。
  Future<void> repairBrokenCurrentEntry() async {
    final linkPath = currentEntryPath();
    try {
      if (File(currentProgramPath()).existsSync()) return;
    } on FileSystemException {
      // 无法遍历不受信任的装入点时，仍尝试拆掉残缺的 current。
    }
    final type = FileSystemEntity.typeSync(linkPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;

    if (Platform.isWindows) {
      final parent = File(linkPath).parent.path;
      await Process.run('cmd', [
        '/C',
        'rmdir',
        'current',
      ], workingDirectory: parent);
      try {
        if (File(currentProgramPath()).existsSync()) return;
      } on FileSystemException {
        // continue
      }
      if (FileSystemEntity.typeSync(linkPath, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return;
      }
      await Process.run('cmd', [
        '/C',
        'rmdir',
        '/S',
        '/Q',
        'current',
      ], workingDirectory: parent);
      return;
    }

    try {
      await Directory(linkPath).delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _copySidecarReplacing(String src, String dest) async {
    final destFile = File(dest);
    if (destFile.existsSync()) {
      try {
        if (await binariesMatch(src, dest)) return;
      } catch (_) {}
      try {
        await destFile.delete();
      } catch (_) {
        return;
      }
    }
    try {
      await File(src).copy(dest);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 183 && destFile.existsSync()) return;
      rethrow;
    }
  }

  String? _findSidecar(String name, String? nearProgram) {
    for (final dir in sidecarSearchDirs(nearProgram)) {
      final file = File(p.join(dir, name));
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  /// 开发时若 GUI 旁没有内核，从并列仓库构建产物拷过去。
  Future<String?> materializeBundledProgram() async {
    final dest = bundledProgramPath();
    if (File(dest).existsSync()) return dest;

    String? newest;
    DateTime? newestMtime;
    for (final path in _devCheckoutBinaries()) {
      final file = File(path);
      if (!file.existsSync()) continue;
      DateTime mtime;
      try {
        mtime = file.lastModifiedSync();
      } catch (_) {
        continue;
      }
      if (newest == null || mtime.isAfter(newestMtime!)) {
        newest = path;
        newestMtime = mtime;
      }
    }
    if (newest == null) return null;
    if (p.equals(newest, dest)) return dest;
    await Directory(File(dest).parent.path).create(recursive: true);
    await File(newest).copy(dest);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', dest]);
    }
    await ensureRuntimeSidecars(nearProgram: dest);
    return dest;
  }

  static Future<String> sha256File(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  /// 大小不同则直接视为不一致；相同再比 SHA-256。
  Future<bool> binariesMatch(String a, String b) async {
    final fa = File(a);
    final fb = File(b);
    if (!fa.existsSync() || !fb.existsSync()) return false;
    if (p.equals(p.normalize(a), p.normalize(b))) return true;
    int sizeA;
    int sizeB;
    try {
      sizeA = fa.lengthSync();
      sizeB = fb.lengthSync();
    } catch (_) {
      return false;
    }
    if (sizeA != sizeB) return false;
    return await sha256File(a) == await sha256File(b);
  }

  Future<String?> findBinary() async {
    for (final path in [bundledProgramPath(), currentProgramPath()]) {
      if (File(path).existsSync()) return path;
    }
    return materializeBundledProgram();
  }

  Future<void> spawnDetached({
    required String binary,
    String listen = listenAddress,
  }) async {
    final dataDir = runtimeDataDir();
    await Directory(dataDir).create(recursive: true);
    await Process.start(
      binary,
      ['run', '--listen', listen, '--data-dir', dataDir],
      mode: ProcessStartMode.detached,
      workingDirectory: File(binary).parent.path,
    );
  }

  /// 未安装服务时，清掉占着 JSON-RPC 端口的临时 astral-core，避免再装绑端口失败。
  Future<void> stopDetachedListener([String listen = listenAddress]) async {
    final port = parseListenPort(listen);
    if (port == null) return;
    try {
      if (Platform.isWindows) {
        final command =
            '''
Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
  ForEach-Object {
    \$proc = Get-Process -Id \$_.OwningProcess -ErrorAction SilentlyContinue
    if (\$proc -and \$proc.ProcessName -like 'astral-core*') {
      Stop-Process -Id \$proc.Id -Force -ErrorAction SilentlyContinue
    }
  }
''';
        await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          command,
        ]);
        return;
      }
      final lsof = await Process.run('lsof', [
        '-t',
        '-iTCP:$port',
        '-sTCP:LISTEN',
      ]);
      if (lsof.exitCode != 0) return;
      for (final line in lsof.stdout.toString().split(RegExp(r'\s+'))) {
        final pid = int.tryParse(line.trim());
        if (pid == null) continue;
        final comm = await Process.run('ps', ['-o', 'comm=', '-p', '$pid']);
        final name = comm.stdout.toString().trim().toLowerCase();
        if (name.contains('astral-core')) {
          await Process.run('kill', ['$pid']);
        }
      }
    } catch (_) {}
  }

  Future<CoreCliResult> runArgs(
    List<String> args, {
    String? binary,
    bool elevate = false,
    String? workingDirectory,
  }) async {
    final exe = binary ?? await findBinary();
    if (exe == null) {
      return const CoreCliResult(
        exitCode: 127,
        stdout: '',
        stderr: '未找到 astral-core',
      );
    }
    final cwd = workingDirectory ?? File(exe).parent.path;
    if (Platform.isWindows && elevate) {
      return _runElevated(exe, args, cwd);
    }
    final result = await Process.run(exe, args, workingDirectory: cwd);
    return CoreCliResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  Future<CoreCliResult> runService(
    String action, {
    List<String> extra = const [],
    String? binary,
    bool elevateIfNeeded = true,
  }) async {
    final args = ['service', action, if (useUserService) '--user', ...extra];
    var result = await runArgs(args, binary: binary);
    if (elevateIfNeeded &&
        Platform.isWindows &&
        !result.ok &&
        _looksLikeNeedsElevate(result)) {
      result = await runArgs(args, binary: binary, elevate: true);
    }
    return result;
  }

  Future<CoreCliResult> installService({
    required String binary,
    String listen = listenAddress,
  }) {
    return runService(
      'install',
      extra: ['--listen', listen, '--program', binary],
      binary: binary,
    );
  }

  Future<CoreCliResult> uninstallService({String? binary}) =>
      runService('uninstall', binary: binary);

  Future<CoreCliResult> startService({String? binary}) =>
      runService('start', binary: binary);

  Future<CoreCliResult> stopService({String? binary}) =>
      runService('stop', binary: binary);

  Future<CoreCliResult> serviceStatus({String? binary}) =>
      runService('status', binary: binary, elevateIfNeeded: false);

  Future<CoreCliResult> updateService({
    required String newProgram,
    String? binary,
  }) {
    return runService(
      'update',
      extra: ['--program', newProgram],
      binary: binary,
    );
  }

  /// 读取 JSON 服务体检报告。
  Future<CoreServiceHealthReport?> serviceDoctor({String? binary}) async {
    final result = await runService(
      'doctor',
      binary: binary,
      elevateIfNeeded: false,
    );
    if (!result.ok && result.stdout.trim().isEmpty) return null;
    return CoreServiceHealthReport.tryParse(result.stdout);
  }

  /// 清理旧服务 / 旧进程，可选迁移 legacy 数据目录。
  Future<CoreRepairReport?> serviceRepair({
    String? binary,
    bool migrateLegacyData = true,
    bool elevateIfNeeded = true,
  }) async {
    final result = await runService(
      'repair',
      extra: migrateLegacyData ? const ['--migrate-legacy-data'] : const [],
      binary: binary,
      elevateIfNeeded: elevateIfNeeded,
    );
    final parsed = result.ok ? parseRepairOutput(result.output) : null;
    if (parsed != null) return parsed;

    // UAC 提权后子进程 stdout 无法回传，用 doctor 复核是否已修复。
    final after = await serviceDoctor(binary: binary);
    if (after != null && !after.needsRepair) {
      return const CoreRepairReport(
        stoppedCurrentService: false,
        uninstalledLegacyService: false,
        killedStaleListeners: 0,
        migratedLegacyData: false,
        removedLegacyDataDir: false,
        normalizedRegistry: false,
      );
    }
    return null;
  }

  Future<String?> readVersion(String? binary) async {
    final exe = binary ?? await findBinary();
    if (exe == null) return null;
    final result = await runArgs(['--version'], binary: exe);
    if (!result.ok && result.stdout.trim().isEmpty) return null;
    return parseCoreVersion('${result.stdout}\n${result.stderr}');
  }

  Future<CoreInstallState> queryInstallState() async {
    final binary = await findBinary();
    if (binary == null) return CoreInstallState.missingBinary;
    final result = await serviceStatus(binary: binary);
    return parseInstallState(result.output);
  }

  Future<CoreCliResult> _runElevated(
    String exe,
    List<String> args,
    String cwd,
  ) => _runElevatedBatch(exe, [args], cwd);

  /// 一次 UAC 提权执行多组参数（同一 exe）。
  /// 用于把 install+start / update+start 合并成一次提权，
  /// 避免用户在自动更新时被弹多次 UAC。
  Future<CoreCliResult> _runElevatedBatch(
    String exe,
    List<List<String>> argsBatch,
    String cwd,
  ) async {
    final script = File(
      p.join(Directory.systemTemp.path, 'astral-core-elevate.ps1'),
    );
    final current = currentEntryPath();
    final exeLit = exe.replaceAll("'", "''");
    final cwdLit = cwd.replaceAll("'", "''");
    final curLit = current.replaceAll("'", "''");
    final blocks = StringBuffer();
    for (final args in argsBatch) {
      final argLine = args.map((a) => "'${a.replaceAll("'", "''")}'").join(' ');
      blocks.writeln("& '$exeLit' $argLine");
      // 每步都吃掉错误，继续下一步（start 在未 install 时会失败，但不阻断）
      blocks.writeln('\$code = \$LASTEXITCODE');
    }
    final body =
        '''
\$ErrorActionPreference = 'SilentlyContinue'
\$cur = '$curLit'
\$bin = Join-Path \$cur 'astral-core.exe'
if (-not (Test-Path -LiteralPath \$bin)) {
  cmd.exe /c "rmdir `"\$cur`""
  if (Test-Path -LiteralPath \$cur) { cmd.exe /c "rmdir /S /Q `"\$cur`"" }
}
\$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath '$cwdLit'
$blocks
exit \$code
''';
    await script.writeAsString(body);
    final scriptPath = script.path.replaceAll("'", "''");
    final command =
        "Start-Process -FilePath 'powershell' -Verb RunAs -Wait -WindowStyle Hidden "
        "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$scriptPath'";
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      command,
    ]);
    return CoreCliResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  /// 一次提权完成安装 + 启动（Windows）。
  Future<CoreCliResult> installAndStartService({
    required String binary,
    String listen = listenAddress,
  }) async {
    final args = [
      'service',
      'install',
      '--listen',
      listen,
      '--program',
      binary,
    ];
    if (Platform.isWindows) {
      final cwd = File(binary).parent.path;
      return _runElevatedBatch(binary, [
        args,
        ['service', 'start'],
      ], cwd);
    }
    final install = await runService(
      'install',
      extra: ['--listen', listen, '--program', binary],
      binary: binary,
    );
    if (!install.ok) return install;
    return startService(binary: binary);
  }

  /// 一次提权完成更新 + 启动（Windows）。
  Future<CoreCliResult> updateAndStartService({
    required String newProgram,
    String? binary,
  }) async {
    final args = ['service', 'update', '--program', newProgram];
    if (Platform.isWindows) {
      final exe = binary ?? newProgram;
      final cwd = File(exe).parent.path;
      return _runElevatedBatch(exe, [
        args,
        ['service', 'start'],
      ], cwd);
    }
    final update = await runService(
      'update',
      extra: ['--program', newProgram],
      binary: binary,
    );
    if (!update.ok) return update;
    return startService(binary: binary);
  }

  static bool _looksLikeAccessDenied(CoreCliResult result) {
    final text = result.output.toLowerCase();
    return text.contains('access is denied') ||
        text.contains('拒绝访问') ||
        text.contains('privilege') ||
        text.contains('administrator') ||
        text.contains('elevation') ||
        result.exitCode == 5;
  }

  static bool _looksLikeNeedsElevate(CoreCliResult result) {
    if (_looksLikeAccessDenied(result)) return true;
    final text = result.output.toLowerCase();
    return text.contains('目录结') ||
        text.contains('mklink') ||
        text.contains('untrusted') ||
        text.contains('不受信任') ||
        text.contains('装入点') ||
        text.contains('448');
  }

  static bool looksLikeNotInstalled(CoreCliResult result) {
    final text = result.output.toLowerCase();
    return text.contains('not-installed') ||
        text.contains('not installed') ||
        text.contains('does not exist') ||
        text.contains('cannot find') ||
        text.contains('找不到') ||
        result.exitCode == 127;
  }

  static bool looksLikeAlreadyRunning(CoreCliResult result) {
    final text = result.output.toLowerCase();
    return text.contains('already running') ||
        text.contains('already started') ||
        text.contains('正在运行');
  }

  /// 旧协议内核会把 HTTP JSON-RPC 连接直接 RST。
  static bool looksLikeProtocolMismatch(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('10054') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('强迫关闭') ||
        text.contains('unexpected end of stream') ||
        text.contains('connection abort');
  }
}

int? parseListenPort(String listen) {
  final trimmed = listen.trim();
  if (trimmed.isEmpty) return null;
  final colon = trimmed.lastIndexOf(':');
  if (colon < 0 || colon == trimmed.length - 1) return null;
  return int.tryParse(trimmed.substring(colon + 1));
}

CoreInstallState parseInstallState(String output) {
  final line = output
      .split(RegExp(r'\r?\n'))
      .map((s) => s.trim().toLowerCase())
      .firstWhere((s) => s.isNotEmpty, orElse: () => '');
  if (line.startsWith('running')) return CoreInstallState.running;
  if (line.startsWith('stopped')) return CoreInstallState.stopped;
  if (line.contains('not-installed') || line.contains('not installed')) {
    return CoreInstallState.notInstalled;
  }
  if (line.isEmpty) return CoreInstallState.unknown;
  if (line.contains('running')) return CoreInstallState.running;
  if (line.contains('stopped')) return CoreInstallState.stopped;
  return CoreInstallState.unknown;
}

String? parseCoreVersion(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'v?\d+\.\d+(?:\.\d+)?').firstMatch(text);
  return match?.group(0);
}
