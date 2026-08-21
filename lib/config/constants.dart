class AppConstants {
  AppConstants._();

  static const String githubOwner = 'AstralNext';
  static const String githubRepo = 'Astral';
  /// 官方 Latest（一条，不翻页）。
  static const String githubLatestReleaseUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  /// 最近一条起最多 5 条，仅用于包含预发布；不翻后续页。
  static const String githubRecentReleasesUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases?per_page=5';

  static const String githubReleasesPage =
      'https://github.com/$githubOwner/$githubRepo/releases';
  static const String githubRepoPage =
      'https://github.com/$githubOwner/$githubRepo';
  static const String githubIssuesPage =
      'https://github.com/$githubOwner/$githubRepo/issues';
}
