import 'dart:convert';

/// astral-core `service doctor` JSON 报告。
class CoreServiceHealthReport {
  const CoreServiceHealthReport({
    required this.serviceName,
    required this.serviceGeneration,
    required this.listen,
    required this.scmStatus,
    required this.legacyServiceInstalled,
    this.legacyServiceStatus,
    this.listenerPid,
    this.listenerCommandLine,
    required this.registryPresent,
    this.registryGeneration,
    this.registryDataDir,
    required this.dataDir,
    required this.legacyDataDir,
    required this.legacyDataDirExists,
    required this.issues,
    required this.needsRepair,
  });

  final String serviceName;
  final String serviceGeneration;
  final String listen;
  final String scmStatus;
  final bool legacyServiceInstalled;
  final String? legacyServiceStatus;
  final int? listenerPid;
  final String? listenerCommandLine;
  final bool registryPresent;
  final String? registryGeneration;
  final String? registryDataDir;
  final String dataDir;
  final String legacyDataDir;
  final bool legacyDataDirExists;
  final List<String> issues;
  final bool needsRepair;

  factory CoreServiceHealthReport.fromJson(Map<String, dynamic> json) {
    final listener = json['listener'];
    return CoreServiceHealthReport(
      serviceName: '${json['service_name'] ?? ''}',
      serviceGeneration: '${json['service_generation'] ?? ''}',
      listen: '${json['listen'] ?? ''}',
      scmStatus: '${json['scm_status'] ?? ''}',
      legacyServiceInstalled: json['legacy_service_installed'] == true,
      legacyServiceStatus: json['legacy_service_status']?.toString(),
      listenerPid: listener is Map ? (listener['pid'] as num?)?.toInt() : null,
      listenerCommandLine: listener is Map
          ? listener['command_line']?.toString()
          : null,
      registryPresent: json['registry_present'] == true,
      registryGeneration: json['registry_generation']?.toString(),
      registryDataDir: json['registry_data_dir']?.toString(),
      dataDir: '${json['data_dir'] ?? ''}',
      legacyDataDir: '${json['legacy_data_dir'] ?? ''}',
      legacyDataDirExists: json['legacy_data_dir_exists'] == true,
      issues: [
        for (final item in json['issues'] as List? ?? const [])
          '$item',
      ],
      needsRepair: json['needs_repair'] == true,
    );
  }

  static CoreServiceHealthReport? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return CoreServiceHealthReport.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

class CoreRepairReport {
  const CoreRepairReport({
    required this.stoppedCurrentService,
    required this.uninstalledLegacyService,
    required this.killedStaleListeners,
    required this.migratedLegacyData,
    required this.removedLegacyDataDir,
    required this.normalizedRegistry,
  });

  final bool stoppedCurrentService;
  final bool uninstalledLegacyService;
  final int killedStaleListeners;
  final bool migratedLegacyData;
  final bool removedLegacyDataDir;
  final bool normalizedRegistry;

  bool get changed =>
      stoppedCurrentService ||
      uninstalledLegacyService ||
      killedStaleListeners > 0 ||
      migratedLegacyData ||
      removedLegacyDataDir ||
      normalizedRegistry;
}

CoreRepairReport? parseRepairOutput(String output) {
  final trimmed = output.trim();
  if (!trimmed.startsWith('repair:')) return null;
  bool flag(String key) => trimmed.contains('$key=true');
  int count(String key) {
    final match = RegExp('$key=(\\d+)').firstMatch(trimmed);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  return CoreRepairReport(
    stoppedCurrentService: flag('stopped_current'),
    uninstalledLegacyService: flag('uninstalled_legacy'),
    killedStaleListeners: count('killed_listeners'),
    migratedLegacyData: flag('migrated_data'),
    removedLegacyDataDir: flag('removed_legacy_dir'),
    normalizedRegistry: flag('normalized_registry'),
  );
}
