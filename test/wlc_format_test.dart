import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/models/ati.dart';

/// Genèse 1,1 telle que `WLC/wlc_to_json.py` l'écrit — copiée depuis
/// `bym-bibles/wlc/1.json`, pas reconstituée : ce qui distingue la WLC de
/// l'ATI ne se voit que sur du vrai.
///
/// Deux faits du corpus y sont figés, et ils ne sont pas décoratifs :
///
/// - le mot passe par `h` et non par `m`. `AtiWord.greek` se décide sur les
///   clés grecques, et une WLC écrite en `m` s'afficherait de gauche à
///   droite, à contresens du texte ;
/// - le pointage est celui du codex. L'ATI repointe `d` selon la forme
///   canonique (`h`=יָשָׁב mais `d`=יַשֵּׁב) : ce travail éditorial n'est pas
///   dérivable de la WLC, et le pointage source est conservé tel quel.
///
/// Les tables `cg` / `ca` sont tronquées aux seules entrées que ce verset
/// utilise ; le livre complet en porte 8 et 999.
const Map<String, dynamic> genese1 = {
  'bym_index': 1,
  'standard': 1,
  'book': 'Genèse',
  // La casse titrée de la maison : les assets lsg / lss / lsgs portent tous
  // `Gen`, et c'est aussi le nom de fichier d'openscriptures/morphhb.
  'osis_id': 'Gen',
  'cg': ['Nom', 'Verbe', 'Particule'],
  'ca': ['R/Ncfsa', 'Vqp3ms', 'Ncmpa', 'To', 'Td/Ncmpa', 'C/To', 'Td/Ncbsa'],
  'chapters': [
    {
      'chapter': 1,
      'verses': [
        {
          'verse': 1,
          'words': [
            // Le `/` du source est retiré de `h` et devient le `•` de `d`.
            {'h': 'בְּרֵאשִׁ֖ית', 'd': 'בְּ • רֵאשִׁ֖ית', 's': 'H7225', 'g': 0, 'a': 0},
            // Sans morphème scindé, pas de `d` : le mot n'a rien à apprendre
            // au-delà de `h`.
            {'h': 'בָּרָ֣א', 's': 'H1254', 'g': 1, 'a': 1},
            {'h': 'אֱלֹהִ֑ים', 's': 'H430', 'g': 0, 'a': 2},
            // Marqueur d'objet direct, sans Strong propre dans la source.
            {'h': 'אֵ֥ת', 's': 'H853', 'g': 2, 'a': 3},
            {'h': 'הַשָּׁמַ֖יִם', 'd': 'הַ • שָּׁמַ֖יִם', 's': 'H8064', 'g': 0, 'a': 4},
            {'h': 'וְאֵ֥ת', 'd': 'וְ • אֵ֥ת', 's': 'H853', 'g': 2, 'a': 5},
            // Le sof pasuq est du texte : il va dans `h`, jamais dans `d`.
            {'h': 'הָאָֽרֶץ׃', 'd': 'הָ • אָֽרֶץ', 's': 'H776', 'g': 0, 'a': 6},
          ],
        },
      ],
    },
  ],
};

