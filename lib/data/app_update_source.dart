import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_version.dart';

/// Par où un utilisateur peut obtenir une version plus récente de l'application.
///
/// L'ordre de déclaration est l'ordre de préférence à l'écran : GitHub d'abord
/// parce que c'est le seul canal réellement ouvert aujourd'hui, les stores
/// ensuite quand ils existeront. Chaque canal est une [AppUpdateSource] ; le
/// service n'en connaît aucun par son nom.
enum UpdateChannel {
  github,
  playStore,
  appStore;

  /// Nom du canal tel qu'il s'affiche.
  String get label => switch (this) {
        UpdateChannel.github => 'GitHub Releases',
        UpdateChannel.playStore => 'Google Play',
        UpdateChannel.appStore => 'App Store',
      };

  /// Verbe du bouton, le canal n'installant pas de la même façon : un APK se
  /// télécharge dans l'application, un store s'ouvre.
  String get action => this == UpdateChannel.github ? 'Télécharger' : 'Ouvrir';
}

/// Comment une vérification s'est terminée, avant de décider quoi en faire.
///
/// Le même vocabulaire que [BymUpdateStatus] — une vérification silencieuse qui
/// échoue ne doit jamais produire autre chose qu'une ligne discrète dans
/// Réglages, jamais une exception ni un dialogue au démarrage.
enum AppUpdateStatus {
  /// La version installée est la plus récente connue.
  upToDate,

  /// Une version plus récente attend l'accord de l'utilisateur.
  available,

  /// Le canal n'est pas encore ouvert : pas d'identifiant Play Store, pas
  /// d'App Store, ou une plateforme que ce canal ne sert pas.
  notConfigured,

  /// La requête n'a pas quitté l'appareil (hors ligne, DNS, mode avion).
  noConnection,

  /// Le serveur a répondu mais a refusé : 403, 429, 5xx ou délai dépassé.
  serverError,

  /// Un 200 est arrivé mais le contenu n'est pas exploitable.
  invalidPayload;

  /// Transitoire : une relance automatique aurait un sens.
  bool get transient => this == noConnection || this == serverError;

  String get message => switch (this) {
        AppUpdateStatus.upToDate => 'L’application est à jour.',
        AppUpdateStatus.available =>
          'Une nouvelle version de l’application est disponible.',
        AppUpdateStatus.notConfigured =>
          'Aucun canal de mise à jour n’est encore ouvert pour cette '
              'plateforme.',
        AppUpdateStatus.noConnection =>
          'Vérification impossible — aucune connexion internet.',
        AppUpdateStatus.serverError =>
          'Vérification impossible — le serveur est momentanément '
              'indisponible.',
        AppUpdateStatus.invalidPayload =>
          'Vérification impossible — la réponse reçue n’est pas exploitable.',
      };
}

/// Une version publiée sur un canal, réduite à ce qu'il faut pour la proposer.
@immutable
class AppUpdateRelease {
  final UpdateChannel channel;

  /// Version telle que la source l'annonce, sans préfixe de tag.
  final AppVersion version;

  /// Texte de la publication (notes de version), éventuellement vide.
  final String notes;
  final DateTime? publishedAt;

  /// L'APK à télécharger (GitHub) ou la page du store à ouvrir.
  final Uri downloadUrl;

  /// Empreinte SHA-256 annoncée, null quand la source n'en publie pas.
  ///
  /// GitHub n'a pas de champ pour cela : c'est un fichier `.sha256` déposé à
  /// côté de l'APK par le workflow de release. Il n'est lu qu'au moment du
  /// téléchargement, jamais pendant la vérification silencieuse.
  final Uri? checksumUrl;

  /// Taille de l'APK, pour la barre de progression.
  final int? sizeBytes;

  const AppUpdateRelease({
    required this.channel,
    required this.version,
    required this.downloadUrl,
    this.notes = '',
    this.publishedAt,
    this.checksumUrl,
    this.sizeBytes,
  });
}

/// Résultat d'une vérification sur un canal.
@immutable
class AppUpdateResult {
  final AppUpdateStatus status;

  /// Renseigné uniquement quand [status] vaut [AppUpdateStatus.available].
  final AppUpdateRelease? release;

  const AppUpdateResult(this.status, [this.release]);

