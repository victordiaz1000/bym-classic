import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_source.dart';
import 'app_version.dart';

export 'app_update_source.dart'
    show AppUpdateRelease, AppUpdateStatus, UpdateChannel;
export 'app_version.dart' show AppVersion;

/// Ce que la vérification silencieuse a trouvé, tous canaux confondus.
///
/// [best] est la release la plus récente ; [releases] les porte toutes, dans
/// l'ordre de préférence des canaux — c'est ce que Réglages affiche quand
/// plusieurs offres existent (« Télécharger depuis GitHub » / « Ouvrir le Play
/// Store »). Une seule source configurée aujourd'hui, mais l'écran ne suppose
/// jamais qu'il y en a une.
@immutable
class AppUpdateReport {
  final AppUpdateStatus status;

  /// Releases proposables, la plus récente en tête. Vide si [status] n'est pas
  /// [AppUpdateStatus.available].
  final List<AppUpdateRelease> releases;

  const AppUpdateReport(this.status, [this.releases = const []]);

  bool get hasUpdate => status == AppUpdateStatus.available;

  AppUpdateRelease? get best => releases.isEmpty ? null : releases.first;

  /// La réponse dit quelque chose de sûr, donc elle vaut la peine d'être
  /// horodatée : un échec réseau ne doit pas repousser la prochaine tentative
  /// de 24 h, sinon une coupure au démarrage condamne l'application à
  /// l'aveugle jusqu'au lendemain.
  bool get definitive =>
      status == AppUpdateStatus.upToDate ||
      status == AppUpdateStatus.available;
}

/// Demande à chaque canal configuré s'il existe une version plus récente.
///
/// Aucun état ici : la vérification est sans mémoire, comme celle du texte. La
/// cadence (une fois par jour) appartient à [AppUpdateChecker], qui la tient dans
/// les préférences.
class AppUpdateService {
  AppUpdateService({
    List<AppUpdateSource>? sources,
    AppVersion? installed,
  })  : _sources = sources ??
            <AppUpdateSource>[GithubUpdateSource(), PlayStoreUpdateSource()],
        _installed = installed;

  /// Canaux interrogés. Par défaut GitHub puis le Play Store — les deux qui
  /// savent servir Android ; l'App Store n'a rien à dire à un téléphone Android
  /// et réciproquement.
  final List<AppUpdateSource> _sources;

  /// Version installée quand l'appelant la connaît (tests). Sinon lue de
  /// `package_info_plus`, donc du manifeste réellement installé.
  // ignore: prefer_initializing_formals
  final AppVersion? _installed;

  /// Version de l'application sur cet appareil.
  ///
  /// `PackageInfo` la donne telle que Flutter l'a écrite dans le manifeste :
  /// `1.0.1` et `14`. La lecture est mise en cache par le paquet lui-même.
  Future<AppVersion?> installedVersion() async {
    if (_installed != null) return _installed;
    try {
      final info = await PackageInfo.fromPlatform();
      return AppVersion.tryParse('${info.version}+${info.buildNumber}');
    } catch (_) {
      // Un build sans version lisible ne doit pas empêcher l'application de
      // démarrer : on ne proposera simplement jamais de mise à jour.
      return null;
    }
  }

  /// Interroge tous les canaux qui servent cette plateforme.
  ///
  /// Un canal qui échoue ne fait pas échouer la vérification : s'il en reste un
  /// qui répond, sa réponse est la vérité. Tous en échec → l'erreur la plus
  /// parlante (réseau d'abord, puis serveur). Aucun canal configuré →
  /// [AppUpdateStatus.notConfigured].
  Future<AppUpdateReport> check() async {
    final installed = await installedVersion();
    if (installed == null) {
      return const AppUpdateReport(AppUpdateStatus.notConfigured);
    }

    final sources =
        _sources.where((s) => s.supportsPlatform).toList(growable: false);
    if (sources.isEmpty) {
      return const AppUpdateReport(AppUpdateStatus.notConfigured);
    }

    final results = await Future.wait(
      sources.map((source) async {
        try {
          return await source.latest(installed);
        } catch (_) {
          return const AppUpdateResult(AppUpdateStatus.invalidPayload);
        }
      }),
    );

    final releases = <AppUpdateRelease>[
      for (final result in results)
        if (result.hasUpdate) result.release!,
    ]..sort((a, b) => b.version.compareTo(a.version));

    if (releases.isNotEmpty) {
      return AppUpdateReport(AppUpdateStatus.available, releases);
    }

    // Aucun canal n'a de version à proposer. « À jour » l'emporte sur un échec
    // réseau — un canal qui a répondu compte plus qu'un canal muet — et un échec
    // transitoire l'emporte sur « non configuré », parce qu'il dit à
    // l'utilisateur de réessayer plutôt que de lui annoncer une absence de
    // canal qui n'existe pas.
    AppUpdateStatus? transient;
    var sawUpToDate = false;
    for (final result in results) {
      if (result.status == AppUpdateStatus.upToDate) sawUpToDate = true;
      if (result.status.transient) transient ??= result.status;
    }
    return AppUpdateReport(
      sawUpToDate ? AppUpdateStatus.upToDate : (transient ?? AppUpdateStatus.notConfigured),
    );
  }

