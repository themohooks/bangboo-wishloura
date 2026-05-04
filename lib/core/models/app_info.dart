/// Represents an installed app that can be included/excluded from the VPN tunnel.
class AppInfo {
  const AppInfo({
    required this.packageName,
    required this.label,
    required this.iconBase64,
    required this.isExcluded,
    required this.isWhitelist,
  });

  final String packageName;
  final String label;

  /// App icon as base64-encoded PNG (from native side).
  final String iconBase64;

  /// Whether this app is currently in the exclusion/inclusion set.
  final bool isExcluded;

  /// Whether the list operates as a whitelist (only listed apps go through VPN)
  /// or blacklist (listed apps bypass VPN).
  final bool isWhitelist;

  AppInfo copyWith({bool? isExcluded, bool? isWhitelist}) => AppInfo(
        packageName: packageName,
        label: label,
        iconBase64: iconBase64,
        isExcluded: isExcluded ?? this.isExcluded,
        isWhitelist: isWhitelist ?? this.isWhitelist,
      );

  @override
  bool operator ==(Object other) => other is AppInfo && other.packageName == packageName;

  @override
  int get hashCode => packageName.hashCode;
}
