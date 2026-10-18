import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_update_service.dart';
import 'package:bible_app/data/app_update_source.dart';

/// Une release GitHub telle que l'API la rend, réduite aux champs lus.
String releaseJson({
  String tag = 'v1.0.1',
  bool draft = false,
  bool prerelease = false,
  List<Map<String, Object?>>? assets,
  String body = 'Corrections de lecture.',
}) {
  final defaultAssets = <Map<String, Object?>>[
    {
      'name': 'bym-$tag.apk'.replaceFirst('-v', '-'),
      'browser_download_url':
          'https://github.com/victordiaz1000/bym-classic/releases/download/'
              '$tag/bym-${tag.replaceFirst('v', '')}.apk',
      'size': 51200000,
    },
    {
      'name': 'bym-${tag.replaceFirst('v', '')}.apk.sha256',
      'browser_download_url':
          'https://github.com/victordiaz1000/bym-classic/releases/download/'
              '$tag/bym-${tag.replaceFirst('v', '')}.apk.sha256',
      'size': 97,
    },
  ];
  return jsonEncode({
    'tag_name': tag,
    'draft': draft,
    'prerelease': prerelease,
    'body': body,
    'published_at': '2026-10-01T12:00:00Z',
    'assets': assets ?? defaultAssets,
  });
}

AppUpdateRelease? parse(String json, String installed) =>
    GithubUpdateSource.parseRelease(
      utf8.encode(json),
      AppVersion.tryParse(installed)!,
    );

