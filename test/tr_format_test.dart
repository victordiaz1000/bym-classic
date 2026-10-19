import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/book_mapping.dart';
import 'package:bible_app/data/download_service.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/models/ati.dart';

/// Matthieu 1:4 telle que `TR-Stephanus-1550/tr_to_json.py` l'écrit —
/// copiée depuis `bym-bibles/tr/40.json`, pas reconstituée : le test
/// verrouille le schéma (grec sans accents + Strong préfixé de `G` + code
/// Robinson déjà décodé) et le pont vers la lecture.
///
/// Les deux tables sont tronquées aux seuls indices que ce verset emploie
/// (`a` ≤ 6, `g` ≤ 4) : le fichier en porte 649 pour `ca` sur ce livre.
const Map<String, dynamic> matthieu1 = {
  'bym_index': 40,
  'standard': 40,
  'book': 'Matthieu',
  'osis_id': 'Matt',
  'cg': ['Nom', 'Nom propre', 'Verbe', 'Article', 'Conjonction'],
  'ca': [
    'Nom· nominatif singulier féminin',
    'Nom· génitif singulier féminin',
    'Nom· génitif singulier masculin',
    'Nom propre',
    'Verbe aoriste actif indicatif· 3ᵉ singulier',
    'Article défini· accusatif singulier masculin',
    'Conjonction',
  ],
  'chapters': [
    {
      'chapter': 1,
      'verses': [
        {
          'verse': 4,
          'words': [
            {'m': 'αραμ', 't': 'aram', 's': 'G689', 'a': 3, 'g': 1},
            {'m': 'δε', 't': 'de', 's': 'G1161', 'a': 6, 'g': 4},
            {'m': 'εγεννησεν', 't': 'egennēsen', 's': 'G1080', 'a': 4, 'g': 2},
            {'m': 'τον', 't': 'ton', 's': 'G3588', 'a': 5, 'g': 3},
            {'m': 'αμιναδαβ', 't': 'aminadab', 's': 'G284', 'a': 3, 'g': 1},
          ],
        },
      ],
    },
  ],
};

