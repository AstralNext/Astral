import 'dart:convert';

import 'package:astral/config/constants.dart';
import 'package:astral/data/state/update_state.dart';
import 'package:astral/utils/app_version.dart';
import 'package:astral/utils/client_runtime_info.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  UpdateService(this.updateState);

  final UpdateState updateState;
  static const _requestTimeout = Duration(seconds: 15);

  Future<String> getCurrentVersion() async {
    await ClientRuntimeInfo.warmUp();
    return ClientRuntimeInfo.appVersion;
  }

  /// 远端 tag 是否新于当前安装版本（忽略 `v` / `+build`）。
  bool isNewerThanCurrent(String latestVersion, {String? currentVersion}) {
    final current = currentVersion ?? ClientRuntimeInfo.appVersion;
    if (current.isEmpty || current == 'unknown') return false;
    return AppVersion.isNewer(latestVersion, current);
  }

  Future<void> checkForUpdates(
    BuildContext context, {
    bool showNoUpdateMessage = true,
    bool showFailureMessage = true,
  }) async {
    if (updateState.isChecking.value) return;
    updateState.isChecking.value = true;

    try {
      final releaseInfo = await _fetchLatestRelease(
        includePrereleases: updateState.beta.value,
      );

      if (releaseInfo == null) {
        if (!context.mounted) return;
        if (showFailureMessage) {
          _showMessageDialog(
            context,
            '检查更新失败',
            '无法从 GitHub 获取 Astral 发布信息，请稍后重试或手动打开 Releases 页面。',
          );
        }
        return;
      }

      final currentVersion = await getCurrentVersion();
      final latestVersion = _versionFromRelease(releaseInfo);

      if (latestVersion == null || latestVersion.isEmpty) {
        if (!context.mounted) return;
        if (showFailureMessage) {
          _showMessageDialog(context, '检查更新失败', '无法解析最新版本号');
        }
        return;
      }

      updateState.setLatestVersion(latestVersion);

      if (!context.mounted) return;

      final releaseNotes = _extractString(
        releaseInfo,
        'body',
        fallback: '新版本已发布，请前往 GitHub Releases 下载安装包。',
      );
      final releaseUrl = _extractString(
        releaseInfo,
        'html_url',
        fallback: AppConstants.githubReleasesPage,
      );

      if (isNewerThanCurrent(latestVersion, currentVersion: currentVersion)) {
        _showUpdateDialog(
          context,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          releaseNotes: releaseNotes,
          releaseUrl: releaseUrl,
        );
      } else if (showNoUpdateMessage) {
        _showMessageDialog(context, '当前已是最新版本', '当前版本: $currentVersion');
      }
    } catch (e) {
      if (!context.mounted) return;
      if (showFailureMessage) {
        _showMessageDialog(context, '更新检查失败', '检查更新时发生错误: $e');
      }
    } finally {
      updateState.isChecking.value = false;
    }
  }

  Future<Map<String, dynamic>?> _fetchLatestRelease({
    bool includePrereleases = false,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(AppConstants.githubReleasesUrl),
            headers: {
              'Accept': 'application/vnd.github.v3+json',
              'User-Agent': 'astral',
            },
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) return null;

      final decoded = json.decode(response.body);
      if (decoded is! List) return null;

      for (final item in decoded) {
        if (item is! Map) continue;
        final release = Map<String, dynamic>.from(item);
        if (release['draft'] == true) continue;
        if (!includePrereleases && release['prerelease'] == true) continue;
        if (_versionFromRelease(release) == null) continue;
        return release;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  String? _versionFromRelease(Map<String, dynamic> release) {
    final tag = _extractString(release, 'tag_name');
    if (tag.isEmpty || !_looksLikeSemverTag(tag)) return null;
    return tag;
  }

  bool _looksLikeSemverTag(String tag) {
    final core = AppVersion.normalize(tag).split('-').first;
    return RegExp(r'^\d+\.\d+').hasMatch(core);
  }

  String _extractString(
    Map<String, dynamic> source,
    String key, {
    String fallback = '',
  }) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  void _showUpdateDialog(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
    required String releaseNotes,
    required String releaseUrl,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('发现新版本: $latestVersion'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前版本: $currentVersion'),
              const SizedBox(height: 12),
              const Text('更新说明:'),
              const SizedBox(height: 8),
              Text(releaseNotes, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
              Text(
                '请前往 GitHub Releases 下载对应平台的安装包。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后再说'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _launchUrl(releaseUrl);
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }

  Future<void> openReleasesPage() => _launchUrl(AppConstants.githubReleasesPage);

  void _showMessageDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (title.contains('失败'))
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _launchUrl(AppConstants.githubReleasesPage);
              },
              child: const Text('打开 Releases'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