void main() {
  group('AppVersion', () {
    test('lit les deux formes de publication', () {
      expect(AppVersion.tryParse('1.0.1'), const AppVersion(1, 0, 1));
      expect(AppVersion.tryParse('v1.0.1'), const AppVersion(1, 0, 1));
      expect(AppVersion.tryParse('1.0.1+14'), const AppVersion(1, 0, 1, 14));
    });

    test('refuse ce qui n’est pas une version', () {
      for (final raw in ['', 'nightly', 'v1.0-beta', '1.0', '1.0.0.0', 'x1.0.0']) {
        expect(AppVersion.tryParse(raw), isNull, reason: raw);
      }
    });

    test('compare les nombres terme à terme, pas en texte', () {
      expect(const AppVersion(1, 0, 10) > const AppVersion(1, 0, 9), isTrue);
      expect(const AppVersion(1, 10, 0) > const AppVersion(1, 9, 9), isTrue);
      expect(const AppVersion(2, 0, 0) > const AppVersion(1, 99, 99), isTrue);
      expect(const AppVersion(1, 0, 0) > const AppVersion(1, 0, 0), isFalse);
    });

    test('un build plus haut compte, un build absent vaut zéro', () {
      expect(const AppVersion(1, 0, 0, 2) > const AppVersion(1, 0, 0, 1), isTrue);
      expect(const AppVersion(1, 0, 1) > const AppVersion(1, 0, 0, 9), isTrue);
      expect(const AppVersion(1, 0, 0) == const AppVersion(1, 0, 0, 0), isTrue);
    });

    test('toString n’affiche le build que s’il existe', () {
      expect(const AppVersion(1, 0, 1).toString(), '1.0.1');
      expect(const AppVersion(1, 0, 1, 3).toString(), '1.0.1+3');
    });
  });

  group('GithubUpdateSource.parseRelease', () {
    test('une version plus haute est proposée, avec son APK et son empreinte', () {
      final release = parse(releaseJson(tag: 'v1.0.1'), '1.0.0+1');
      expect(release, isNotNull);
      expect(release!.version, const AppVersion(1, 0, 1));
      expect(release.downloadUrl.path, endsWith('bym-1.0.1.apk'));
      expect(release.checksumUrl, isNotNull);
      expect(release.sizeBytes, 51200000);
      expect(release.notes, 'Corrections de lecture.');
    });

    test('la version installée ne se repropose pas', () {
      expect(parse(releaseJson(tag: 'v1.0.0'), '1.0.0+1'), isNull);
    });

    test('un build plus récent que le tag ne se repropose pas', () {
      // Le tag n'a pas de build : il vaut 0, donc « 1.0.1 » ne dépasse pas
      // « 1.0.1+3 » installée.
      expect(parse(releaseJson(tag: 'v1.0.1'), '1.0.1+3'), isNull);
    });

    test('brouillons et préversions sont ignorés', () {
      expect(parse(releaseJson(draft: true), '1.0.0'), isNull);
      expect(parse(releaseJson(prerelease: true), '1.0.0'), isNull);
    });

    test('un tag illisible ne devient pas une version', () {
      for (final tag in ['nightly', 'v2', 'release-1.0.1']) {
        expect(parse(releaseJson(tag: tag), '1.0.0'), isNull, reason: tag);
      }
    });

    test('sans APK joint, rien n’est proposé — on ne peut pas installer', () {
      final json = releaseJson(assets: const []);
      expect(parse(json, '1.0.0'), isNull);
    });

    test('un APK sans empreinte est proposé mais sans checksumUrl', () {
      final json = releaseJson(assets: [
        {
          'name': 'bym-1.0.1.apk',
          'browser_download_url': 'https://example.invalid/bym-1.0.1.apk',
          'size': 1,
        },
      ]);
      final release = parse(json, '1.0.0');
      expect(release, isNotNull);
      expect(release!.checksumUrl, isNull);
    });

    test('une URL non https n’est jamais retenue', () {
      final json = releaseJson(assets: [
        {
          'name': 'bym-1.0.1.apk',
          'browser_download_url': 'http://example.invalid/bym-1.0.1.apk',
          'size': 1,
        },
      ]);
      expect(parse(json, '1.0.0'), isNull);
    });

    test('une réponse qui n’est pas du JSON ne lève pas', () {
      expect(parse('<html>Bad Gateway</html>', '1.0.0'), isNull);
    });
  });

  group('GithubUpdateSource.latest', () {
    test('classe les refus du serveur sans lever', () async {
      final source = GithubUpdateSource(
        client: MockClient((_) async => http.Response('', 403)),
      );
      final result = await source.latest(const AppVersion(1, 0, 0));
      expect(result.status, AppUpdateStatus.serverError);
      source.close();
    });

    test('404 = aucune release, donc « à jour » et non une panne', () async {
      final source = GithubUpdateSource(
        client: MockClient((_) async => http.Response('', 404)),
      );
      final result = await source.latest(const AppVersion(1, 0, 0));
      expect(result.status, AppUpdateStatus.upToDate);
      source.close();
    });

    test('une release lisible devient une mise à jour disponible', () async {
      final source = GithubUpdateSource(
        client: MockClient((_) async => http.Response(releaseJson(), 200)),
      );
      final result = await source.latest(const AppVersion(1, 0, 0, 1));
      expect(result.status, AppUpdateStatus.available);
      expect(result.release!.version, const AppVersion(1, 0, 1));
      source.close();
    });

    test('une coupure réseau est classée noConnection', () async {
      final source = GithubUpdateSource(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final result = await source.latest(const AppVersion(1, 0, 0));
      expect(result.status, AppUpdateStatus.noConnection);
      source.close();
    });
  });

  group('AppUpdateService', () {
    test('garde la release la plus haute parmi les canaux', () async {
      final service = AppUpdateService(
        sources: [
          _FakeSource(UpdateChannel.github, const AppVersion(1, 0, 1)),
          _FakeSource(UpdateChannel.playStore, const AppVersion(1, 0, 3)),
        ],
        installed: const AppVersion(1, 0, 0),
      );
      final report = await service.check();
      expect(report.hasUpdate, isTrue);
      expect(report.best!.version, const AppVersion(1, 0, 3));
      expect(report.releases, hasLength(2));
    });

    test('un canal muet ne masque pas celui qui répond', () async {
      final service = AppUpdateService(
        sources: [
          _FailingSource(UpdateChannel.github),
          _FakeSource(UpdateChannel.playStore, const AppVersion(1, 0, 1)),
        ],
        installed: const AppVersion(1, 0, 0),
      );
      final report = await service.check();
      expect(report.status, AppUpdateStatus.available);
    });

    test('tous muets : l’échec réseau l’emporte sur « non configuré »', () async {
      final service = AppUpdateService(
        sources: [
          _FailingSource(UpdateChannel.github),
          _SkeletonSource(UpdateChannel.playStore),
        ],
        installed: const AppVersion(1, 0, 0),
      );
      final report = await service.check();
      expect(report.status, AppUpdateStatus.serverError);
    });

    test('un canal à jour et l’autre muet : « à jour »', () async {
      final service = AppUpdateService(
        sources: [
          _FakeSource(UpdateChannel.github, null),
          _FailingSource(UpdateChannel.playStore),
        ],
        installed: const AppVersion(1, 0, 0),
      );
      final report = await service.check();
      expect(report.status, AppUpdateStatus.upToDate);
    });
  });

  group('AppUpdateChecker', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppUpdateChecker.available.value = null;
    });

    tearDown(() {
      AppUpdateChecker.debugCheck = null;
      AppUpdateChecker.debugLastCheck = null;
      AppUpdateChecker.debugMarkChecked = null;
      AppUpdateChecker.available.value = null;
    });

    test('une vérification récente empêche la suivante', () async {
      var calls = 0;
      AppUpdateChecker.debugLastCheck =
          () async => DateTime.now().subtract(const Duration(hours: 2));
      AppUpdateChecker.debugCheck = () async {
        calls++;
        return const AppUpdateReport(AppUpdateStatus.upToDate);
      };
      await AppUpdateChecker.maybeCheck();
      expect(calls, 0);
    });

    test('force court-circuite la cadence', () async {
      var calls = 0;
      AppUpdateChecker.debugLastCheck =
          () async => DateTime.now().subtract(const Duration(hours: 2));
      AppUpdateChecker.debugCheck = () async {
        calls++;
        return const AppUpdateReport(AppUpdateStatus.upToDate);
      };
      await AppUpdateChecker.maybeCheck(force: true);
      expect(calls, 1);
    });

    test('au-delà de 24 h, la vérification part et publie son résultat', () async {
      var marked = false;
      AppUpdateChecker.debugLastCheck =
          () async => DateTime.now().subtract(const Duration(days: 2));
      AppUpdateChecker.debugMarkChecked = (_) async => marked = true;
      AppUpdateChecker.debugCheck = () async => AppUpdateReport(
            AppUpdateStatus.available,
            [
              AppUpdateRelease(
                channel: UpdateChannel.github,
                version: const AppVersion(1, 0, 1),
                downloadUrl: Uri.parse('https://example.invalid/bym.apk'),
              ),
            ],
          );
      await AppUpdateChecker.maybeCheck();
      expect(marked, isTrue);
      expect(AppUpdateChecker.available.value?.version,
          const AppVersion(1, 0, 1));
    });

    test('une erreur ne lève pas et ne publie rien', () async {
      AppUpdateChecker.debugCheck = () async => throw StateError('boom');
      await AppUpdateChecker.maybeCheck(force: true);
      expect(AppUpdateChecker.available.value, isNull);
    });

    test('un échec réseau n’est pas horodaté : la tentative suivante repart',
        () async {
      var marked = false;
      AppUpdateChecker.debugMarkChecked = (_) async => marked = true;
      AppUpdateChecker.debugCheck = () async =>
          const AppUpdateReport(AppUpdateStatus.serverError);
      await AppUpdateChecker.maybeCheck(force: true);
      expect(marked, isFalse);
    });
  });
}

class _FakeSource implements AppUpdateSource {
  _FakeSource(this.channel, this.version);

  @override
  final UpdateChannel channel;

  /// Null : ce canal est à jour.
  final AppVersion? version;

  @override
  bool get supportsPlatform => true;

  @override
  Future<AppUpdateResult> latest(AppVersion installed) async => version == null
      ? const AppUpdateResult(AppUpdateStatus.upToDate)
      : AppUpdateResult(
          AppUpdateStatus.available,
          AppUpdateRelease(
            channel: channel,
            version: version!,
            downloadUrl: Uri.parse('https://example.invalid/bym.apk'),
          ),
        );
}

class _FailingSource implements AppUpdateSource {
  _FailingSource(this.channel);

  @override
  final UpdateChannel channel;

  @override
  bool get supportsPlatform => true;

  @override
  Future<AppUpdateResult> latest(AppVersion installed) async =>
      const AppUpdateResult(AppUpdateStatus.serverError);
}

class _SkeletonSource implements AppUpdateSource {
  _SkeletonSource(this.channel);

  @override
  final UpdateChannel channel;

  @override
  bool get supportsPlatform => true;

  @override
  Future<AppUpdateResult> latest(AppVersion installed) async =>
      const AppUpdateResult.notConfigured();
}
