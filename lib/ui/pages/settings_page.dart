import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
import '../../core/bidi.dart';
import '../../core/catppuccin.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../player/mpv_client.dart';

/// Languages offered for the default audio and subtitle tracks. Servers often
/// tag tracks with two-letter codes, so that is what the picker stores; the
/// player also matches full names in track titles.
const List<String> _languageCodes = <String>[
  'en',
  'ar',
  'fr',
  'es',
  'de',
  'it',
  'pt',
  'ru',
  'tr',
  'fa',
  'ur',
  'hi',
  'bn',
  'id',
  'ms',
  'zh',
  'ja',
  'ko',
];

const List<String> _audioLanguages = <String>['auto', ..._languageCodes];

const List<String> _subtitleLanguages = <String>[
  'auto',
  'off',
  ..._languageCodes,
];

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onOpenSources});

  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mojacColors;
    final settings = state.settings;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  strings.settings,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: strings.appearance,
                  children: <Widget>[
                    _FieldLabel(text: strings.theme),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final family in ThemeFamily.values)
                          _ThemeChip(
                            family: family,
                            selected: settings.themeFamily == family,
                            accent: settings.accent,
                            label: strings.themeFamilyLabel(family),
                            onTap: () => unawaited(
                              state.setThemeFamily(family),
                            ),
                          ),
                      ],
                    ),
                    if (settings.themeFamily == ThemeFamily.system) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        strings.systemThemeHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                              height: 1.4,
                            ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _FieldLabel(text: strings.accent),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        for (final accent in ThemeAccent.values)
                          _AccentDot(
                            accent: accent,
                            selected: settings.accent == accent,
                            palette: paletteFor(
                              settings.themeFamily == ThemeFamily.system
                                  ? ThemeFamily.mocha
                                  : settings.themeFamily,
                            ),
                            onTap: () => unawaited(state.setAccent(accent)),
                          ),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: strings.language,
                  children: <Widget>[
                    InputDecorator(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.translate_rounded),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<AppLanguage>(
                          value: settings.language,
                          isExpanded: true,
                          isDense: true,
                          items: <DropdownMenuItem<AppLanguage>>[
                            DropdownMenuItem<AppLanguage>(
                              value: AppLanguage.system,
                              child: Text(strings.systemLanguage),
                            ),
                            DropdownMenuItem<AppLanguage>(
                              value: AppLanguage.english,
                              child: Text(strings.english),
                            ),
                            DropdownMenuItem<AppLanguage>(
                              value: AppLanguage.arabic,
                              child: Text(strings.arabic),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              unawaited(state.setLanguage(value));
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.languageHelp,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                          ),
                    ),
                    const SizedBox(height: 20),
                    _FieldLabel(text: strings.timeFormat),
                    SwitchListTile(
                      value: settings.use24HourTime,
                      onChanged: (value) =>
                          unawaited(state.setUse24HourTime(value)),
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.use24HourTime),
                      subtitle: Text(
                        strings.use24HourTimeHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: strings.sources,
                  children: <Widget>[
                    if (state.sources.isEmpty)
                      Text(
                        strings.noSourcesBody,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                              height: 1.4,
                            ),
                      )
                    else ...<Widget>[
                      _InfoRow(
                        icon: Icons.dns_rounded,
                        label: strings.activeSource,
                        value: state.activeSource?.name ??
                            strings.noActiveSource,
                      ),
                      _InfoRow(
                        icon: Icons.layers_rounded,
                        label: strings.sourceType,
                        value: state.activeSource?.provider.label ??
                            strings.notConfigured,
                      ),
                      _InfoRow(
                        icon: Icons.calendar_month_rounded,
                        label: strings.guideSource,
                        value: state.xmltvLocation ?? strings.notConfigured,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          onPressed: onOpenSources,
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: Text(strings.manageSources),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      strings.sourcesHelp,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
                _Section(
                  title: strings.playback,
                  children: <Widget>[
                    SwitchListTile(
                      value: settings.showChannelBanner,
                      onChanged: (value) =>
                          unawaited(state.setShowChannelBanner(value)),
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.channelBanner),
                      subtitle: Text(
                        strings.channelBannerHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SelectField<String>(
                      icon: Icons.graphic_eq_rounded,
                      label: strings.defaultAudioLanguage,
                      help: strings.defaultAudioHelp,
                      value: settings.defaultAudioLanguage ?? 'auto',
                      items: _audioLanguages,
                      itemLabel: strings.languageName,
                      onChanged: (value) => unawaited(
                        state.setDefaultAudioLanguage(
                          value == 'auto' ? null : value,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SelectField<String>(
                      icon: Icons.subtitles_rounded,
                      label: strings.defaultSubtitles,
                      help: strings.defaultSubtitlesHelp,
                      value: settings.defaultSubtitleLanguage ?? 'auto',
                      items: _subtitleLanguages,
                      itemLabel: strings.languageName,
                      onChanged: (value) => unawaited(
                        state.setDefaultSubtitleLanguage(
                          value == 'auto' ? null : value,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.playerSettingsHelp,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                            height: 1.4,
                          ),
                    ),
                    // The switch only matters when a system mpv is installed;
                    // without one the launcher falls back to the built-in
                    // player.
                    if (Platform.isLinux && MpvClient.resolveBinary() != null)
                      ...<Widget>[
                        const Divider(height: 28),
                        SwitchListTile(
                          value: settings.nativePlayer,
                          onChanged: (value) =>
                              unawaited(state.setNativePlayer(value)),
                          contentPadding: EdgeInsets.zero,
                          title: Text(strings.nativePlayer),
                          subtitle: Text(
                            strings.nativePlayerHelp,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colors.subtext0,
                                    ),
                          ),
                        ),
                      ],
                  ],
                ),
                _Section(
                  title: strings.dataAndGuide,
                  children: <Widget>[
                    _InfoRow(
                      icon: Icons.schedule_rounded,
                      label: strings.lastUpdated,
                      value: state.lastLoaded == null
                          ? strings.never
                          : '${strings.relativeTime(state.lastLoaded!, state.now)} · '
                              '${strings.formatDateTime(state.lastLoaded!, use24HourTime: settings.use24HourTime)}',
                    ),
                    if (state.hasContent)
                      _InfoRow(
                        icon: Icons.live_tv_rounded,
                        label: strings.channelsLabel,
                        value:
                            '${strings.channelCount(state.channels.length)} · '
                            '${strings.programmeCount(state.epg.programmeCount)}',
                      ),
                    const SizedBox(height: 4),
                    _SelectField<int>(
                      icon: Icons.view_timeline_rounded,
                      label: strings.guideWindow,
                      help: strings.guideWindowHelp,
                      value: settings.guideHours,
                      items: const <int>[12, 24, 48, 72, 96, 168],
                      itemLabel: strings.guideHoursLabel,
                      onChanged: (value) =>
                          unawaited(state.setGuideHours(value)),
                    ),
                    const SizedBox(height: 16),
                    _SelectField<int>(
                      icon: Icons.autorenew_rounded,
                      label: strings.autoRefresh,
                      help: strings.autoRefreshHelp,
                      value: settings.refreshMinutes,
                      items: const <int>[0, 15, 30, 60, 180, 360, 720],
                      itemLabel: (minutes) => minutes == 0
                          ? strings.refreshOff
                          : strings.refreshEvery(minutes),
                      onChanged: (value) =>
                          unawaited(state.setRefreshMinutes(value)),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed:
                              state.isLoading ? null : () => state.refresh(),
                          icon: state.isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            state.isLoading ? strings.refreshing : strings.refresh,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: strings.about,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: colors.accentSoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.live_tv_rounded,
                            color: colors.accent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${strings.appName} $kAppVersion',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                strings.appTagline,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: colors.subtext0),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      strings.aboutBody,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.subtext1,
                            height: 1.55,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      kProjectUrl,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.accent,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () {
                            showLicensePage(
                              context: context,
                              applicationName: strings.appName,
                              applicationVersion: kAppVersion,
                              applicationIcon: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.live_tv_rounded,
                                  color: colors.accent,
                                  size: 36,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.description_outlined,
                            size: 18,
                          ),
                          label: Text(strings.licenses),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface0,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            kLicenseName,
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: colors.subtext0,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface0,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.surface1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.family,
    required this.selected,
    required this.accent,
    required this.label,
    required this.onTap,
  });

  final ThemeFamily family;
  final bool selected;
  final ThemeAccent accent;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    final preview = previewColorFor(family, accent);
    return Material(
      color: selected ? colors.accentSoft : colors.mantle,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? colors.accent : colors.surface1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: family == ThemeFamily.amoled
                      ? Colors.black
                      : preview,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.overlay0.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.accent,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final ThemeAccent accent;
  final bool selected;
  final CatppuccinPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = palette.accent(accent);
    final foreground =
        color.computeLuminance() > 0.55 ? Colors.black : Colors.white;
    return Tooltip(
      message: accent.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 18, color: foreground)
              : null,
        ),
      ),
    );
  }
}

class _SelectField<T> extends StatelessWidget {
  const _SelectField({
    required this.icon,
    required this.label,
    required this.help,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String help;
  final T value;
  final List<T> items;
  final String Function(T value) itemLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    // Stored settings are clamped, not restricted to the offered presets, so
    // an older value still gets a menu entry instead of tripping the dropdown
    // assertion.
    final options = items.contains(value) ? items : <T>[value, ...items];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _FieldLabel(text: label),
        const SizedBox(height: 6),
        InputDecorator(
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              items: <DropdownMenuItem<T>>[
                for (final option in options)
                  DropdownMenuItem<T>(
                    value: option,
                    child: Text(itemLabel(option)),
                  ),
              ],
              onChanged: (next) {
                if (next != null) {
                  onChanged(next);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          help,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.subtext0,
                height: 1.4,
              ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.mojacColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.overlay0),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.subtext0,
                  ),
            ),
          ),
          Expanded(
            child: BidiText(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
