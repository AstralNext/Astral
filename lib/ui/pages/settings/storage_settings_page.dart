import 'package:astral/config/app_dimensions.dart';
import 'package:astral/config/theme.dart';
import 'package:astral/data/services/instance_catalog_service.dart';
import 'package:astral/di.dart';
import 'package:astral/ui/widgets/astral_card.dart';
import 'package:astral/ui/widgets/astral_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  String _rootPath = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = await getIt<InstanceCatalogService>().ensureInstancesDirPath();
    if (!mounted) return;
    setState(() => _rootPath = path);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.pagePaddingH,
        AppDimensions.pagePaddingV,
        AppDimensions.pagePaddingH,
        20,
      ),
      children: [
        AstralCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: const Text('数据存储'),
                subtitle: Text(
                  '本机实例配置目录',
                  style: TextStyle(color: palette.textSecondary),
                ),
                leading: Icon(
                  Icons.storage_outlined,
                  color: palette.accent,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Text(
                '实例与配置保存在本机目录。',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: palette.surfaceDecoration(
                  variant: AstralSurfaceVariant.inset,
                  radius: AppDimensions.radiusSm,
                ),
                child: SelectableText(
                  _rootPath.isEmpty ? '加载中…' : _rootPath,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    height: 1.4,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _rootPath.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: _rootPath),
                          );
                          if (context.mounted) {
                            showAstralSnack(context, '已复制路径');
                          }
                        },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制路径'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
