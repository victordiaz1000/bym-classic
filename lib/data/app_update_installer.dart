import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_update_source.dart';

/// Où en est le téléchargement d'un APK.
@immutable
class AppUpdateProgress {
  /// Octets déjà écrits.
  final int received;

  /// Taille annoncée par la release, null quand la source ne la donne pas —
  /// la barre reste alors indéterminée plutôt que de mentir.
  final int? total;

  const AppUpdateProgress({required this.received, this.total});

  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0);
  }
}

/// Comment la préparation d'une mise à jour s'est terminée.
enum AppUpdateInstallStatus {
  /// L'installeur du système a été ouvert sur l'APK vérifié.
  launched,

  /// Le SHA-256 ne correspond pas à celui annoncé : **rien** n'a été lancé.
  checksumMismatch,

  /// La source n'annonce pas d'empreinte — on refuse plutôt que d'installer
  /// un fichier dont on ne peut rien dire.
  checksumMissing,

  /// L'APK n'a pas pu être écrit, ou l'intent a été refusé par le système
  /// (permission « installer des applications inconnues » retirée, par ex.).
  failed,

  /// Requête d'abandon, ou coupure réseau pendant le transfert.
  noConnection,

  /// [AppUpdateInstaller.cancel] a été appelé.
  cancelled,

  /// Cette plateforme ne sait pas installer un APK (iOS) : la page de release
  /// reste la seule voie tant que l'App Store n'est pas ouvert.
  unsupported;

  bool get ok => this == AppUpdateInstallStatus.launched;

  String get message => switch (this) {
        AppUpdateInstallStatus.launched =>
          'Téléchargement vérifié — l’installeur Android s’ouvre.',
        AppUpdateInstallStatus.checksumMismatch =>
          'Installation refusée — le fichier téléchargé ne correspond pas à '
              'l’empreinte publiée. Rien n’a été installé.',
        AppUpdateInstallStatus.checksumMissing =>
          'Installation refusée — cette publication n’annonce pas d’empreinte, '
              'le fichier ne peut pas être vérifié.',
        AppUpdateInstallStatus.failed =>
          'L’installation n’a pas pu être lancée. Autorisez « installer des '
              'applications inconnues » pour BYM dans les réglages Android.',
        AppUpdateInstallStatus.noConnection =>
          'Téléchargement interrompu — aucune connexion internet.',
        AppUpdateInstallStatus.cancelled =>
          'Téléchargement interrompu. Rien n’a été installé.',
        AppUpdateInstallStatus.unsupported =>
          'Cette mise à jour s’installe sur Android. Sur iPhone, elle arrivera '
              'par l’App Store.',
      };
}

/// Télécharge l'APK d'une release, vérifie son SHA-256, puis confie le fichier
/// à l'installeur Android.
///
/// Trois garanties, dans l'ordre où elles comptent :
///
/// 1. **Rien de non vérifié n'est confié à l'installeur.** Le fichier est écrit
///    sous `.part`, haché au fil de l'eau, et l'empreinte est comparée à celle
///    que la publication annonce *avant* tout intent. Une page d'erreur servie
///    en 200 échoue ici.
/// 2. **Un abandon ne laisse rien.** [cancel] arrête la boucle d'écriture, et
///    le `.part` est supprimé dans tous les cas d'échec.
/// 3. **La vérification ne coûte qu'une requête.** L'empreinte n'est lue qu'au
///    moment du téléchargement, jamais pendant la vérification silencieuse.
///
/// L'APK vit dans le cache de l'application : le système peut le reprendre
/// quand il manque de place, ce qui est sans conséquence — on le retélécharge.
class AppUpdateInstaller {
  AppUpdateInstaller({http.Client? client, Directory? directory})
      : _injectedClient = client,
        _injectedDirectory = directory;

  static const Duration _timeout = Duration(seconds: 30);

  /// Dossier des APK dans le cache. Nommé pour ne jamais être confondu avec les
  /// données que l'application garde.
  static const String directoryName = 'bym_updates';

  final http.Client? _injectedClient;
  final Directory? _injectedDirectory;
  http.Client? _ownedClient;

