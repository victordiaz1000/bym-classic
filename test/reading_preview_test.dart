import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/widgets/reading_preview.dart';

/// L'aperçu de la carte LECTURE réunit ce que les onze rangées règlent : il
/// suit les préférences en direct, et n'invente rien — l'échantillon est le
/// vrai Ge. 1:1 du texte BYM, et sa note la vraie note du verset.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// L'aperçu est monté comme dans sa carte : une colonne à largeur de
  /// téléphone, dans une page qui défile comme la carte des Réglages.
  Future<AppPreferences> pumpPreview(
    WidgetTester tester, {
    AppPreferences? prefs,
  }) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final p = prefs ?? await AppPreferences.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: ReadingPreview(prefs: p),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return p;
  }

  /// Le corps du verset : le `Text` qui porte l'échantillon.
  Text sampleOf(WidgetTester tester) =>
      tester.widget<Text>(find.text(ReadingPreview.sampleText));

  testWidgets('le vrai verset, sous le thème en vigueur', (tester) async {
    await pumpPreview(tester);

    expect(find.text('APERÇU'), findsOneWidget);
    expect(find.text(ReadingPreview.sampleText), findsOneWidget);
    // Le thème se nomme ici — sa rangée vit dans APPARENCE — avec le texte
    // dont l'échantillon vient.
    expect(find.text('Bois doré · BYM'), findsOneWidget);
    expect(
      find.text('Crimson Pro · 100 % · gauche · marges 14 px · panneau 80 %'),
      findsOneWidget,
      reason: 'la légende nomme ce que le dessin ne dit pas',
    );
  });

  testWidgets('la légende suit les curseurs', (tester) async {
    final prefs = await pumpPreview(tester);

    prefs
      ..readingFont = ReadingFont.garamond
      ..fontSize = 33
      ..textAlign = ReadingTextAlign.center
      ..sidePadding = 22
      ..panelOpacity = .55;
    await pumpPreview(tester, prefs: prefs);

    expect(
      find.text('EB Garamond · 150 % · centré · marges 22 px · panneau 55 %'),
      findsOneWidget,
    );
  });

  testWidgets('le corps grandit avec « Taille du texte »', (tester) async {
    final prefs = await pumpPreview(tester);
    final small = tester.getSize(find.text(ReadingPreview.sampleText)).height;

    prefs.fontSize = 44;
    await pumpPreview(tester, prefs: prefs);

    expect(
      tester.getSize(find.text(ReadingPreview.sampleText)).height,
      greaterThan(small),
      reason: 'l\'échantillon est un aperçu, pas une image fixe',
    );
  });

  testWidgets('le thème et la couleur du texte gagnent l\'échantillon', (
    tester,
  ) async {
    final prefs = await pumpPreview(tester);
    expect(sampleOf(tester).style?.color, themeById('forest').textColor);

    // Le même renversement que dans le lecteur : `withTextColor` recompute ce
    // qui dérive de la couleur du texte, pour qu'un texte clair sur un thème
    // clair reste lisible.
    prefs
      ..themeId = 'azur'
      ..textColorOverride = '${const Color(0xFF102030).toARGB32()}';
    await pumpPreview(tester, prefs: prefs);

    expect(find.text('Azur profond · BYM'), findsOneWidget);
    expect(sampleOf(tester).style?.color, const Color(0xFF102030));
  });

  testWidgets('les notes n\'apparaissent qu\'allumées et que si le texte '
      'en porte', (tester) async {
    final prefs = await pumpPreview(tester);
    expect(find.textContaining('Bereshit'), findsNothing);

    prefs.notesMode = true;
    await pumpPreview(tester, prefs: prefs);
    // La carte de note du lecteur : « 1 · commencement : » puis la note.
    expect(find.textContaining('1 · commencement : '), findsOneWidget);
    expect(find.textContaining('Bereshit bara elohîm'), findsOneWidget);

    // La LSGS ne porte pas de notes : la rangée « Notes » le dit déjà, et
    // l'aperçu n'a rien à montrer — surtout pas un texte inventé.
    prefs.versionCode = VersionRepository.lsgsCode;
    await pumpPreview(tester, prefs: prefs);
    expect(find.textContaining('Bereshit'), findsNothing);
  });
}
