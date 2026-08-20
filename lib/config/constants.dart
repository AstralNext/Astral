class AppConstants {
  AppConstants._();

  static const String githubOwner = 'AstralNext';
  static const String githubRepo = 'Astral';
  static const String githubReleasesUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases?per_page=20';
  static const String githubReleasesPage =
      'https://github.com/$githubOwner/$githubRepo/releases';
  static const String githubRepoPage =
      'https://github.com/$githubOwner/$githubRepo';
  static const String githubIssuesPage =
      'https://github.com/$githubOwner/$githubRepo/issues';
}
