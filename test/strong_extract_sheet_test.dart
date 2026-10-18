import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/widgets/loading_skeleton.dart';
import 'package:bible_app/widgets/strong_extract_sheet.dart';

import 'support/fake_strong_lexicon_bundle.dart';

/// Le lexique réel pèse 8,8 Mo et 14 195 entrées : sa première charge gèle le
/// fil principal. Ce bundle reproduit ce que la feuille doit faire pendant ce
/// temps — il retarde sa réponse et compte ses lectures.
class _SlowStrongLexiconBundle extends FakeStrongLexiconBundle {
  _SlowStrongLexiconBundle([super.entries]);

  int loads = 0;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'assets/lexicon/strong_fr.json') {
      loads++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return super.loadString(key, cache: cache);
  }
}

void main() {
  setUp(() {
    // La feuille peint ses couleurs depuis le thème enregistré.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'le tap ouvre aussitôt la coquille, la définition vient s’y poser',
    (tester) async {
      StrongLexicon.useBundle(_SlowStrongLexiconBundle());
      addTearDown(StrongLexicon.useRootBundle);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showStrongExtractSheet(
                    context,
                    strong: StrongLexicon.instance.lookup('H7225'),
                    onOpenFull: (_) {},
                  ),
                  child: const Text('mot'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('mot'));
      await tester.pump();

      // Le tap n'attend plus : la feuille est déjà montée, sur son squelette.
      // C'est là que l'écran gelait sans rien montrer.
      expect(find.byType(StrongExtractLoadingSkeleton), findsOneWidget);
      expect(find.text('Voir la fiche complète'), findsNothing);

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      // L'entrée est venue se poser sur la coquille : même feuille, plein.
      expect(find.byType(StrongExtractLoadingSkeleton), findsNothing);
      expect(find.text('Voir la fiche complète'), findsOneWidget);
      expect(find.textContaining('Définition test de H7225'), findsWidgets);
    },
  );

  test(
    'deux consultations concurrentes ne chargent le lexique qu’une fois',
    () async {
      final bundle = _SlowStrongLexiconBundle();
      StrongLexicon.useBundle(bundle);
      addTearDown(StrongLexicon.useRootBundle);

      // Le premier tap engage la charge ; un deuxième, pendant ce temps,
      // repartait de zéro — lecture, décodage et rangement deux fois.
      await Future.wait([
        StrongLexicon.instance.lookup('H7225'),
        StrongLexicon.instance.lookup('H0430'),
        StrongLexicon.instance.preload(),
      ]);

      expect(bundle.loads, 1);
      expect(StrongLexicon.instance.isLoaded, isTrue);
    },
  );

  test(
    'un lexique déjà réchauffé répond sans rien recharger',
    () async {
      final bundle = _SlowStrongLexiconBundle();
      StrongLexicon.useBundle(bundle);
      addTearDown(StrongLexicon.useRootBundle);

      await StrongLexicon.instance.preload();
      await StrongLexicon.instance.lookup('H0430');

      expect(bundle.loads, 1);
    },
  );
}
