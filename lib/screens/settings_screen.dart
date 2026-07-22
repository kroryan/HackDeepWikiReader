import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/llm_config.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'llm_connection_form_screen.dart';

/// App settings: this app's own LLM provider connections (independent of
/// any connected HackDeepWiki server -- see lib/llm/) and appearance
/// (font family/size, theme mode). Anything that needs configuring before
/// chat works lives here.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;
    final colors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LLM providers', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add provider',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LlmConnectionFormScreen()),
                ),
              ),
            ],
          ),
          Text(
            'Chat talks directly to whichever provider you configure here -- HackDeepWikiReader '
            'never sends your messages through a HackDeepWiki server.',
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (settingsProvider.connections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No providers configured yet. Add one to start chatting.',
                style: TextStyle(color: colors.muted),
              ),
            ),
          for (final connection in settingsProvider.connections)
            Card(
              child: ListTile(
                leading: Icon(
                  connection.id == settings.defaultConnectionId ? Icons.star : Icons.star_border,
                  color: connection.id == settings.defaultConnectionId ? colors.accentPrimary : colors.muted,
                ),
                title: Text(connection.name),
                subtitle: Text('${connection.preset.label} · ${connection.model}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => LlmConnectionFormScreen(existing: connection)),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'default') {
                      settingsProvider.setDefaultConnection(connection.id);
                    } else if (value == 'edit') {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => LlmConnectionFormScreen(existing: connection)),
                      );
                    } else if (value == 'delete') {
                      settingsProvider.removeConnection(connection.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'default', child: Text('Set as default')),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Font family', style: TextStyle(color: colors.muted, fontSize: 12)),
          DropdownButton<String>(
            isExpanded: true,
            value: settings.fontFamily,
            items: [
              for (final family in kAvailableFontFamilies)
                DropdownMenuItem(value: family, child: Text(family)),
            ],
            onChanged: (value) {
              if (value != null) settingsProvider.updateSettings(settings.copyWith(fontFamily: value));
            },
          ),
          const SizedBox(height: 16),
          Text('Font size', style: TextStyle(color: colors.muted, fontSize: 12)),
          Row(
            children: [
              const Text('A', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: settings.fontScale,
                  min: 0.85,
                  max: 1.4,
                  divisions: 11,
                  label: '${(settings.fontScale * 100).round()}%',
                  onChanged: (value) => settingsProvider.updateSettings(settings.copyWith(fontScale: value)),
                ),
              ),
              const Text('A', style: TextStyle(fontSize: 22)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Theme', style: TextStyle(color: colors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(value: AppThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: AppThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
              ButtonSegment(value: AppThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) =>
                settingsProvider.updateSettings(settings.copyWith(themeMode: selection.first)),
          ),
        ],
      ),
    );
  }
}