  const AppUpdateResult.upToDate() : this(AppUpdateStatus.upToDate);
  const AppUpdateResult.notConfigured() : this(AppUpdateStatus.notConfigured);

  bool get hasUpdate => status == AppUpdateStatus.available && release != null;
}

/// Un moyen de savoir si l'application est à jour.
///
/// Les trois implémentations — [GithubUpdateSource] aujourd'hui, Play Store et
/// App Store demain — ne partagent que ce contrat. [AppUpdateService] interroge
/// celles qui servent la plateforme courante et garde la plus récente ; ajouter
/// un store ne demande donc ni de toucher au service, ni aux écrans.
abstract class AppUpdateSource {
  UpdateChannel get channel;

  /// Ce canal sert-il cette plateforme ? GitHub sur Android et sur le poste de
  /// développement ; les stores seulement sur leur système.
  bool get supportsPlatform;

  /// Version la plus récente publiée sur ce canal, si elle dépasse [installed].
  ///
  /// Rend un [AppUpdateResult] plutôt qu'une version nue : « rien de neuf » et
  /// « je n'ai pas pu demander » ne se racontent pas de la même façon, et un
  /// service qui les confondrait annoncerait « à jour » à un appareil hors
  /// ligne.
  Future<AppUpdateResult> latest(AppVersion installed);
}

/// Dépôt des releases, public et sans authentification.
///
/// La même adresse que celle du site (`docs/script.js`), donc une seule source
/// de vérité sur ce qui a été publié.
const String githubRepoApi =
    'https://api.github.com/repos/victordiaz1000/bym-classic';

/// Le canal GitHub : la dernière release, hors brouillons et préversions.
///
/// Une seule requête par vérification (la réponse porte les assets et leurs
/// tailles). Le quota non authentifié de GitHub est de 60 requêtes par heure et
/// par IP ; une vérification par jour et par appareil le tient trente fois.
class GithubUpdateSource implements AppUpdateSource {
  GithubUpdateSource({http.Client? client, this.requestTimeout = _timeout})
      : _injectedClient = client;

  static const Duration _timeout = Duration(seconds: 20);

  final Duration requestTimeout;
  final http.Client? _injectedClient;
  http.Client? _ownedClient;

  http.Client get _client =>
      _injectedClient ?? (_ownedClient ??= http.Client());

  void close() {
    _ownedClient?.close();
    _ownedClient = null;
  }

  @override
  UpdateChannel get channel => UpdateChannel.github;

  /// La release GitHub sert Android. Sur iOS, installer un APK n'a aucun sens :
  /// le canal reste déclaré pour la vérification de version, mais son action
  /// ouvre la page de release plutôt que d'installer — voir [canInstall].
  @override
  bool get supportsPlatform => true;

  /// Vrai quand ce canal peut réellement remplacer l'application sur place.
  /// Faux sur iOS : on y propose de visiter la release, pas d'installer.
  bool get canInstall => !kIsWeb && Platform.isAndroid;

  static final RegExp _tagPattern = RegExp(r'^v?(\d+\.\d+\.\d+)$');

