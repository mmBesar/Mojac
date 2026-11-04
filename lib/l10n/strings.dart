import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/catppuccin.dart';
import '../data/models.dart';

/// Hand-written localisation. It keeps the build simple (no code generation)
/// while still covering every string the interface uses, in English and
/// Arabic.
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
  ];

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        const AppStrings(Locale('en'));
  }

  bool get isArabic => locale.languageCode == 'ar';

  String get appName => 'Mojac';
  String get appTagline => isArabic ? 'بثّك على موجتك' : 'Stream, Your Wave';

  String get channels => isArabic ? 'القنوات' : 'Channels';
  String get guide => isArabic ? 'الدليل' : 'Guide';
  String get sources => isArabic ? 'المصادر' : 'Sources';
  String get settings => isArabic ? 'الإعدادات' : 'Settings';

  String get searchChannels => isArabic ? 'ابحث في القنوات' : 'Search channels';
  String get searchProgrammes => isArabic ? 'ابحث في البرامج' : 'Search programmes';
  String get clearSearch => isArabic ? 'مسح البحث' : 'Clear search';
  String get allGroups => isArabic ? 'كل المجموعات' : 'All groups';
  String get noChannels => isArabic ? 'لا توجد قنوات بعد' : 'No channels yet';
  String get noChannelsBody => isArabic
      ? 'أضف مصدرًا لتحميل قائمة التشغيل والدليل.'
      : 'Add a source to load a playlist and its guide.';
  String get noSearchResults =>
      isArabic ? 'لا توجد قنوات تطابق البحث.' : 'No channels match your search.';
  String get addSource => isArabic ? 'إضافة مصدر' : 'Add source';
  String get now => isArabic ? 'الآن' : 'Now';
  String get next => isArabic ? 'التالي' : 'Next';
  String get live => isArabic ? 'مباشر' : 'LIVE';
  String get onNow => isArabic ? 'يُعرض الآن' : 'On now';
  String get upNext => isArabic ? 'التالي' : 'Up next';
  String get noProgrammeInfo =>
      isArabic ? 'لا تتوفر معلومات عن البرنامج' : 'No programme information';
  String get channel => isArabic ? 'القناة' : 'Channel';
  String get channelsLabel => isArabic ? 'القنوات' : 'Channels';
  String get programmesLabel => isArabic ? 'البرامج' : 'Programmes';

  String channelCount(int count) => isArabic
      ? '$count قناة'
      : count == 1
          ? '1 channel'
          : '$count channels';

  String programmeCount(int count) => isArabic
      ? '$count برنامج'
      : count == 1
          ? '1 programme'
          : '$count programmes';

  String get guideEmptyTitle => isArabic ? 'لا توجد بيانات للدليل' : 'No guide data yet';
  String get guideEmptyBody => isArabic
      ? 'أضف رابط XMLTV لهذا المصدر ثم حدّث البيانات.'
      : 'Add an XMLTV URL to this source, then refresh the data.';
  String get guideNoChannels => isArabic
      ? 'أضف مصدرًا لعرض جدول البرامج.'
      : 'Add a source to see the programme schedule.';
  String get guideNow => isArabic ? 'الآن' : 'Now';
  String get timelineZoom =>
      isArabic ? 'تكبير الجدول الزمني' : 'Timeline zoom';

  String get retry => isArabic ? 'إعادة المحاولة' : 'Retry';
  String get refresh => isArabic ? 'تحديث' : 'Refresh';
  String get refreshing => isArabic ? 'جارٍ التحديث…' : 'Refreshing…';
  String get close => isArabic ? 'إغلاق' : 'Close';
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get save => isArabic ? 'حفظ' : 'Save';
  String get edit => isArabic ? 'تعديل' : 'Edit';
  String get delete => isArabic ? 'حذف' : 'Delete';
  String get back => isArabic ? 'رجوع' : 'Back';
  String get done => isArabic ? 'تم' : 'Done';
  String get unknown => isArabic ? 'غير معروف' : 'Unknown';

  String get active => isArabic ? 'نشط' : 'Active';
  String get setActive => isArabic ? 'تعيين كنشط' : 'Set as active';
  String get activeSource => isArabic ? 'المصدر النشط' : 'Active source';
  String get noSources => isArabic ? 'لا توجد مصادر' : 'No sources yet';
  String get noSourcesBody => isArabic
      ? 'أضف أول مصدر M3U وXMLTV للبدء. يمكنك حفظ عدة مصادر والتبديل بينها.'
      : 'Add your first M3U and XMLTV source to get started. You can keep several sources and switch between them.';
  String get sourceName => isArabic ? 'اسم المصدر' : 'Source name';
  String get sourceNameHint =>
      isArabic ? 'مثال: تونار المنزل' : 'For example: Home Tunarr';
  String get playlistM3u => isArabic ? 'قائمة التشغيل (M3U)' : 'Playlist (M3U)';
  String get xmltvGuide => isArabic ? 'دليل XMLTV' : 'XMLTV guide';
  String get playlistHelp => isArabic
      ? 'رابط أو ملف M3U أو M3U8.'
      : 'An M3U or M3U8 URL or file.';
  String get guideHelp => isArabic
      ? 'اتركه فارغًا لاستخدام عنوان XMLTV المعلن في قائمة التشغيل.'
      : 'Leave empty to use the XMLTV URL advertised by the playlist.';
  String get location => isArabic ? 'الموقع' : 'Location';
  String get url => isArabic ? 'رابط' : 'URL';
  String get file => isArabic ? 'ملف' : 'File';
  String get chooseFile => isArabic ? 'اختيار ملف' : 'Choose file';
  String get browse => isArabic ? 'استعراض' : 'Browse';
  String get allowInsecure => isArabic
      ? 'السماح بشهادات HTTPS ذاتية التوقيع'
      : 'Allow self-signed HTTPS certificates';
  String get allowInsecureHelp => isArabic
      ? 'فعّل هذا الخيار للخوادم المحلية التي تستخدم شهادة HTTPS ذاتية التوقيع. يُطبَّق على قائمة التشغيل والدليل والشعارات والتشغيل. يُقبل HTTP العادي دائمًا.'
      : 'Enable for local servers with a self-signed HTTPS certificate. Applies to the playlist, guide, logos and playback. Plain HTTP is always accepted.';
  String get addSourceTitle => isArabic ? 'إضافة مصدر' : 'Add source';
  String get editSourceTitle => isArabic ? 'تعديل المصدر' : 'Edit source';
  String get sourceAdded => isArabic ? 'تمت إضافة المصدر.' : 'Source added.';
  String get sourceSaved => isArabic ? 'تم حفظ المصدر.' : 'Source saved.';
  String get sourceNameRequired =>
      isArabic ? 'أدخل اسمًا للمصدر.' : 'Enter a name for this source.';
  String get playlistRequired =>
      isArabic ? 'أدخل رابط أو ملف قائمة التشغيل.' : 'Enter a playlist URL or file.';
  String get invalidLocation => isArabic
      ? 'أدخل رابطًا يبدأ بـ http أو https، أو مسار ملف صالح.'
      : 'Enter an http(s) URL or a valid file path.';
  String get deleteSourceTitle =>
      isArabic ? 'حذف المصدر؟' : 'Delete source?';
  String deleteSourceBody(String name) => isArabic
      ? 'سيتم حذف «$name» وإعداداته من هذا الجهاز.'
      : '"$name" and its settings will be removed from this device.';
  String get testConnection => isArabic ? 'اختبار الاتصال' : 'Test connection';
  String get testing => isArabic ? 'جارٍ الاختبار…' : 'Testing…';
  String get testSucceeded => isArabic ? 'نجح الاتصال' : 'Connection succeeded';
  String get testFailed => isArabic ? 'فشل الاتصال' : 'Connection failed';
  String testSummary(int channels, int programmes) => isArabic
      ? 'تم العثور على $channels قناة و$programmes برنامج.'
      : 'Found ${channelCount(channels)} and ${programmeCount(programmes)}.';
  String get saveAndLoad => isArabic ? 'حفظ وتحميل' : 'Save and load';

  String get appearance => isArabic ? 'المظهر' : 'Appearance';
  String get theme => isArabic ? 'السمة' : 'Theme';
  String get accent => isArabic ? 'لون التمييز' : 'Accent';
  String get language => isArabic ? 'اللغة' : 'Language';
  String get systemLanguage => isArabic ? 'لغة النظام' : 'System language';
  String get english => 'English';
  String get arabic => 'العربية';
  String get timeFormat => isArabic ? 'صيغة الوقت' : 'Time format';
  String get use24HourTime =>
      isArabic ? 'استخدام نظام 24 ساعة' : 'Use 24-hour time';
  String get use24HourTimeHelp => isArabic
      ? 'عند الإيقاف يُعرض الوقت بنظام 12 ساعة مع ص/م.'
      : 'When off, times use a 12-hour clock with AM/PM.';
  String get dataAndGuide => isArabic ? 'البيانات والدليل' : 'Data and guide';
  String get lastUpdated => isArabic ? 'آخر تحديث' : 'Last updated';
  String get never => isArabic ? 'أبدًا' : 'Never';
  String get guideSource => isArabic ? 'مصدر الدليل' : 'Guide source';
  String get notConfigured => isArabic ? 'غير مُهيّأ' : 'Not configured';
  String get fromCache => isArabic ? 'من الذاكرة المؤقتة' : 'From cache';
  String get about => isArabic ? 'حول' : 'About';
  String get version => isArabic ? 'الإصدار' : 'Version';
  String get licenses => isArabic ? 'التراخيص' : 'Licenses';
  String get viewLicenses => isArabic ? 'عرض تراخيص المصادر المفتوحة' : 'View open-source licenses';
  String get projectPage => isArabic ? 'صفحة المشروع' : 'Project page';
  String get aboutBody => isArabic
      ? 'Mojac مشغّل IPTV حر ومفتوح المصدر لـ Android وLinux، مع دعم كامل للنصوص العربية والإنجليزية.'
      : 'Mojac is a free, open-source IPTV client for Android and Linux with first-class Arabic and English text support.';
  String get appearanceSystem => isArabic ? 'النظام' : 'System';
  String get systemThemeHelp => isArabic
      ? 'تتبع السمة ألوان النظام. على Android تُستخدم الألوان الديناميكية عند توفرها.'
      : 'Follows the system appearance. On Android, dynamic colours are used when available.';
  String get languageHelp => isArabic
      ? 'تتبع الواجهة لغة النظام عند اختيار «لغة النظام».'
      : 'The interface follows the system language when set to "System language".';

  String get themeSystem => isArabic ? 'النظام' : 'System';
  String get themeLatte => 'Latte';
  String get themeFrappe => 'Frappé';
  String get themeMacchiato => 'Macchiato';
  String get themeMocha => 'Mocha';
  String get themeAmoled => 'AMOLED';
  String themeFamilyLabel(ThemeFamily family) => switch (family) {
        ThemeFamily.system => themeSystem,
        ThemeFamily.latte => themeLatte,
        ThemeFamily.frappe => themeFrappe,
        ThemeFamily.macchiato => themeMacchiato,
        ThemeFamily.mocha => themeMocha,
        ThemeFamily.amoled => themeAmoled,
      };

  String get warningNoEpg => isArabic
      ? 'لا يوجد دليل XMLTV مُهيّأ لهذا المصدر، لذا تظهر أسماء القنوات فقط.'
      : 'No XMLTV guide is configured for this source, so only channel names are shown.';
  String get warningPlaylistCache => isArabic
      ? 'تعذّر الوصول إلى المصدر؛ تُعرض آخر قائمة تشغيل محفوظة.'
      : 'The source could not be reached; showing the last saved playlist.';
  String get warningEpgCache => isArabic
      ? 'تعذّر تحديث الدليل؛ تُعرض النسخة المحفوظة.'
      : 'The guide could not be refreshed; showing the saved copy.';
  String get warningEpgUnavailable => isArabic
      ? 'دليل البرامج غير متاح حاليًا.'
      : 'The programme guide is unavailable right now.';
  String get warningEpgEmpty => isArabic
      ? 'تم تحميل الدليل لكنه لا يحتوي على برامج ضمن النافذة الحالية.'
      : 'The guide loaded but has no programmes in the current window.';
  String warningText(LoadWarning warning) => switch (warning) {
        LoadWarning.noEpgEndpoint => warningNoEpg,
        LoadWarning.playlistFromCache => warningPlaylistCache,
        LoadWarning.epgFromCache => warningEpgCache,
        LoadWarning.epgUnavailable => warningEpgUnavailable,
        LoadWarning.epgEmpty => warningEpgEmpty,
      };

  String get playbackError =>
      isArabic ? 'تعذّر تشغيل البث' : 'Playback failed';
  String get playbackErrorBody => isArabic
      ? 'تعذّر فتح القناة. تحقق من اتصال الشبكة، ورابط البث، وإعداد الشهادات ذاتية التوقيع.'
      : 'The channel could not be opened. Check the network connection, the stream URL, and the self-signed certificate setting.';
  String get playbackRetry => isArabic ? 'إعادة المحاولة' : 'Retry playback';
  String get fullScreen => isArabic ? 'ملء الشاشة' : 'Full screen';
  String get play => isArabic ? 'تشغيل' : 'Play';
  String get pause => isArabic ? 'إيقاف مؤقت' : 'Pause';
  String get mute => isArabic ? 'كتم الصوت' : 'Mute';
  String get unmute => isArabic ? 'إلغاء كتم الصوت' : 'Unmute';
  String get volume => isArabic ? 'مستوى الصوت' : 'Volume';
  String get brightness => isArabic ? 'السطوع' : 'Brightness';
  String get exitFullScreen => isArabic ? 'إنهاء ملء الشاشة' : 'Exit full screen';
  String get streamUnavailable =>
      isArabic ? 'البث غير متاح' : 'Stream unavailable';

  String get playback => isArabic ? 'التشغيل' : 'Playback';
  String get nativePlayer => isArabic
      ? 'استخدام مشغّل mpv النظامي'
      : 'Use the system mpv player';
  String get nativePlayerHelp => isArabic
      ? 'يسلّم التشغيل على سطح المكتب القناة إلى مشغّل mpv النظامي، فيفكّ الترميز عبر كرت الرسوميات ويوفّر ملء شاشة حقيقياً وأدوات تحكم أصلية. لا تعرض Mojac أي أدوات تحكم؛ أغلق نافذة mpv لإنهاء البث. أوقف هذا الخيار لاستخدام المشغّل المدمج.'
      : 'Desktop playback hands the channel to the system mpv, which decodes with the GPU, provides real fullscreen and uses your own mpv configuration and controls. Mojac shows no controls: closing the mpv window ends the stream. Turn this off to use the built-in player instead.';
  String get nativePlaybackFailed => isArabic
      ? 'تعذّر على mpv تشغيل هذه القناة.'
      : 'mpv could not play this channel.';

  String get channelGuide => isArabic ? 'دليل القناة' : 'Channel guide';
  String get watchLive => isArabic ? 'مشاهدة مباشرة' : 'Watch live';
  String get programmeGuide =>
      isArabic ? 'جدول البرامج' : 'Programme schedule';

  String get favorites => isArabic ? 'المفضلة' : 'Favorites';
  String get search => isArabic ? 'بحث' : 'Search';
  String get searchHint => isArabic
      ? 'ابحث عن قناة أو برنامج أو مجموعة…'
      : 'Search channels, programmes, groups…';
  String get searchPrompt => isArabic
      ? 'اكتب اسم قناة أو برنامجًا أو مجموعة. تطابق العناوين والوصف والحلقات.'
      : 'Type a channel, programme or group. Titles, descriptions and episodes all match.';
  String get searchNoResults => isArabic
      ? 'لا توجد نتائج مطابقة.'
      : 'No matching results.';
  String get resultChannels => isArabic ? 'القنوات' : 'Channels';
  String get resultProgrammes => isArabic ? 'البرامج' : 'Programmes';
  String get searchGroups => isArabic ? 'المجموعات' : 'Groups';
  String searchResultCount(int count) =>
      isArabic ? '$count نتيجة' : '$count result${count == 1 ? '' : 's'}';
  String get favoritesEmptyTitle =>
      isArabic ? 'لا توجد قنوات مفضلة بعد' : 'No favorites yet';
  String get favoritesEmptyBody => isArabic
      ? 'اضغط النجمة بجانب أي قناة لتظهر هنا دائمًا.'
      : 'Tap the star beside a channel and it will always be waiting here.';
  String get addFavorite => isArabic ? 'إضافة إلى المفضلة' : 'Add to favorites';
  String get removeFavorite =>
      isArabic ? 'إزالة من المفضلة' : 'Remove from favorites';
  String get addedToFavorites =>
      isArabic ? 'أُضيفت إلى المفضلة.' : 'Added to favorites.';
  String get removedFromFavorites =>
      isArabic ? 'أُزيلت من المفضلة.' : 'Removed from favorites.';
  String favoriteCount(int count) => isArabic
      ? '$count قناة مفضلة'
      : count == 1
          ? '1 favorite'
          : '$count favorites';
  String get noGroupChannels => isArabic
      ? 'لا توجد قنوات في هذه المجموعة.'
      : 'No channels in this group.';

  String get switchSource => isArabic ? 'تبديل المصدر' : 'Switch source';
  String get chooseSource => isArabic ? 'اختر مصدرًا' : 'Choose a source';
  String get manageSources =>
      isArabic ? 'إدارة المصادر' : 'Manage sources';
  String get sourcesHelp => isArabic
      ? 'احفظ عدة مصادر وبدّل بينها بسرعة من الشريط العلوي.'
      : 'Keep several sources and switch between them from the top bar.';
  String get sourceType => isArabic ? 'نوع المصدر' : 'Source type';
  String get sourceTypeHelp => isArabic
      ? 'اختر Tunarr أو ErsatzTV وأدخل عنوان الخادم فقط؛ سيجلب Mojac قائمة التشغيل والدليل تلقائيًا.'
      : 'Pick Tunarr or ErsatzTV and enter just the server address; Mojac finds the playlist and guide automatically.';
  String get serverAddress =>
      isArabic ? 'عنوان الخادم' : 'Server address';
  String get serverAddressHint => 'https://tunarr.hs.lan';
  String get providerIptvHelp => isArabic
      ? 'أدخل رابط M3U ورابط XMLTV بنفسك.'
      : 'Enter the M3U and XMLTV URLs yourself.';
  String get providerTunarrHelp => isArabic
      ? 'يُستخدم /api/channels.m3u و/api/xmltv.xml تلقائيًا.'
      : 'Uses /api/channels.m3u and /api/xmltv.xml automatically.';
  String get providerErsatzHelp => isArabic
      ? 'يُستخدم /iptv/channels.m3u و/iptv/xmltv.xml تلقائيًا.'
      : 'Uses /iptv/channels.m3u and /iptv/xmltv.xml automatically.';
  String get serverAddressRequired => isArabic
      ? 'أدخل عنوان خادم Tunarr أو ErsatzTV.'
      : 'Enter the Tunarr or ErsatzTV server address.';
  String providerDetected(String name) => isArabic
      ? 'تم التعرف على $name وتعبئة الروابط.'
      : 'Detected $name and filled in the URLs.';

  String get guideWindow => isArabic ? 'مدة الدليل' : 'Guide window';
  String get guideWindowHelp => isArabic
      ? 'كم ساعة يعرضها الجدول الزمني، بدءًا من الآن. المزيد يعني تمريرًا أطول وتحميلًا أكبر للبرامج.'
      : 'How many hours the timeline shows from now. Longer windows scroll further and retain more programmes.';
  String guideHoursLabel(int hours) =>
      isArabic ? '$hours ساعة' : hours == 1 ? '1 hour' : '$hours hours';

  String get autoRefresh =>
      isArabic ? 'التحديث التلقائي' : 'Auto refresh';
  String get autoRefreshHelp => isArabic
      ? 'يعيد تحميل قائمة التشغيل والدليل في الخلفية حسب الجدول المحدد.'
      : 'Reloads the playlist and guide in the background on the schedule you choose.';
  String get refreshOff => isArabic ? 'إيقاف' : 'Off';
  String refreshEvery(int minutes) {
    if (minutes < 60) {
      return isArabic ? 'كل $minutes دقيقة' : 'Every $minutes min';
    }
    final hours = minutes ~/ 60;
    return isArabic
        ? 'كل $hours ساعة'
        : hours == 1
            ? 'Every hour'
            : 'Every $hours hours';
  }

  String get startingStream =>
      isArabic ? 'جارٍ بدء البث…' : 'Starting stream…';
  String get streamStartTimeout => isArabic
      ? 'لم يبدأ البث خلال الوقت المتوقع. قد يكون المصدر مشغولًا أو الرابط غير متاح.'
      : 'The stream did not start in time. The source may be busy or the link may be unavailable.';
  String get audioTracks => isArabic ? 'المسارات الصوتية' : 'Audio tracks';
  String get subtitleTracks =>
      isArabic ? 'الترجمة والوسوم' : 'Subtitles';
  String get subtitlesOff => isArabic ? 'إيقاف الترجمة' : 'Subtitles off';
  String get tracks => isArabic ? 'المسارات' : 'Tracks';
  String get autoTrack => isArabic ? 'تلقائي' : 'Auto';
  String get noTrack => isArabic ? 'بدون' : 'None';
  String trackNumber(int number) =>
      isArabic ? 'مسار $number' : 'Track $number';

  String get channelBanner => isArabic ? 'شريط القناة' : 'Channel banner';
  String get channelBannerHelp => isArabic
      ? 'يعرض اسم القناة وما يُعرض الآن وما يليه لثوانٍ عند فتح أي قناة.'
      : 'Shows the channel name, what is on now and what is next for a few seconds whenever a channel opens.';
  String get pinBanner =>
      isArabic ? 'إبقاء الشريط ظاهرًا' : 'Keep the banner on screen';
  String get unpinBanner => isArabic ? 'إخفاء الشريط' : 'Hide the banner';
  String get previousChannel => isArabic ? 'القناة السابقة' : 'Previous channel';
  String get nextChannel => isArabic ? 'القناة التالية' : 'Next channel';
  String get browseChannels => isArabic ? 'استعراض القنوات' : 'Browse channels';
  String get channelBrowserHint => isArabic
      ? 'اكتب اسم القناة أو رقمها'
      : 'Type a channel name or number';
  String get noChannelMatch =>
      isArabic ? 'لا توجد قناة مطابقة.' : 'No channel matches that search.';
  String get tunedTo => isArabic ? 'تم الانتقال إلى' : 'Tuned to';
  String get channelNotFound =>
      isArabic ? 'لا توجد قناة بهذا الرقم' : 'No channel with that number';
  String get enterChannelNumber =>
      isArabic ? 'أدخل رقم القناة' : 'Enter a channel number';
  String get muted => isArabic ? 'مكتوم' : 'Muted';
  String get paused => isArabic ? 'متوقف مؤقتًا' : 'Paused';
  String get playing => isArabic ? 'قيد التشغيل' : 'Playing';
  String get audioTrackChanged => isArabic ? 'المسار الصوتي' : 'Audio track';
  String get subtitleChanged => isArabic ? 'الترجمة' : 'Subtitles';
  String get onlyOneAudio => isArabic
      ? 'لهذا البث مسار صوتي واحد فقط.'
      : 'This stream has only one audio track.';
  String get noSubtitleTracks => isArabic
      ? 'لا توجد مسارات ترجمة في هذا البث.'
      : 'This stream has no subtitle tracks.';
  String get trackMemoryHelp => isArabic
      ? 'يتذكّر Mojac اختيارك للمسارات لكل قناة.'
      : 'Mojac remembers your track choice for each channel.';
  String get restoreTrackDefaults => isArabic
      ? 'استخدام المسارات الافتراضية'
      : 'Use the default tracks';
  String get trackDefaultsRestored => isArabic
      ? 'تمت استعادة المسارات الافتراضية.'
      : 'Default tracks restored.';

  String get sleepTimer => isArabic ? 'مؤقّت النوم' : 'Sleep timer';
  String get sleepOff => isArabic ? 'إيقاف' : 'Off';
  String get sleepEndOfProgramme =>
      isArabic ? 'نهاية هذا البرنامج' : 'End of this programme';
  String get sleepTimerFinished =>
      isArabic ? 'انتهى مؤقّت النوم.' : 'Sleep timer finished.';
  String sleepTimerSet(int minutes) => isArabic
      ? 'سيتوقف التشغيل بعد $minutes دقيقة'
      : 'Sleeping in $minutes min';
  String sleepIn(int minutes) =>
      isArabic ? 'النوم بعد $minutes د' : 'Sleep in ${minutes}m';

  String get picture => isArabic ? 'الصورة' : 'Picture';
  String get aspectRatio =>
      isArabic ? 'نسبة العرض إلى الارتفاع' : 'Aspect ratio';
  String get aspectAuto => isArabic ? 'تلقائي (الأصل)' : 'Auto (native)';
  String get aspectFill => isArabic ? 'ملء الشاشة' : 'Fill screen';
  String get aspectStretch => isArabic ? 'تمديد' : 'Stretch';
  String get aspectHelp => isArabic
      ? '«تلقائي» يعيد نسبة البث الأصلية، و«ملء الشاشة» يقتص الحواف بلا تشويه، و«تمديد» يملأ النافذة حتى لو تغيّرت النسبة. تبقى الخيارات الأخرى مفعّلة حتى تختار تلقائي مجددًا.'
      : 'Auto restores the stream\'s own ratio, Fill crops the edges without distorting, and Stretch fills the window even if that changes the ratio. The others stay until you pick Auto again.';
  String get deinterlace => isArabic ? 'إزالة التشابك' : 'Deinterlace';
  String get deinterlaceAuto => isArabic ? 'تلقائي' : 'Auto';
  String get deinterlaceOn => isArabic ? 'تشغيل' : 'On';
  String get deinterlaceOff => isArabic ? 'إيقاف' : 'Off';
  String get audioDelay => isArabic ? 'تأخير الصوت' : 'Audio delay';
  String get subtitleDelay => isArabic ? 'تأخير الترجمة' : 'Subtitle delay';
  String get resetPicture => isArabic ? 'إعادة ضبط الصورة' : 'Reset picture';
  String get pictureReset => isArabic
      ? 'تمت إعادة ضبط إعدادات الصورة.'
      : 'Picture settings reset.';

  String get playbackInfo => isArabic ? 'معلومات التشغيل' : 'Playback info';
  String get statistics => isArabic ? 'الإحصاءات' : 'Statistics';
  String get showStatistics => isArabic
      ? 'عرض إحصاءات التشغيل'
      : 'Show playback statistics';
  String get hideStatistics => isArabic
      ? 'إخفاء إحصاءات التشغيل'
      : 'Hide playback statistics';
  String get streamUrl => isArabic ? 'رابط البث' : 'Stream URL';
  String get redactedUrlNote => isArabic
      ? 'أُخفيت بيانات الدخول ومعاملات الرابط.'
      : 'Credentials and query strings are hidden.';
  String get copyDetails => isArabic ? 'نسخ التفاصيل' : 'Copy details';
  String get detailsCopied => isArabic ? 'نُسخت التفاصيل.' : 'Details copied.';
  String get engine => isArabic ? 'المحرّك' : 'Engine';
  String get builtInEngine => isArabic
      ? 'المشغّل المدمج (media_kit / libmpv)'
      : 'Built-in player (media_kit / libmpv)';
  String get resolution => isArabic ? 'الدقة' : 'Resolution';
  String get videoCodec => isArabic ? 'ترميز الفيديو' : 'Video codec';
  String get audioCodec => isArabic ? 'ترميز الصوت' : 'Audio codec';
  String get frameRate => isArabic ? 'معدل الإطارات' : 'Frame rate';
  String get bufferLevel => isArabic ? 'المخزن المؤقت' : 'Buffer';
  String get droppedFrames => isArabic ? 'الإطارات المفقودة' : 'Dropped frames';
  String get hardwareDecoder =>
      isArabic ? 'فك الترميز العتادي' : 'Hardware decoder';
  String get bitrate => isArabic ? 'معدل البت' : 'Bitrate';
  String get position => isArabic ? 'الموضع' : 'Position';
  String get waitingForData => isArabic ? 'بانتظار البيانات' : 'Waiting for data';

  String get keyboardShortcuts =>
      isArabic ? 'اختصارات لوحة المفاتيح' : 'Keyboard shortcuts';
  String get shortcutsIntro => isArabic
      ? 'تعمل مع لوحة مفاتيح أو جهاز تحكم.'
      : 'These work with a hardware keyboard or a TV remote.';
  String get shortcutPlayPause =>
      isArabic ? 'تشغيل أو إيقاف مؤقت' : 'Play or pause';
  String get shortcutFullscreen => isArabic ? 'ملء الشاشة' : 'Full screen';
  String get shortcutMute => isArabic ? 'كتم الصوت' : 'Mute';
  String get shortcutVolume =>
      isArabic ? 'رفع أو خفض الصوت' : 'Volume up or down';
  String get shortcutChannels =>
      isArabic ? 'القناة السابقة أو التالية' : 'Previous or next channel';
  String get shortcutBrowser => isArabic ? 'مستعرض القنوات' : 'Channel browser';
  String get shortcutTracks =>
      isArabic ? 'المسارات الصوتية والترجمة' : 'Audio and subtitle tracks';
  String get shortcutAudio =>
      isArabic ? 'تبديل المسار الصوتي' : 'Cycle the audio track';
  String get shortcutSubtitles => isArabic ? 'تبديل الترجمة' : 'Cycle subtitles';
  String get shortcutPicture =>
      isArabic ? 'إعدادات الصورة' : 'Picture settings';
  String get shortcutAspect =>
      isArabic ? 'تبديل نسبة العرض' : 'Cycle the aspect ratio';
  String get shortcutDeinterlace =>
      isArabic ? 'تبديل إزالة التشابك' : 'Cycle deinterlace';
  String get shortcutBanner =>
      isArabic ? 'إظهار أو إخفاء الشريط' : 'Show or hide the banner';
  String get shortcutSleep => isArabic ? 'مؤقّت النوم' : 'Sleep timer';
  String get shortcutStatistics =>
      isArabic ? 'إحصاءات التشغيل' : 'Playback statistics';
  String get shortcutInfo =>
      isArabic ? 'معلومات التشغيل' : 'Playback info';
  String get shortcutNumbers =>
      isArabic ? 'إدخال رقم قناة' : 'Enter a channel number';
  String get shortcutEscape => isArabic
      ? 'إغلاق أو الخروج من ملء الشاشة أو الرجوع'
      : 'Close, leave full screen or go back';
  String get shortcutHelp =>
      isArabic ? 'قائمة الاختصارات' : 'This shortcut list';

  String get defaultAudioLanguage =>
      isArabic ? 'لغة الصوت الافتراضية' : 'Default audio language';
  String get defaultSubtitles =>
      isArabic ? 'الترجمة الافتراضية' : 'Default subtitles';
  String get defaultAudioHelp => isArabic
      ? 'يُختار المسار المطابق عند فتح القناة، ويُحفظ اختيارك لكل قناة.'
      : 'The matching track is chosen when a channel opens, and your pick is remembered per channel.';
  String get defaultSubtitlesHelp => isArabic
      ? 'اختر «إيقاف الترجمة» لبدء كل قناة دون ترجمة، أو تلقائي لترك القرار للمشغّل.'
      : 'Choose Subtitles off to start every channel without them, or Automatic to leave it to the player.';
  String get playerSettingsHelp => isArabic
      ? 'تُطبَّق هذه الإعدادات على المشغّل المدمج في Android وعندما لا يُستخدم mpv النظامي.'
      : 'These apply to the built-in player on Android and wherever the system mpv is not used.';
  String get automatic => isArabic ? 'تلقائي' : 'Automatic';

  String languageName(String code) {
    switch (code) {
      case 'auto':
        return automatic;
      case 'off':
        return subtitlesOff;
      case 'en':
        return isArabic ? 'الإنجليزية' : 'English';
      case 'ar':
        return isArabic ? 'العربية' : 'Arabic';
      case 'fr':
        return isArabic ? 'الفرنسية' : 'French';
      case 'es':
        return isArabic ? 'الإسبانية' : 'Spanish';
      case 'de':
        return isArabic ? 'الألمانية' : 'German';
      case 'it':
        return isArabic ? 'الإيطالية' : 'Italian';
      case 'pt':
        return isArabic ? 'البرتغالية' : 'Portuguese';
      case 'ru':
        return isArabic ? 'الروسية' : 'Russian';
      case 'tr':
        return isArabic ? 'التركية' : 'Turkish';
      case 'fa':
        return isArabic ? 'الفارسية' : 'Persian';
      case 'ur':
        return isArabic ? 'الأردية' : 'Urdu';
      case 'hi':
        return isArabic ? 'الهندية' : 'Hindi';
      case 'bn':
        return isArabic ? 'البنغالية' : 'Bengali';
      case 'id':
        return isArabic ? 'الإندونيسية' : 'Indonesian';
      case 'ms':
        return isArabic ? 'الملايو' : 'Malay';
      case 'zh':
        return isArabic ? 'الصينية' : 'Chinese';
      case 'ja':
        return isArabic ? 'اليابانية' : 'Japanese';
      case 'ko':
        return isArabic ? 'الكورية' : 'Korean';
      default:
        return code;
    }
  }

  String get zoomIn => isArabic ? 'تكبير' : 'Zoom in';
  String get zoomOut => isArabic ? 'تصغير' : 'Zoom out';
  String get zoomHint => isArabic
      ? 'Ctrl + عجلة الفأرة للتكبير أو التصغير'
      : 'Ctrl + scroll wheel to zoom';
  String get guideFilterGroup =>
      isArabic ? 'تصفية حسب المجموعة' : 'Filter by group';
  String minutesLeft(int minutes) {
    final value = minutes < 1 ? 1 : minutes;
    return isArabic ? 'بقيت $value دقيقة' : '$value min left';
  }


  String get programmeDetails => isArabic ? 'تفاصيل البرنامج' : 'Programme details';
  String get noDescription =>
      isArabic ? 'لا يوجد وصف لهذا البرنامج.' : 'No description for this programme.';
  String get categories => isArabic ? 'التصنيفات' : 'Categories';
  String get newEpisode => isArabic ? 'حلقة جديدة' : 'New episode';
  String get previouslyShown => isArabic ? 'أُعيد عرضه' : 'Previously shown';
  String get credits => isArabic ? 'فريق العمل' : 'Credits';
  String get directedBy => isArabic ? 'إخراج' : 'Directed by';
  String get writtenBy => isArabic ? 'كتابة' : 'Written by';
  String get producedBy => isArabic ? 'إنتاج' : 'Produced by';
  String get musicBy => isArabic ? 'موسيقى' : 'Music by';
  String get presentedBy => isArabic ? 'تقديم' : 'Presented by';
  String get starring => isArabic ? 'بطولة' : 'Starring';
  String get guests => isArabic ? 'ضيوف' : 'Guests';
  String get keywords => isArabic ? 'كلمات مفتاحية' : 'Keywords';
  String get ratedLabel => isArabic ? 'التصنيف العمري' : 'Rated';
  String yearLabel(int year) => isArabic ? 'سنة $year' : '$year';
  String get watchChannel => isArabic ? 'مشاهدة القناة' : 'Watch channel';
  String get startsAt => isArabic ? 'يبدأ' : 'Starts';
  String get endsAt => isArabic ? 'ينتهي' : 'Ends';

  String get errorTitle => isArabic ? 'حدث خطأ' : 'Something went wrong';
  String get settingsSaved => isArabic ? 'تم حفظ الإعدادات.' : 'Settings saved.';
  String get noActiveSource =>
      isArabic ? 'لا يوجد مصدر نشط' : 'No active source';
  String get openSettings => isArabic ? 'فتح الإعدادات' : 'Open settings';

  String get errorGeneric => isArabic
      ? 'تعذّر إكمال العملية. حاول مرة أخرى.'
      : 'The operation could not be completed. Try again.';

  String relativeTime(DateTime time, DateTime now) {
    final difference = now.difference(time);
    if (difference.inSeconds < 60) {
      return isArabic ? 'قبل لحظات' : 'moments ago';
    }
    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return isArabic ? 'قبل $minutes دقيقة' : '${minutes}m ago';
    }
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return isArabic ? 'قبل $hours ساعة' : '${hours}h ago';
    }
    final days = difference.inDays;
    return isArabic ? 'قبل $days يوم' : '${days}d ago';
  }

  String formatTime(DateTime value, {required bool use24HourTime}) {
    final hour = value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    if (use24HourTime) {
      return '${hour.toString().padLeft(2, '0')}:$minute';
    }
    final display = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour < 12
        ? (isArabic ? 'ص' : 'AM')
        : (isArabic ? 'م' : 'PM');
    return '$display:$minute $suffix';
  }

  String formatHour(DateTime value, {required bool use24HourTime}) {
    final hour = value.hour;
    final minute = value.minute;
    if (use24HourTime) {
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }
    final display = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = minute == 0
        ? (hour < 12 ? (isArabic ? 'ص' : 'AM') : (isArabic ? 'م' : 'PM'))
        : '';
    final minutes = minute == 0 ? '' : ':${minute.toString().padLeft(2, '0')}';
    return suffix.isEmpty ? '$display$minutes' : '$display$minutes $suffix';
  }

  String formatRange(
    DateTime start,
    DateTime stop, {
    required bool use24HourTime,
  }) {
    return '${formatTime(start, use24HourTime: use24HourTime)} – '
        '${formatTime(stop, use24HourTime: use24HourTime)}';
  }

  String formatDateTime(DateTime value, {required bool use24HourTime}) {
    return '${formatDate(value)} · '
        '${formatTime(value, use24HourTime: use24HourTime)}';
  }

  String formatDate(DateTime value) {
    final weekdays = isArabic
        ? const <String>[
            'الاثنين',
            'الثلاثاء',
            'الأربعاء',
            'الخميس',
            'الجمعة',
            'السبت',
            'الأحد',
          ]
        : const <String>[
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
            'Sunday',
          ];
    final months = isArabic
        ? const <String>[
            'يناير',
            'فبراير',
            'مارس',
            'أبريل',
            'مايو',
            'يونيو',
            'يوليو',
            'أغسطس',
            'سبتمبر',
            'أكتوبر',
            'نوفمبر',
            'ديسمبر',
          ]
        : const <String>[
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];
    final weekday = weekdays[(value.weekday - 1) % 7];
    final month = months[(value.month - 1) % 12];
    return isArabic
        ? '$weekday، ${value.day} $month'
        : '$weekday, $month ${value.day}';
  }

  String formatDayNumber(DateTime value) => value.day.toString();
}

class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppStrings.supportedLocales
        .any((supported) => supported.languageCode == locale.languageCode);
  }

  @override
  Future<AppStrings> load(Locale locale) {
    return SynchronousFuture<AppStrings>(AppStrings(locale));
  }

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
