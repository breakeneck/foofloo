import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Settings screen: rescan, music root, theme, connection/unpair.
class SettingsScreen extends StatelessWidget {
  final FooFloApiClient client;
  final String root;
  final String scanState;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final bool compact;
  final ValueChanged<bool> onCompactChanged;
  final VoidCallback onRescan;
  final ValueChanged<String> onRootChanged;
  final VoidCallback onLogout;
  const SettingsScreen(
      {super.key,
      required this.client,
      required this.root,
      required this.scanState,
      required this.themeMode,
      required this.onThemeChanged,
      required this.compact,
      required this.onCompactChanged,
      required this.onRescan,
      required this.onRootChanged,
      required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Налаштування')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Рескан бібліотеки'),
            subtitle: Text(scanState),
            onTap: onRescan,
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Корінь музики на сервері'),
            subtitle: Text(root, overflow: TextOverflow.ellipsis),
            onTap: () {
              final ctrl = TextEditingController(text: root);
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Корінь музики'),
                  content: TextField(controller: ctrl, autocorrect: false),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Скасувати')),
                    TextButton(
                      onPressed: () async {
                        final r = ctrl.text.trim();
                        Navigator.pop(ctx); // dialog
                        if (r.isNotEmpty) {
                          final prefs =
                              await SharedPreferences.getInstance();
                          await prefs.setString('root', r);
                          onRootChanged(r);
                        }
                      },
                      child: const Text('Зберегти й рескан'),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Тема',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (v) {
              if (v != null) {
                onThemeChanged(v);
                SharedPreferences.getInstance()
                    .then((p) => p.setString('theme', v.name));
              }
            },
            child: Column(
              children: [
                for (final m in const [
                  (ThemeMode.system, 'Авто (як у системи)'),
                  (ThemeMode.light, 'Світла'),
                  (ThemeMode.dark, 'Темна'),
                ])
                  RadioListTile<ThemeMode>(
                    title: Text(m.$2),
                    value: m.$1,
                  ),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Компактний список'),
            subtitle: const Text('трек + артист в один рядок, менше відступів'),
            value: compact,
            onChanged: onCompactChanged,
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Підключення'),
            subtitle: Text(client.base.toString()),
          ),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('Від\'єднати пристрій'),
            subtitle: const Text('Знадобиться новий pairing-код'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Від\'єднати пристрій?'),
                  content: const Text(
                      'Токен буде видалено з Keystore.\n'
                      'Щоб знову слухати, знадобиться новий pairing-код.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Скасувати')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Від\'єднати')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                Navigator.pop(context); // settings
                onLogout();
              }
            },
          ),
        ],
      ),
    );
  }
}