  void close() {
    for (final source in _sources) {
      if (source is GithubUpdateSource) source.close();
    }
  }
}

/// Vérification silencieuse au démarrage, et source de vérité unique pour les
/// trois surfaces qui l'affichent.
///
/// Même forme que [BymUpdateChecker] : un [ValueNotifier] statique, une cadence
/// tenue dans les préférences, et l'assurance que rien n'est jamais levé — un
/// appareil hors ligne doit démarrer exactement comme un appareil à jour.
class AppUpdateChecker {
  /// Mise à jour repérée et non encore installée, null sinon.
  static final ValueNotifier<AppUpdateRelease?> available =
      ValueNotifier<AppUpdateRelease?>(null);

  /// Clé de préférence de la dernière vérification réussie.
  static const String lastCheckKey = 'app.update.lastCheck';

  /// Au plus une vérification par jour et par appareil. Le quota GitHub non
  /// authentifié (60 requêtes/heure et par IP) n'est jamais approché.
  static const Duration checkInterval = Duration(hours: 24);

  static bool _running = false;

  /// Point d'injection des tests, comme `BymUpdateChecker.debugServiceFactory`.
  @visibleForTesting
  static Future<AppUpdateReport> Function()? debugCheck;

  /// Lit la dernière vérification depuis les préférences, via le hook d'écriture
  /// injectable des tests.
  @visibleForTesting
  static Future<DateTime?> Function()? debugLastCheck;
  @visibleForTesting
  static Future<void> Function(DateTime when)? debugMarkChecked;

  /// Vérifie au plus une fois par [checkInterval]. Ne lève jamais, n'attend
  /// rien, ne télécharge rien.
  static Future<void> maybeCheck({bool force = false}) async {
    if (_running) return;
    _running = true;
    try {
      if (!force) {
        final last = await (debugLastCheck?.call() ?? _readLastCheck());
        if (last != null &&
            DateTime.now().difference(last) < checkInterval) {
          return;
        }
      }
      final report = debugCheck != null
          ? await debugCheck!()
          : await _checkAndClose();
      if (report.definitive) {
        await (debugMarkChecked?.call(DateTime.now()) ?? _writeLastCheck());
      }
      available.value = report.hasUpdate ? report.best : null;
    } catch (_) {
      // Une vérification ratée ne doit rien coûter au démarrage.
    } finally {
      _running = false;
    }
  }

  static Future<AppUpdateReport> _checkAndClose() async {
    final service = AppUpdateService();
    try {
      return await service.check();
    } finally {
      service.close();
    }
  }

  /// À appeler après une installation ou quand le lecteur choisit d'ignorer.
  static void clear() => available.value = null;

  /// Date de la dernière vérification **réussie**, pour l'afficher dans
  /// Réglages. « À jour » déconnecté du moment où on l'a vérifié ne veut rien
  /// dire : le lecteur doit pouvoir dater l'information qu'on lui donne.
  static Future<DateTime?> lastCheck() =>
      debugLastCheck?.call() ?? _readLastCheck();

  static Future<DateTime?> _readLastCheck() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(lastCheckKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeLastCheck() async {
    try {
      final prefs = await _prefs;
      await prefs.setString(lastCheckKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Sans horodatage, la prochaine vérification aura lieu tout de suite :
      // dégradation acceptable, jamais un blocage.
    }
  }

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();
}