  @override
  Future<AppUpdateResult> latest(AppVersion installed) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$githubRepoApi/releases/latest'),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(requestTimeout);
    } on TimeoutException {
      return const AppUpdateResult(AppUpdateStatus.serverError);
    } on SocketException {
      return const AppUpdateResult(AppUpdateStatus.noConnection);
    } on http.ClientException {
      return const AppUpdateResult(AppUpdateStatus.noConnection);
    } catch (_) {
      return const AppUpdateResult(AppUpdateStatus.invalidPayload);
    }

    if (response.statusCode != 200) {
      // 404 = aucune release publiée : ce n'est pas une erreur de serveur, c'est
      // simplement « rien à proposer ». 403/429 = quota, 5xx = panne.
      if (response.statusCode == 404) {
        return const AppUpdateResult(AppUpdateStatus.upToDate);
      }
      if (response.statusCode == 403 ||
          response.statusCode == 429 ||
          response.statusCode >= 500) {
        return const AppUpdateResult(AppUpdateStatus.serverError);
      }
      return const AppUpdateResult(AppUpdateStatus.invalidPayload);
    }

    final release = parseRelease(response.bodyBytes, installed);
    if (release == null) return const AppUpdateResult(AppUpdateStatus.upToDate);
    return AppUpdateResult(AppUpdateStatus.available, release);
  }

  /// Lit la réponse de l'API. Null quand il n'y a rien de plus récent.
  ///
  /// Visible pour les tests, et parce que c'est ici que se joue la seule règle
  /// qui compte : on ne propose que ce qu'on peut installer — un tag lisible,
  /// plus haut que l'installé, et un APK joint.
  @visibleForTesting
  static AppUpdateRelease? parseRelease(
    List<int> body,
    AppVersion installed,
  ) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['draft'] == true || decoded['prerelease'] == true) return null;

    final tag = decoded['tag_name'];
    if (tag is! String) return null;
    final match = _tagPattern.firstMatch(tag.trim());
    if (match == null) return null;
    final version = AppVersion.tryParse(match.group(1)!);
    if (version == null || version <= installed) return null;

    final rawAssets = decoded['assets'];
    if (rawAssets is! List) return null;

    _Asset? apk;
    _Asset? checksum;
    for (final raw in rawAssets) {
      if (raw is! Map) continue;
      final name = raw['name'];
      final url = raw['browser_download_url'];
      if (name is! String || url is! String) continue;
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https') continue;
      final size = raw['size'] is int ? raw['size'] as int : null;
      if (name.endsWith('.apk')) {
        // `bym-1.0.1.apk` d'abord — le nom que le workflow produit ; tout autre
        // `.apk` en secours, pour qu'une release renommée à la main ne rende
        // pas l'application éternellement « à jour ».
        final preferred = 'bym-$version.apk';
        if (apk == null || name == preferred) {
          apk = _Asset(name, uri, size);
        }
      } else if (name.endsWith('.apk.sha256') || name.endsWith('.sha256')) {
        checksum = _Asset(name, uri, size);
      }
    }
    if (apk == null) return null;

    final notes = decoded['body'];
    final rawDate = decoded['published_at'];
    return AppUpdateRelease(
      channel: UpdateChannel.github,
      version: version,
      downloadUrl: apk.url,
      notes: notes is String ? notes.trim() : '',
      publishedAt: rawDate is String ? DateTime.tryParse(rawDate) : null,
      checksumUrl: checksum?.url,
      sizeBytes: apk.size,
    );
  }
}

/// Un asset de la release, nom/URL/taille.
class _Asset {
  final String name;
  final Uri url;
  final int? size;

  const _Asset(this.name, this.url, this.size);
}

/// Google Play — **squelette**, sans identifiant de publication.
///
/// Le jour où l'application y sera publiée, cette classe interroge Play Core
/// (plugin `in_app_update`) et rend la release annoncée ; `AppUpdateService` et
/// les trois surfaces d'annonce fonctionneront alors sans être touchés.
/// Jusque-là elle répond honnêtement [AppUpdateStatus.notConfigured] : aucune
/// URL de store n'est inventée, et rien n'est proposé à quelqu'un qui ne
/// pourrait pas l'installer.
class PlayStoreUpdateSource implements AppUpdateSource {
  /// À renseigner à la publication : `com.bym.bible_app`.
  static const String? packageId = null;

  @override
  UpdateChannel get channel => UpdateChannel.playStore;

  @override
  bool get supportsPlatform => !kIsWeb && Platform.isAndroid;

  @override
  Future<AppUpdateResult> latest(AppVersion installed) async =>
      const AppUpdateResult.notConfigured();
}

/// App Store — **squelette**, sans identifiant de publication.
///
/// À la mise en ligne, l'API publique `itunes.apple.com/lookup?id=…` donne la
/// dernière version et sa page ; ici, rien n'est encore publié, donc rien n'est
/// proposé.
class AppStoreUpdateSource implements AppUpdateSource {
  /// À renseigner à la publication (identifiant numérique de l'app).
  static const String? appId = null;

  @override
  UpdateChannel get channel => UpdateChannel.appStore;

  @override
  bool get supportsPlatform => !kIsWeb && Platform.isIOS;

  @override
  Future<AppUpdateResult> latest(AppVersion installed) async =>
      const AppUpdateResult.notConfigured();
}