void main() {
  group('WLC', () {
    test('un mot hébreu est lu comme de l\'hébreu, pas comme du grec', () {
      final livre = bookFromAti(genese1, bymIndex: 1);
      final mots = livre.chapters.first.verses.first.mots!;

      expect(mots, hasLength(7));
      expect(mots.first.hebrew, 'בְּרֵאשִׁ֖ית');
      expect(mots.first.greek, isFalse,
          reason: 'la clé `h` ne fait pas basculer le rendu en grec');
    });

    test('la même donnée écrite en `m` serait lue pour du grec', () {
      // Le fait que la règle existe, et qu'elle tient à la clé et non au
      // contenu : c'est pourquoi le convertisseur ne peut pas écrire `m`.
      final enGrec = AtiWord.fromJson(const {'m': 'Ἐν', 's': 'G1722'});
      final enHebreu = AtiWord.fromJson(const {'h': 'בְּרֵאשִׁ֖ית', 's': 'H7225'});

      expect(enGrec.greek, isTrue);
      expect(enHebreu.greek, isFalse);
    });

    test('le découpage morphémique rejoint la table `cg` en français', () {
      final livre = bookFromAti(genese1, bymIndex: 1);
      final mot = livre.chapters.first.verses.first.mots!.first;

      expect(mot.split, 'בְּ • רֵאשִׁ֖ית');
      expect(mot.grammar, 'Nom');
      expect(mot.analysis, 'R/Ncfsa');
      expect(mot.translit, isNull, reason: laSourceNAPasDeTranslitteration);
      expect(mot.gloss, isNull, reason: laSourceNAPasDeGlose);
    });

    test('un mot sans morphème scindé n\'a pas de découpage', () {
      final livre = bookFromAti(genese1, bymIndex: 1);
      final mots = livre.chapters.first.verses.first.mots!;

      expect(mots[1].hebrew, 'בָּרָ֣א');
      expect(mots[1].split, isNull);
    });

    test('le sof pasuq reste dans le mot, hors du découpage', () {
      final livre = bookFromAti(genese1, bymIndex: 1);
      final dernier = livre.chapters.first.verses.last.mots!.last;

      expect(dernier.hebrew, endsWith('׃'));
      expect(dernier.split, isNot(contains('׃')));
    });

    test('la tête du mot ignore les suffixes : « son nom » reste un nom', () {
      // `HNcmsc/Sp3ms` : le suffixe `Sp3ms` ne porte pas de partie de
      // speech, et l'étiquette courte doit dire Nom, pas Sp3ms.
      expect(etiquetteCourte('HNcmsc/Sp3ms'), 'Nom');
      expect(etiquetteCourte('HR/Ncfsa'), 'Nom');
      expect(etiquetteCourte('HC/Vqw3ms'), 'Verbe');
      expect(etiquetteCourte('HTo'), 'Particule');
    });

    test('un index hors table donne null, pas une exception', () {
      final horsTable = AtiWord.fromJson(
        {'h': 'אֵ֥ת', 'g': 99, 'a': 99},
        grammarTable: ['Nom'],
        analysisTable: ['Ncmpa'],
      );

      expect(horsTable.grammar, isNull);
      expect(horsTable.analysis, isNull);
    });

    test('un verset sans glose se lit en interlinéaire, texte aplati vide', () {
      final livre = bookFromAti(genese1, bymIndex: 1);
      final verset = livre.chapters.first.verses.first;

      // Même situation que la SES, déjà téléchargeable : sans glose
      // française la ligne jointe n'a rien à dire, et le lecteur s'appuie
      // sur `mots`.
      expect(verset.text, isEmpty);
      expect(verset.mots, isNotEmpty);
    });
  });

  group('catalogue', () {
    test('WLC est téléchargeable, Ancien Testament seul, au format ati', () {
      final entry = versionByCode('WLC');

      expect(entry, isNotNull);
      expect(entry!.format, VersionFormat.ati);
      expect(entry.fetchable, isTrue);
      expect(entry.otOnly, isTrue);
      expect(entry.bookCount, 39);
      expect(entry.containsBook(39), isTrue, reason: 'Malachie');
      expect(entry.containsBook(40), isFalse, reason: 'Matthieu');
      expect(entry.languageCode, 'HE');
      // La source n'est pas Biblia Universalis : c'est la version de la
      // Bibliothèque qui en vient d'ailleurs, et les deux lignes le disent.
      expect(entry.rights, isNot(contains('Biblia Universalis')));
      expect(entry.rights, contains('domaine public'));
      expect(entry.rights, contains('CC BY 4.0'));
      expect(entry.attribution, contains('Open Scriptures'));
      // Le drapeau décrit le texte aplati, où aucun code n'est inséré.
      expect(entry.hasStrong, isFalse);
      expect(entry.carriesNotes, isFalse);
    });

    test('la WLC rejoint l\'ATI dans le même sous-dossier hébergé', () {
      final wlc = versionByCode('WLC')!;
      final ati = versionByCode('ATI')!;

      expect(wlc.urlTemplate, contains('/wlc/{book}.json'));
      expect(ati.urlTemplate, contains('/ati/{book}.json'));
      // Même canon, donc mêmes livres servis — et l'ATI, autre édition du
      // même hébreu, n'est ni copiée ni référencée par la WLC.
      expect(wlc.bookCount, ati.bookCount);
    });
  });
}

const laSourceNAPasDeTranslitteration =
    'OSHB ne fournit pas de translittération, et rien ne doit en tenir lieu';

const laSourceNAPasDeGlose =
    'La WLC est le texte hébreu : aucun français ne doit y être ajouté';

/// L'étiquette que `cg` porte pour un code morphologique OSHB.
///
/// Reproduit la règle de `WLC/wlc_to_json.py` pour la poser à côté des
/// valeurs qu'elle produit : la tête du mot est le dernier morphème qui
/// porte une partie de speech, un suffixe n'en portant pas.
String etiquetteCourte(String morph) {
  const pos = {
    'A': 'Adjectif',
    'C': 'Conjonction',
    'D': 'Adverbe',
    'N': 'Nom',
    'P': 'Préposition',
    'R': 'Pronom',
    'T': 'Particule',
    'V': 'Verbe',
  };
  final sansH = morph.startsWith('H') ? morph.substring(1) : morph;
  final morceaux = sansH.split('/').where((m) => m.isNotEmpty).toList();
  final porteurs = morceaux.where((m) => pos.containsKey(m[0])).toList();
  final tete = porteurs.isNotEmpty
      ? porteurs.last
      : (morceaux.isNotEmpty ? morceaux.last : sansH);
  return pos[tete[0]] ?? sansH;
}
