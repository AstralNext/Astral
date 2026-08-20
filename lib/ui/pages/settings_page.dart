import 'dart:io';

import 'package:astral/config/app_dimensions.dart';
import 'package:astral/config/app_theme_id.dart';
import 'package:astral/data/services/windows_startup_launch.dart';
import 'package:astral/data/state/settings_state.dart';
import 'package:astral/data/state/theme_reveal_state.dart';
import 'package:astral/data/state/update_state.dart';
import 'package:astral/di.dart';
import 'package:astral/ui/pages/settings/about_page.dart';
import 'package:astral/ui/pages/settings/kernel_settings_section.dart';
import 'package:astral/ui/pages/tools/network_diagnostic_page.dart';
import 'package:astral/ui/shell/shell_content_controller.dart';
import 'package:astral/ui/widgets/astral_settings_section.dart';
import 'package:astral/ui/widgets/astral_snack.dart';
import 'package:astral/ui/widgets/theme_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// MD3 风格设置：按分类分组的 surface 列表。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _openSubpage({required Widget page, required String title}) {
    getIt<ShellContentController>().showOverlay(content: page, title: title);
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = getIt<SettingsState>();
    final updateState = getIt<UpdateState>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.pagePaddingH,
        AppDimensions.pagePaddingV,
        AppDimensions.pagePaddingH,
        32,
      ),
      children: [
        Watch((context) {
          final id = settingsState.appThemeId.value;
          return AstralSettingsSection(
            title: '外观',
            items: [
              AstralSettingItem(
                icon: Icons.palette_outlined,
                label: '主题',
                subtitle: id.label,
                onTap: () => _pickTheme(context, settingsState, id),
              ),
            ],
          );
        }),
        const SizedBox(height: AppDimensions.sectionGap),

        if (settingsState.isDesktop) ...[
          AstralSettingsSection(
            title: '通用',
            child: Column(
              children: [
                Watch((context) {
                  return SwitchListTile(
                    secondary: const Icon(Icons.doorbell_outlined),
                    title: const Text('关闭时最小化到托盘'),
                    subtitle: const Text('隐藏到托盘；退出客户端后内核继续运行'),
                    value: settingsState.closeMinimize.value,
                    onChanged: (v) {
                      settingsState.closeMinimize.value = v;
                      settingsState.saveToPersistence();
                    },
                  );
                }),
                if (Platform.isWindows) ...[
                  const AstralSettingsDivider(),
                  Watch((context) {
                    return SwitchListTile(
                      secondary: const Icon(Icons.power_settings_new_outlined),
                      title: const Text('登录时启动'),
                      subtitle: const Text('登录 Windows 后自动打开 Astral'),
                      value: settingsState.launchAtStartup.value,
                      onChanged: (v) =>
                          _setLaunchAtStartup(context, settingsState, v),
                    );
                  }),
                  const AstralSettingsDivider(),
                  Watch((context) {
                    final login = settingsState.launchAtStartup.value;
                    return SwitchListTile(
                      secondary: const Icon(Icons.visibility_off_outlined),
                      title: const Text('启动后最小化到托盘'),
                      subtitle: Text(
                        login ? '登录自动打开时不弹出窗口' : '先打开「登录时启动」后生效',
                      ),
                      value: login && settingsState.startMinimized.value,
                      onChanged: login
                          ? (v) => _setStartMinimized(context, settingsState, v)
                          : null,
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.sectionGap),
          const KernelSettingsSection(),
          const SizedBox(height: AppDimensions.sectionGap),
        ],

        AstralSettingsSection(
          title: '更新',
          child: Column(
            children: [
              Watch((context) {
                return SwitchListTile(
                  secondary: const Icon(Icons.system_update_alt),
                  title: const Text('自动检查更新'),
                  subtitle: const Text('启动时检查客户端更新'),
                  value: updateState.autoCheckUpdate.value,
                  onChanged: updateState.setAutoCheckUpdate,
                );
              }),
              const AstralSettingsDivider(),
              Watch((context) {
                return SwitchListTile(
                  secondary: const Icon(Icons.science_outlined),
                  title: const Text('测试版频道'),
                  subtitle: const Text('接收预发布版本更新'),
                  value: updateState.beta.value,
                  onChanged: updateState.setBeta,
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionGap),

        AstralSettingsSection(
          title: '工具',
          items: [
            AstralSettingItem(
              icon: Icons.network_check,
              label: '网络诊断',
              subtitle: '检查网络连通性和延迟',
              onTap: () => _openSubpage(
                page: const NetworkDiagnosticPage(),
                title: '网络诊断',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.sectionGap),

        AstralSettingsSection(
          title: '关于',
          items: [
            AstralSettingItem(
              icon: Icons.info_outline_rounded,
              label: '关于 Astral',
              subtitle: '版本与更新',
              onTap: () => _openSubpage(page: const AboutPage(), title: '关于'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickTheme(
    BuildContext context,
    SettingsState settingsState,
    AppThemeId currentId,
  ) async {
    final picked = await showAppThemePickerSheet(context, current: currentId);
    if (picked == null || picked.themeId == currentId) return;

    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!context.mounted) return;

    getIt<ThemeRevealController>().beginReveal(
      origin: picked.origin,
      newTheme: picked.themeId,
    );
    settingsState.saveToPersistence();
  }

  Future<void> _setLaunchAtStartup(
    BuildContext context,
    SettingsState settingsState,
    bool enabled,
  ) async {
    try {
      await WindowsStartupLaunch.setEnabled(
        enabled,
        startMinimized: settingsState.startMinimized.value,
      );
      settingsState.launchAtStartup.value = enabled;
      await settingsState.saveToPersistence();
    } catch (e) {
      if (context.mounted) {
        showAstralSnack(context, '设置失败: $e');
      }
    }
  }

  Future<void> _setStartMinimized(
    BuildContext context,
    SettingsState settingsState,
    bool enabled,
  ) async {
    try {
      if (settingsState.launchAtStartup.value) {
        await WindowsStartupLaunch.setEnabled(
          true,
          startMinimized: enabled,
        );
      }
      settingsState.startMinimized.value = enabled;
      await settingsState.saveToPersistence();
    } catch (e) {
      if (context.mounted) {
        showAstralSnack(context, '设置失败: $e');
      }
    }
  }
}
