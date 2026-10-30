import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../daily/daily_controller.dart';
import '../feedback/feedback_sheet.dart';
import '../notifications/notifications_controller.dart';
import '../packs/packs_providers.dart';
import '../puzzle/application/progress_providers.dart';
import '../wallet/wallet_controller.dart';
import 'settings_controller.dart';
import 'settings_model.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final config = ref.watch(gameConfigProvider);
    final appConfig = ref.watch(appConfigProvider);
    final lang = s.puzzleProfile;
    final ads = ref.watch(adsServiceProvider);
    final notifications = ref.watch(notificationsServiceProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        children: [
          SectionHeader(l10n.settingsSectionLanguage),
          ListTile(
            title: Text(l10n.settingsLanguage),
            trailing: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'he', label: Text(l10n.languageHebrew)),
                ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
              ],
              selected: {s.uiLang},
              onSelectionChanged: (v) => ctl.setLanguage(v.first),
              showSelectedIcon: false,
            ),
          ),

          SectionHeader(l10n.settingsSectionPlay),
          SwitchListTile(
            title: Text(l10n.settingsSystemKeyboard),
            subtitle: Text(l10n.settingsSystemKeyboardHint),
            value: s.systemKeyboard,
            onChanged: ctl.setSystemKeyboard,
          ),
          if (!s.systemKeyboard)
            ListTile(
              title: Text(l10n.settingsKeyboardLayout),
              trailing: DropdownButton<String>(
                value: s.keyboardLayoutFor(lang).id,
                onChanged: (v) => v == null ? null : ctl.setKeyboardLayout(v),
                items: [
                  for (final layout in lang.keyboardLayouts)
                    DropdownMenuItem(value: layout.id, child: Text(l10n.layoutName(layout.id))),
                ],
              ),
            ),
          SwitchListTile(title: Text(l10n.settingsBigKeyboard), value: s.bigKeyboard, onChanged: ctl.setBigKeyboard),
          SwitchListTile(title: Text(l10n.settingsShowTimer), value: s.showTimer, onChanged: ctl.setShowTimer),
          SwitchListTile(title: Text(l10n.settingsSkipFilled), value: s.skipFilled, onChanged: ctl.setSkipFilled),
          SwitchListTile(title: Text(l10n.settingsAutoNextWord), value: s.autoNextWord, onChanged: ctl.setAutoNextWord),
          for (final level in LevelInfo.all)
            ListTile(
              title: Text(l10n.settingsDefaultMode(level.level)),
              trailing: DropdownButton<PlayMode>(
                value: s.modePerLevel[level.level] ?? config.defaultModeForLevel(level.level),
                onChanged: (m) => m == null ? null : ctl.setModeForLevel(level.level, m),
                items: [for (final m in PlayMode.values) DropdownMenuItem(value: m, child: Text(l10n.modeName(m)))],
              ),
            ),

          SectionHeader(l10n.settingsSectionDisplay),
          ListTile(
            title: Text(l10n.settingsTextSize),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<double>(
                segments: [
                  for (final v in AppSettings.textScales)
                    ButtonSegment(value: v, label: Text('${(v * 100).round()}%')),
                ],
                selected: {_nearest(s.textScale)},
                onSelectionChanged: (v) => ctl.setTextScale(v.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.settingsTheme),
            subtitle: Text(s.useCustomTheme
                ? l10n.themeCustom
                : s.highContrast
                    ? l10n.themeHighContrast
                    : switch (s.themeMode) {
                        ThemeMode.system => l10n.themeSystem,
                        ThemeMode.light => l10n.themeLight,
                        ThemeMode.dark => l10n.themeDark,
                      }),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/settings/theme'),
          ),

          SectionHeader(l10n.settingsSectionFeedback),
          SwitchListTile(title: Text(l10n.settingsHaptics), value: s.haptics, onChanged: ctl.setHaptics),
          SwitchListTile(title: Text(l10n.settingsSounds), value: s.sounds, onChanged: ctl.setSounds),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.tonalIcon(
              onPressed: () {
                ctl.applySeniorsPreset();
                showSnack(context, l10n.seniorsApplied);
              },
              icon: const Icon(Icons.accessibility_new_rounded),
              label: Text(l10n.settingsSeniorsPreset),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(l10n.settingsSeniorsPresetDescription, style: Theme.of(context).textTheme.bodySmall),
          ),

          SectionHeader(l10n.settingsSectionNotifications),
          SwitchListTile(
            title: Text(l10n.settingsNotifDaily),
            value: s.notificationsDailyReady,
            onChanged: notifications.available
                ? (on) async {
                    final l = context.l10n;
                    if (on) {
                      final ok = await ref.read(notificationsProvider.notifier).enable(l, daily: true, streak: s.notificationsStreak);
                      if (!ok && context.mounted) showSnack(context, l.notifDenied);
                    } else {
                      ctl.setNotifications(daily: false);
                      await ref.read(notificationsProvider.notifier).reschedule(l);
                    }
                  }
                : null,
          ),
          SwitchListTile(
            title: Text(l10n.settingsNotifStreak),
            value: s.notificationsStreak,
            onChanged: notifications.available
                ? (on) async {
                    final l = context.l10n;
                    if (on) {
                      final ok = await ref.read(notificationsProvider.notifier).enable(l, daily: s.notificationsDailyReady, streak: true);
                      if (!ok && context.mounted) showSnack(context, l.notifDenied);
                    } else {
                      ctl.setNotifications(streak: false);
                      await ref.read(notificationsProvider.notifier).reschedule(l);
                    }
                  }
                : null,
          ),
          ListTile(
            title: Text(l10n.settingsNotifHour),
            enabled: s.notificationsDailyReady,
            trailing: DropdownButton<int>(
              value: s.notificationsHour,
              onChanged: s.notificationsDailyReady
                  ? (h) async {
                      if (h == null) return;
                      ctl.setNotifications(hour: h);
                      await ref.read(notificationsProvider.notifier).reschedule(context.l10n);
                    }
                  : null,
              items: [for (var h = 5; h <= 22; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
            ),
          ),

          SectionHeader(l10n.settingsSectionPrivacy),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.settingsManageConsent),
            subtitle: ads.enabled ? null : Text(l10n.consentUnavailable),
            enabled: ads.enabled,
            onTap: ads.enabled ? () => ads.showPrivacyOptions() : null,
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text(l10n.settingsDeleteData),
            onTap: () => _confirmDelete(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(l10n.storeTitle),
            onTap: () => context.push('/store'),
          ),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: Text(l10n.feedbackSettingsTile),
            subtitle: Text(l10n.feedbackSettingsHint),
            onTap: () => showFeedbackSheet(context),
          ),
          // iOS needs the App Store id to open the listing.
          if (defaultTargetPlatform != TargetPlatform.iOS || appConfig.appStoreId.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.star_outline_rounded),
              title: Text(l10n.rateApp),
              subtitle: Text(l10n.rateAppHint),
              onTap: () => ref.read(reviewServiceProvider).openStore(),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(l10n.settingsAbout),
            onTap: () => context.push('/about'),
          ),
        ],
      ),
    );
  }

  double _nearest(double v) {
    var best = AppSettings.textScales.first;
    for (final s in AppSettings.textScales) {
      if ((s - v).abs() < (best - v).abs()) best = s;
    }
    return best;
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsDeleteData),
        content: Text(l10n.deleteDataConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(jsonStoreProvider).clear();
    ref.read(settingsProvider.notifier).reset();
    ref.read(walletProvider.notifier).reset();
    ref.read(dailyHistoryProvider.notifier).reset();
    ref.read(progressSummariesProvider.notifier).clear();
    if (context.mounted) showSnack(context, l10n.deleteDataDone);
  }
}
