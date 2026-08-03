import 'package:astral/data/services/app_settings_service.dart';
import 'package:astral/utils/app_version.dart';
import 'package:astral/utils/client_runtime_info.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals.dart';

class UpdateState {
  final beta = signal(false);
  final autoCheckUpdate = signal(true);
  final latestVersion = signal<String?>(null);
  final isChecking = signal(false);

  void loadFromPersistence() {
    final settings = GetIt.I<AppSettingsService>();
    autoCheckUpdate.value = settings.getAutoCheckUpdate();
    beta.value = settings.getUpdateBetaChannel();
  }

  void setBeta(bool value) {
    beta.value = value;
    GetIt.I<AppSettingsService>().setUpdateBetaChannel(value);
  }

  void setAutoCheckUpdate(bool value) {
    autoCheckUpdate.value = value;
    GetIt.I<AppSettingsService>().setAutoCheckUpdate(value);
  }

  void setLatestVersion(String? version) => latestVersion.value = version;

  late final hasNewVersion = computed(() {
    final latest = latestVersion.value;
    if (latest == null || latest.trim().isEmpty) return false;
    final current = ClientRuntimeInfo.appVersion;
    if (current.isEmpty || current == 'unknown') return false;
    return AppVersion.isNewer(latest, current);
  });
}
