/// 应用主题标识（Morandi / Ins 配色）。
enum AppThemeId {
  insCream,
  elegantGreen,
  mistBlue,
  lavenderGrey,
  cementGrey,
  darkCoffee,
  cyber2077,
}

/// 应用默认主题。
const AppThemeId kDefaultAppThemeId = AppThemeId.darkCoffee;

extension AppThemeIdCodec on AppThemeId {
  String get label => switch (this) {
        AppThemeId.insCream => '奶油',
        AppThemeId.elegantGreen => '淡雅绿',
        AppThemeId.mistBlue => '雾蓝',
        AppThemeId.lavenderGrey => '薰衣草',
        AppThemeId.cementGrey => '水泥灰',
        AppThemeId.darkCoffee => '黑咖',
        AppThemeId.cyber2077 => '2077',
      };

  String get subtitle => switch (this) {
        AppThemeId.insCream => '暖灰底 · 奶白卡片 · 奶茶棕',
        AppThemeId.elegantGreen => '薄荷底 · 白卡片 · 鼠尾草绿',
        AppThemeId.mistBlue => '雾蓝底 · 白卡片 · 灰蓝强调',
        AppThemeId.lavenderGrey => '淡紫底 · 白卡片 · 薰衣草',
        AppThemeId.cementGrey => '中灰底 · 白卡片 · 中性灰',
        AppThemeId.darkCoffee => '深灰底 · 金棕点缀',
        AppThemeId.cyber2077 => '深空底 · 霓虹黄青点缀',
      };

  static AppThemeId fromIndex(int index) {
    if (index < 0 || index >= AppThemeId.values.length) {
      return kDefaultAppThemeId;
    }
    return AppThemeId.values[index];
  }

  int get storageIndex => AppThemeId.values.indexOf(this);
}