void main() {
  group('canon du Textus Receptus', () {
    test('TR est téléchargeable, Nouveau Testament seul, au format ati', () {
      final entry = versionByCode('TR');

      expect(entry, isNotNull);
      expect(entry!.availability, VersionAvailability.downloadable);
      expect(entry.format, VersionFormat.ati);
      expect(entry.fetchable, isTrue);
      // Le Textus Receptus va de Matthieu à l'Apocalypse : miroir exact de
      // `otOnly` sur l'ATI.
      expect(entry.ntOnly, isTrue);
      expect(entry.otOnly, isFalse);
      expect(entry.canonOnly, 'le Nouveau Testament');
      expect(entry.interlinear, isTrue, reason: 'grille de colonnes de mots');
      expect(entry.bookCount, 27);
      expect(entry.containsBook(39), isFalse, reason: 'Malachie inexistant');
      expect(entry.containsBook(40), isTrue, reason: 'Matthieu');
      expect(entry.containsBook(66), isTrue, reason: 'Apocalypse');
      expect(entry.rights, contains('domaine public'));
      // Le drapeau décrit le texte aplati : ce corpus n'a aucune glose, donc
      // aucun code n'y est inséré — les numéros se cliquent dans les colonnes.
      expect(entry.hasStrong, isFalse);
      expect(entry.carriesNotes, isFalse);
      // Le grec, comme le « HE » de la WLC nomme l'hébreu.
      expect(entry.languageCode, 'EL');
      // Le chemin, pas l'hôte — convention de `wlc_format_test`, qui laisse
      // l'essai local rediriger le corpus sans casser le test.
      expect(entry.urlTemplate, contains('/tr/{book}.json'));
    });

    test('le fichier servi suit la numérotation standard', () {
      final entry = versionByCode('TR')!;
      // Matthieu : BYM 40 = standard 40 — le fichier tr/40.json.
      expect(
        DownloadService.bookUri(entry, bymToStandard(40)).toString(),
        endsWith('/tr/40.json'),
      );
      // Jacques : BYM 45 mais standard 59 — les deux ordres divergent juste
      // après les Épîtres, et c'est le standard qui nomme le fichier. Sans
      // ce passage, le téléchargement de Jacques irait chercher un Galates.
      expect(bymToStandard(45), 59);
      expect(
        DownloadService.bookUri(entry, bymToStandard(45)).toString(),
        endsWith('/tr/59.json'),
      );
    });
  });

  group('lecture du Textus Receptus', () {
    test('le grec part par `m`, et le verset n\'a aucune ligne de texte', () {
      final book = bookFromAti(matthieu1, bymIndex: 40);

      final verse = book.chapters.first.verses.first;
      expect(verse.mots, hasLength(5));
      // Aucune glose dans ce corpus : la ligne aplatie est vide, et ce sont
      // les mots que le rendu interlinéaire pose en colonnes. Comparer
      // l'écarte d'elle-même plutôt que d'afficher un verset blanc.
      expect(verse.text, isEmpty);

      final mot = verse.mots!.first;
      expect(mot.modern, 'αραμ');
      expect(mot.strong, 'G689', reason: 'préfixé, comme le NTI');
      expect(mot.greek, isTrue, reason: 'grec : de gauche à droite');
      expect(mot.readableGloss, isNull);
      // Le kit livre son grec **nu** — ni accents ni esprits, son README le
      // veut ainsi. La translittération est ce qui le rend suivi de
      // lecture : `αραμ` seul ne se lit pas « aram ».
      expect(mot.translit, 'aram');
    });

    test('chaque mot porte une translittération, jamais vide', () {
      // Le générateur l'écrit sur les 140 722 mots du corpus.
      final book = AtiBook.fromJson(matthieu1);
      for (final chapitre in book.chapters) {
        for (final verset in chapitre.verses) {
          for (final mot in verset.words) {
            expect(mot.translit, isNotNull, reason: mot.strong);
            expect(mot.translit, isNotEmpty, reason: mot.strong);
          }
        }
      }
    });

    test('les codes Robinson se lisent en français dans la feuille', () {
      final book = AtiBook.fromJson(matthieu1);
      final mots = book.chapters.first.verses.first.words;

      final verbe = mots[2]; // εγεννησεν
      expect(verbe.grammar, 'Verbe');
      expect(verbe.analysis, 'Verbe aoriste actif indicatif· 3ᵉ singulier');
      expect(verbe.translit, 'egennēsen',
          reason: 'le ō du η se lit ici, absent du texte nu');

      final article = mots[3]; // τον
      expect(article.grammar, 'Article');
      expect(article.analysis, 'Article défini· accusatif singulier masculin');

      final nomPropre = mots.first; // αραμ
      expect(nomPropre.grammar, 'Nom propre');
      expect(nomPropre.analysis, 'Nom propre');
    });

    test('aucune analyse n\'est un code brut de Robinson', () {
      // C'est la raison d'être du décodage : `N-NSF` est une clé de table,
      // pas une analyse. Un code brut tel quel ne doit jamais atteindre la
      // feuille — ni comme analyse, ni comme étiquette de cellule.
      final brut = RegExp(r'^[A-Z]+(-[A-Z0-9]+)+$');
      final ca = (matthieu1['ca'] as List).cast<String>();
      final cg = (matthieu1['cg'] as List).cast<String>();

      expect(ca, isNotEmpty);
      for (final analyse in ca) {
        expect(analyse, isNot(contains('/')), reason: analyse);
        expect(analyse, isNot(matches(brut)), reason: 'code brut : $analyse');
      }
      for (final etiquette in cg) {
        expect(etiquette, isNot(matches(brut)), reason: 'code brut : $etiquette');
      }

      // Et chaque mot du verset ressort résolu, jamais null.
      final book = AtiBook.fromJson(matthieu1);
      for (final mot in book.chapters.first.verses.first.words) {
        expect(mot.analysis, isNotNull, reason: mot.strong);
        expect(mot.grammar, isNotNull, reason: mot.strong);
      }
    });
  });
}