  http.Client get _client =>
      _injectedClient ?? (_ownedClient ??= http.Client());

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  void close() {
    _ownedClient?.close();
    _ownedClient = null;
  }

  Future<Directory> directory() async {
    if (_injectedDirectory != null) return _injectedDirectory;
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, directoryName));
    await dir.create(recursive: true);
    return dir;
  }

  /// Télécharge, vérifie, ouvre l'installeur.
  Future<AppUpdateInstallStatus> install(
    AppUpdateRelease release, {
    void Function(AppUpdateProgress)? onProgress,
  }) async {
    _cancelled = false;

    // Un APK ne s'installe que sur Android. Sur iOS, rien n'est téléchargé :
    // c'est à l'appelant de proposer la page du store.
    if (kIsWeb || !Platform.isAndroid) {
      return AppUpdateInstallStatus.unsupported;
    }

    final checksumUrl = release.checksumUrl;
    if (checksumUrl == null) return AppUpdateInstallStatus.checksumMissing;
    final expected = await _fetchChecksum(checksumUrl);
    if (expected == null) {
      return _cancelled
          ? AppUpdateInstallStatus.cancelled
          : AppUpdateInstallStatus.checksumMissing;
    }

    final target = File(p.join(
      (await directory()).path,
      'bym-${release.version}.apk',
    ));
    final part = File('${target.path}.part');

    final digest = await _download(
      release.downloadUrl,
      part,
      expectedSize: release.sizeBytes,
      onProgress: onProgress,
    );

    if (digest == null) {
      await _delete(part);
      return _cancelled
          ? AppUpdateInstallStatus.cancelled
          : AppUpdateInstallStatus.noConnection;
    }
    if (digest != expected) {
      await _delete(part);
      return AppUpdateInstallStatus.checksumMismatch;
    }

    try {
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } catch (_) {
      await _delete(part);
      return AppUpdateInstallStatus.failed;
    }

    try {
      final result = await OpenFilex.open(
        target.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type == ResultType.done) {
        return AppUpdateInstallStatus.launched;
      }
      if (kDebugMode) debugPrint('Ouverture APK : ${result.message}');
      return AppUpdateInstallStatus.failed;
    } catch (_) {
      return AppUpdateInstallStatus.failed;
    }
  }

  /// Écrit [url] dans [file] en hachant les octets au fil de l'eau.
  ///
  /// Rend l'empreinte observée, ou null sur échec/coupure. Un fichier existant
  /// est tronqué : une reprise partirait d'un `.part` dont on ne sait pas ce
  /// qu'il contient.
  Future<String?> _download(
    Uri url,
    File file, {
    int? expectedSize,
    void Function(AppUpdateProgress)? onProgress,
  }) async {
    // `startChunkedConversion` rend un sink dans lequel on verse les octets ;
    // c'est notre collecteur, tenu à part, qui reçoit le Digest final.
    final digest = _DigestSink();
    final sink = sha256.startChunkedConversion(digest);
    var received = 0;

    try {
      final request = http.Request('GET', url);
      final response =
          await _client.send(request).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final total = response.contentLength ?? expectedSize;
      final out = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          if (_cancelled) {
            await out.flush();
            return null;
          }
          out.add(chunk);
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(AppUpdateProgress(received: received, total: total));
        }
      } finally {
        await out.flush();
        await out.close();
      }
      sink.close();
      return digest.value?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Lit le fichier `.sha256` et en extrait 64 hexadécimaux.
  ///
  /// Le format de `sha256sum` est « `<hash>  <nom>` » ; on ne retient que le
  /// hash, et on refuse le reste — un fichier qui contiendrait plusieurs lignes
  /// n'a pas de sens ici.
  Future<String?> _fetchChecksum(Uri url) async {
    try {
      final response = await _client.get(url).timeout(_timeout);
      if (_cancelled || response.statusCode != 200) return null;
      final match =
          RegExp(r'\b([0-9a-fA-F]{64})\b').firstMatch(response.body);
      return match?.group(1)?.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Un reste dans le cache ne sera jamais installé : il ne porte pas le nom
      // définitif.
    }
  }
}

/// Collecte l'unique empreinte produite par `startChunkedConversion`.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
