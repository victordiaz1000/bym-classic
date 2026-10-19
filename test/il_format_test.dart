import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/book_mapping.dart';
import 'package:bible_app/data/download_service.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/models/ati.dart';

/// Genèse 1:1 telle que `Bible-Interlineaire/il_to_json.py` l'écrit — copiée
/// depuis `bym-bibles/il/1.json`, pas reconstituée : le test verrouille le
/// schéma (hébreu pointillé + Strong + glose anglaise, **sans** morphologie)
/// et le pont vers la lecture.
const Map<String, dynamic> genese1 = {
  'bym_index': 1,
  'standard': 1,
  'book': 'Genèse',
  'osis_id': 'Gen',
  'chapters': [
    {
      'chapter': 1,
      'verses': [
        {
          'verse': 1,
          'words': [
            {'h': 'בְּרֵאשִׁ֖ית', 't': 'bə·rê·šîṯ', 's': 'H7225',
              'f': 'In the beginning'},
            {'h': 'בָּרָ֣א', 't': 'bā·rā', 's': 'H1254', 'f': 'created'},
          ],
        },
      ],
    },
  ],
};

/// Jean 1:1 — la moitié grec du même corpus, où le mot part par `m` et non
/// par `h` : c'est ce qui bascule la colonne de droite à gauche à gauche à
/// droite, sans une ligne de code sachant dans quel Testament elle est.
const Map<String, dynamic> jean1 = {
  'bym_index': 43,
  'standard': 43,
  'book': 'Jean',
  'osis_id': 'John',
  'chapters': [
    {
      'chapter': 1,
      'verses': [
        {
          'verse': 1,
          'words': [
            {'m': 'Ἐν', 't': 'En', 's': 'G1722', 'f': 'In'},
            {'m': 'ἀρχῇ', 't': 'archēi', 's': 'G746', 'f': 'the beginning'},
          ],
        },
      ],
    },
  ],
};

void main() {
  group('canon de l\'interlinéaire complet', () {
    test('IL est téléchargeable, Bible entière, au format ati', () {
      final entry = versionByCode('IL');

      expect(entry, isNotNull);
      expect(entry!.availability, VersionAvailability.downloadable);
      expect(entry.format, VersionFormat.ati);
      expect(entry.fetchable, isTrue);
      // Le seul corpus de la Bibliothèque qui porte les deux Testaments en
      // interlinéaire : ni `otOnly` ni `ntOnly`.
      expect(entry.otOnly, isFalse);
      expect(entry.ntOnly, isFalse);
      expect(entry.canonOnly, isNull);
      expect(entry.interlinear, isTrue, reason: 'grille de colonnes de mots');
      expect(entry.bookCount, 66);
      expect(entry.containsBook(1), isTrue, reason: 'Genèse');
      expect(entry.containsBook(39), isTrue, reason: 'Malachie');
      expect(entry.containsBook(40), isTrue, reason: 'Matthieu');
      expect(entry.containsBook(66), isTrue, reason: 'Apocalypse');
      expect(entry.rights, contains('Domaine public'),
          reason: 'la provenance est portée sur la carte');
      // Le drapeau décrit le texte aplati, où `bookFromAti` ne joint que des
      // gloses : les numéros deviennent cliquables par les colonnes.
      expect(entry.hasStrong, isFalse);
      expect(entry.carriesNotes, isFalse);
      // Les gloses sont anglaises — le français de ce kit n'existe qu'en PDF.
      expect(entry.languageCode, 'EN');
      // Le chemin, pas l'hôte : celui-ci vise le dépôt publié, sauf en essai
      // local où les corpus téléchargeables pointent sur le serveur de la
      // machine. C'est la convention de `wlc_format_test`.
      expect(entry.urlTemplate, contains('/il/{book}.json'));
    });

    test('le fichier servi suit la numérotation standard', () {
      final entry = versionByCode('IL')!;
      // BYM 38 = 1 Chroniques, standard 13 — le fichier il/13.json.
      expect(bymToStandard(38), 13);
      expect(
        DownloadService.bookUri(entry, bymToStandard(38)).toString(),
        endsWith('/il/13.json'),
      );
    });
  });

  group('lecture de l\'interlinéaire complet', () {
    test('un mot hébreu part par `h` et se lit de droite à gauche', () {
      final book = bookFromAti(genese1, bymIndex: 1);

      final verse = book.chapters.first.verses.first;
      expect(verse.mots, hasLength(2));
      // La ligne aplatie est la glose anglaise jointe : chercher et partager
      // y trouvent du texte, les colonnes lisent les mots.
      expect(verse.text, 'In the beginning created');

      final mot = verse.mots!.first;
      expect(mot.hebrew, 'בְּרֵאשִׁ֖ית');
      expect(mot.modern, isNull);
      expect(mot.greek, isFalse, reason: 'hébreu : de droite à gauche');
      expect(mot.strong, 'H7225');
      expect(mot.readableGloss, 'In the beginning');
      // Le kit ne livre aucune translittération : elle est calculée, par
      // l'outil même de la WLC — un seul générateur pour un même texte
      // pointé, donc les mêmes coupes « · » et la même ponctuation de fin
      // de mot, `;` compris.
      expect(mot.translit, 'bə·rê·šîṯ');
    });

    test('un mot grec part par `m` et se lit de gauche à droite', () {
      final book = bookFromAti(jean1, bymIndex: 43);

      final mot = book.chapters.first.verses.first.mots!.first;
      expect(mot.modern, 'Ἐν');
      expect(mot.hebrew, isNull);
      expect(mot.greek, isTrue, reason: 'grec : de gauche à droite');
      expect(mot.strong, 'G1722');
      // Le grec passe par `translit_grec`, dont l'accord avec la
      // convention est mesuré contre le lexique Strong du kit Stephanus.
      expect(mot.translit, 'En');
    });

    test('chaque mot porte une translittération, jamais vide', () {
      // Le générateur l'écrit sur les 445 326 mots des deux testaments.
      // Sans elle, qui ne lit ni l'hébreu ni le grec n'a devant lui qu'un
      // mot illisible et une glose anglaise.
      for (final json in [genese1, jean1]) {
        final book = AtiBook.fromJson(json);
        for (final chapitre in book.chapters) {
          for (final verset in chapitre.verses) {
            for (final mot in verset.words) {
              expect(mot.translit, isNotNull, reason: mot.strong);
              expect(mot.translit, isNotEmpty, reason: mot.strong);
            }
          }
        }
      }
    });

    test('le kit n\'a aucune morphologie : aucune ligne d\'analyse', () {
      // C'est le point à ne pas rater : ce corpus ne porte ni `g` ni `a`,
      // et la feuille d'un mot n'y montre donc pas d'« Analyse ». Rien n'est
      // inventé pour la remplir — l'AT hébreu est couvert par l'ATI, le NT
      // grec par le NTI, tous deux avec leur analyse.
      final book = AtiBook.fromJson(genese1);
      final mot = book.chapters.first.verses.first.words.first;

      expect(mot.grammar, isNull);
      expect(mot.analysis, isNull);
      expect(book.chapters.first.verses.first.words.first.gloss, isNotNull);
    });
  });
}
