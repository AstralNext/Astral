import 'dart:convert';
import 'dart:io';

import 'package:astral/config/constants.dart';
import 'package:astral/data/kernel/core_host.dart';
import 'package:astral/utils/app_version.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class CoreReleaseInfo {
  const CoreReleaseInfo({
    required this.version,
    required this.assetUrl,
    this.wintunUrl,
    this.notes = '',
    this.htmlUrl = '',
  });

  final String version;
  final String assetUrl;
  final String? wintunUrl;
  final String notes;
  final String htmlUrl;
}

/// 从 GitHub 拉取 astral-core 发行包并落到本地。
class CoreUpdateService {
  CoreUpdateService(this._host);

  final CoreHost _host;
  static const _timeout = Duration(seconds: 120);

  Future<CoreReleaseInfo?> fetchLatest({
    bool includePrereleases = false,
  }) async {
    final response = await http
        .get(
          Uri.parse(AppConstants.coreGithubReleasesUrl),
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'astral',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;

    final decoded = json.decode(response.body);
    if (decoded is! List) return null;

    final assetNames = CoreHost.releaseAssetNames();
    final wintunNames = CoreHost.wintunAssetNames();

    for (final item in decoded) {
      if (item is! Map) continue;
      final release = Map<String, dynamic>.from(item);
      if (release['draft'] == true) continue;
      if (!includePrereleases && release['prerelease'] == true) continue;
      final tag = (release['tag_name'] as String?)?.trim() ?? '';
      if (tag.isEmpty) continue;
      final assets = release['assets'];
      if (assets is! List) continue;
      String? assetUrl;
      String? wintunUrl;
      for (final wanted in assetNames) {
        for (final raw in assets) {
          if (raw is! Map) continue;
          final name = raw['name']?.toString() ?? '';
          final url = raw['browser_download_url']?.toString() ?? '';
          if (name == wanted && (assetUrl == null || assetUrl.isEmpty)) {
            assetUrl = url;
          }
          if (wintunUrl == null || wintunUrl.isEmpty) {
            for (final tun in wintunNames) {
              if (name == tun) {
                wintunUrl = url;
                break;
              }
            }
          }
        }
        if (assetUrl != null && assetUrl.isNotEmpty) break;
      }
      if (assetUrl == null || assetUrl.isEmpty) continue;
      return CoreReleaseInfo(
        version: tag,
        assetUrl: assetUrl,
        wintunUrl: wintunUrl,
        notes: (release['body'] as String?)?.trim() ?? '',
        htmlUrl:
            (release['html_url'] as String?)?.trim() ??
            AppConstants.coreGithubReleasesPage,
      );
    }
    return null;
  }

  bool isNewer(String latest, String? current) {
    if (current == null || current.trim().isEmpty) return true;
    return AppVersion.isNewer(latest, current);
  }

  /// 下载到托管 bin 目录，返回 exe 路径。
  Future<String> downloadRelease(CoreReleaseInfo release) async {
    final dir = Directory(_host.managedBinDir());
    await dir.create(recursive: true);
    final exePath = p.join(dir.path, CoreHost.binaryName);
    await _downloadTo(release.assetUrl, exePath);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', exePath]);
    }
    if (release.wintunUrl != null && release.wintunUrl!.isNotEmpty) {
      await _downloadTo(release.wintunUrl!, p.join(dir.path, 'wintun.dll'));
    }
    return exePath;
  }

  Future<void> copySidecarsNextTo(String exePath) async {
    await _host.ensureRuntimeSidecars(nearProgram: exePath);
  }

  Future<void> _downloadTo(String url, String dest) async {
    final response = await http.get(Uri.parse(url)).timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError('下载失败 ${response.statusCode}: $url');
    }
    await File(dest).writeAsBytes(response.bodyBytes, flush: true);
  }
}
