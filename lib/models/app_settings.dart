/// App-wide preferences -- appearance + which LLM connection is used by
/// default for new chats. A single record, stored under one fixed key (see
/// lib/storage/local_storage.dart), not a list.
library;

/// Curated Google Fonts family names -- kept small on purpose (every entry
/// here must actually look right for both prose and code-ish wiki content).
const kAvailableFontFamilies = <String>[
  'Noto Sans JP',
  'Inter',
  'Roboto',
  'Source Sans 3',
  'JetBrains Mono',
  'Fira Code',
  'IBM Plex Mono',
];

const kDefaultFontFamily = 'Noto Sans JP';

enum AppThemeMode { system, light, dark }

class AppSettings {
  final String fontFamily;
  final double fontScale; // 0.85 - 1.4, applied via TextTheme.apply(fontSizeFactor:)
  final AppThemeMode themeMode;
  final String? defaultConnectionId;

  const AppSettings({
    this.fontFamily = kDefaultFontFamily,
    this.fontScale = 1.0,
    this.themeMode = AppThemeMode.system,
    this.defaultConnectionId,
  });

  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily,
        'fontScale': fontScale,
        'themeMode': themeMode.name,
        'defaultConnectionId': defaultConnectionId,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        fontFamily: json['fontFamily'] as String? ?? kDefaultFontFamily,
        fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
        themeMode: AppThemeMode.values.firstWhere(
          (m) => m.name == json['themeMode'],
          orElse: () => AppThemeMode.system,
        ),
        defaultConnectionId: json['defaultConnectionId'] as String?,
      );

  AppSettings copyWith({
    String? fontFamily,
    double? fontScale,
    AppThemeMode? themeMode,
    String? defaultConnectionId,
    bool clearDefaultConnection = false,
  }) =>
      AppSettings(
        fontFamily: fontFamily ?? this.fontFamily,
        fontScale: fontScale ?? this.fontScale,
        themeMode: themeMode ?? this.themeMode,
        defaultConnectionId:
            clearDefaultConnection ? null : (defaultConnectionId ?? this.defaultConnectionId),
      );
}
