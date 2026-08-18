import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

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
  static const instanceName = 'default';

  /// Linux / macOS 走用户级服务，无需 root；Windows 为系统服务（必要时 UAC）。
  static bool get useUserService => !Platform.isWindows;

  static String get binaryName =>
      Platform.isWindows ? 'astral-core.exe' : 'astral-core';

  String dataRoot() {
    if (Platform.isWindows) {
      final appdata = Platform.environment['APPDATA'] ?? '';
      // 与 directories::ProjectDirs Windows data_dir 对齐：...\Astral\astral-core\data
      return p.join(appdata, 'Astral', 'astral-core', 'data');
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

  /// 与 astral-core 服务默认 `--data-dir`（`instances/<name>`）对齐。
  String instanceDataDir() => p.join(dataRoot(), 'instances', instanceName);

  /// 与 astral-core `layout::default_install_root` 对齐。
  String defaultInstallRoot() {
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'] ?? '';
      return p.join(local, 'Astral', 'astral-core', 'data', 'app');
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

  String managedBinDir() {
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'] ?? '';
      return p.join(local, 'Astral', 'astral-core', 'bin');
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return p.join(
        home,
        'Library',
        'Application Support',
        'dev.Astral.astral-core',
        'bin',
      );
    }
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final home = Platform.environment['HOME'] ?? '';
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : p.join(home, '.local', 'share');
    return p.join(base, 'astral-core', 'bin');
  }

  /// 定位候选：设置路径、GUI 旁、已安装 current、托管 bin、并列仓库的本地构建。
  List<String> binaryCandidates(String? configured) {
    final seen = <String>{};
    final out = <String>[];
    void add(String path) {
      final n = p.normalize(path);
      if (n.isEmpty || !seen.add(n.toLowerCase())) return;
      out.add(n);
    }

    if (configured != null && configured.trim().isNotEmpty) {
      add(configured.trim());
    }
    add(p.join(File(Platform.resolvedExecutable).parent.path, binaryName));
    add(currentProgramPath());
    add(p.join(managedBinDir(), binaryName));
    for (final path in _devCheckoutBinaries()) {
      add(path);
    }
    return out;
  }

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

  static const windowsSidecars = ['wintun.dll', 'Packet.dll'];

  List<String> sidecarSearchDirs(String? nearProgram) {
    return [
      if (nearProgram != null && nearProgram.trim().isNotEmpty)
        File(nearProgram.trim()).parent.path,
      File(Platform.resolvedExecutable).parent.path,
      p.join(Directory.current.path, 'dlls'),
      managedBinDir(),
    ];
  }

  /// 把签名过的 wintun / Packet 拷到内核 exe 旁（服务进程从这里 LoadLibrary）。
  Future<void> ensureRuntimeSidecars({String? nearProgram}) async {
    if (!Platform.isWindows) return;
    final destDirs = <String>{
      File(currentProgramPath()).parent.path,
      managedBinDir(),
      if (nearProgram != null && nearProgram.trim().isNotEmpty)
        File(nearProgram.trim()).parent.path,
    };
    for (final name in windowsSidecars) {
      final src = _findSidecar(name, nearProgram);
      if (src == null) continue;
      for (final destDir in destDirs) {
        await Directory(destDir).create(recursive: true);
        final dest = p.join(destDir, name);
        if (p.equals(src, dest)) continue;
        await File(src).copy(dest);
      }
    }
  }

  String? _findSidecar(String name, String? nearProgram) {
    for (final dir in sidecarSearchDirs(nearProgram)) {
      final file = File(p.join(dir, name));
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  /// 比已安装 `current` 更新的本地二进制，供协议不匹配时 `service update`。
  Future<String?> findUpgradeBinary(String? configured) async {
    final current = currentProgramPath();
    final currentFile = File(current);
    DateTime? currentMtime;
    if (currentFile.existsSync()) {
      try {
        currentMtime = currentFile.lastModifiedSync();
      } catch (_) {}
    }

    String? best;
    DateTime? bestMtime;
    for (final path in binaryCandidates(configured)) {
      if (p.equals(p.normalize(path), p.normalize(current))) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      DateTime mtime;
      try {
        mtime = file.lastModifiedSync();
      } catch (_) {
        continue;
      }
      if (currentMtime != null && !mtime.isAfter(currentMtime)) continue;
      if (best == null || mtime.isAfter(bestMtime!)) {
        best = path;
        bestMtime = mtime;
      }
    }
    return best;
  }

  Future<String?> findBinary(String? configured) async {
    for (final path in binaryCandidates(configured)) {
      if (File(path).existsSync()) return path;
    }

    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'astral-core',
      ], runInShell: true);
      if (result.exitCode == 0) {
        final line = result.stdout
            .toString()
            .trim()
            .split(RegExp(r'\r?\n'))
            .first
            .trim();
        if (line.isNotEmpty && File(line).existsSync()) return line;
      }
    } catch (_) {}
    return null;
  }

  Future<void> spawnDetached({
    required String binary,
    required String listen,
  }) async {
    final dataDir = instanceDataDir();
    await Directory(dataDir).create(recursive: true);
    await Process.start(
      binary,
      ['run', '--listen', listen, '--data-dir', dataDir],
      mode: ProcessStartMode.detached,
      workingDirectory: File(binary).parent.path,
    );
  }

  /// 未安装服务时，清掉占着 JSON-RPC 端口的临时 astral-core，避免再装绑端口失败。
  Future<void> stopDetachedListener(String listen) async {
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
    final exe = binary ?? await findBinary(null);
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
    final args = [
      'service',
      action,
      if (useUserService) '--user',
      ...extra,
    ];
    var result = await runArgs(args, binary: binary);
    if (elevateIfNeeded &&
        Platform.isWindows &&
        !result.ok &&
        _looksLikeAccessDenied(result)) {
      result = await runArgs(args, binary: binary, elevate: true);
    }
    return result;
  }

  Future<CoreCliResult> installService({
    required String binary,
    required String listen,
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

  Future<String?> readVersion(String? binary) async {
    final exe = binary ?? await findBinary(null);
    if (exe == null) return null;
    final result = await runArgs(['--version'], binary: exe);
    if (!result.ok && result.stdout.trim().isEmpty) return null;
    return parseCoreVersion('${result.stdout}\n${result.stderr}');
  }

  Future<CoreInstallState> queryInstallState({String? configured}) async {
    final binary = await findBinary(configured);
    if (binary == null) return CoreInstallState.missingBinary;
    final result = await serviceStatus(binary: binary);
    return parseInstallState(result.output);
  }

  static String releaseAssetName() => releaseAssetNames().first;

  /// 当前平台优先匹配的发行包名，后接可运行的回退（如 Windows ARM 用 x64）。
  static List<String> releaseAssetNames() {
    final abi = Abi.current();
    if (Platform.isWindows) {
      if (abi == Abi.windowsArm64) {
        return const [
          'astral-core-windows-aarch64.exe',
          'astral-core-windows-x86_64.exe',
        ];
      }
      return const ['astral-core-windows-x86_64.exe'];
    }
    if (Platform.isMacOS) {
      if (abi == Abi.macosX64) return const ['astral-core-macos-x86_64'];
      return const ['astral-core-macos-aarch64'];
    }
    if (abi == Abi.linuxArm64) return const ['astral-core-linux-aarch64'];
    return const ['astral-core-linux-x86_64'];
  }

  static List<String> wintunAssetNames() {
    if (!Platform.isWindows) return const [];
    if (Abi.current() == Abi.windowsArm64) {
      return const ['wintun-windows-aarch64.dll', 'wintun-windows-x86_64.dll'];
    }
    return const ['wintun-windows-x86_64.dll'];
  }

  static String? wintunAssetName() {
    final names = wintunAssetNames();
    return names.isEmpty ? null : names.first;
  }

  Future<CoreCliResult> _runElevated(
    String exe,
    List<String> args,
    String cwd,
  ) async {
    final filePath = exe.replaceAll("'", "''");
    final argList = args.map((a) => "'${a.replaceAll("'", "''")}'").join(',');
    final command =
        "Start-Process -FilePath '$filePath' -ArgumentList $argList "
        "-Verb RunAs -Wait -WindowStyle Hidden "
        "-WorkingDirectory '${cwd.replaceAll("'", "''")}'";
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

  static bool _looksLikeAccessDenied(CoreCliResult result) {
    final text = result.output.toLowerCase();
    return text.contains('access is denied') ||
        text.contains('拒绝访问') ||
        text.contains('privilege') ||
        text.contains('administrator') ||
        text.contains('elevation') ||
        result.exitCode == 5;
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

  /// 旧 gRPC 内核会把 HTTP JSON-RPC 连接直接 RST。
  static bool looksLikeProtocolMismatch(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('10054') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('强迫关闭') ||
        text.contains('http exception') ||
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
