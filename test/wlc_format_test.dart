import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/models/ati.dart';

/// Genèse 1,1 telle que `WLC/wlc_to_json.py` l'écrit — copiée depuis
/// `bym-bibles/wlc/1.json`, pas reconstituée : ce qui distingue la WLC de
/// l'ATI ne se voit que sur du vrai.
///
/// Trois faits du corpus y sont figés, et ils ne sont pas décoratifs :
///
/// - le mot passe par `h` et non par `m`. `AtiWord.greek` se décide sur les
///   clés grecques, et une WLC écrite en `m` s'afficherait de gauche à
///   droite, à contresens du texte ;
/// - le pointage est celui du codex. L'ATI repointe `d` selon la forme
///   canonique (`h`=יָשָׁב mais `d`=יַשֵּׁב) : ce travail éditorial n'est pas
///   dérivable de la WLC, et le pointage source est conservé tel quel ;
/// - la translittération `t` est **générée** à partir des points du codex.
///   L'ATI ne fournit qu'une comparaison : rien de son `t` n'est lu ici.
///
/// Les tables `cg` / `ca` sont tronquées aux seules entrées que ce verset
/// utilise ; le livre complet en porte 8 et 998.
const Map<String, dynamic> genese1 = {
  'bym_index': 1,
  'standard': 1,
  'book': 'Genèse',
  // La casse titrée de la maison : les assets lsg / lss / lsgs portent tous
  // `Gen`, et c'est aussi le nom de fichier d'openscriptures/morphhb.
  'osis_id': 'Gen',
  'cg': ['Nom', 'Verbe', 'Particule'],
  // `ca` porte la lecture en français du code OSHB, pas le code lui-même :
  // c'est ce que la feuille affiche sous « Analyse ». Les sept entrées de ce
  // verset sont écrites telles que `wlc_to_json.py` les produit.
  'ca': [
    'Nom commun· féminin singulier· état absolu— Préposition',
    'Verbe qal parfait (qatal)· 3ᵉ masculin singulier',
    'Nom commun· masculin pluriel· état absolu',
    'Particule marqueur d’objet direct',
    'Nom commun· masculin pluriel· état absolu— Particule article défini',
    'Particule marqueur d’objet direct— Conjonction',
    'Nom commun· féminin et masculin singulier· état absolu— '
    'Particule article défini',
  ],
  'chapters': [
    {
      'chapter': 1,
      'verses': [
        {
          'verse': 1,
          'words': [
            // Le `/` du source est retiré de `h` et devient le `•` de `d`.
            {
              'h': 'בְּרֵאשִׁ֖ית',
              'd': 'בְּ • רֵאשִׁ֖ית',
              's': 'H7225',
              'g': 0,
              'a': 0,
              't': 'bə·rê·šîṯ',
            },
            // Sans morphème scindé, pas de `d` : le mot n'a rien à apprendre
            // au-delà de `h`.
            {'h': 'בָּרָ֣א', 's': 'H1254', 'g': 1, 'a': 1, 't': 'bā·rā'},
            // L'accent devient la ponctuation de fin de mot : etnahta → `;`.
            {
              'h': 'אֱלֹהִ֑ים',
              's': 'H430',
              'g': 0,
              'a': 2,
              't': '’ĕ·lō·hîm;',
            },
            // Marqueur d'objet direct, sans Strong propre dans la source.
            {'h': 'אֵ֥ת', 's': 'H853', 'g': 2, 'a': 3, 't': '’êṯ'},
            {
              'h': 'הַשָּׁמַ֖יִם',
              'd': 'הַ • שָּׁמַ֖יִם',
              's': 'H8064',
              'g': 0,
              'a': 4,
              't': 'haš·šā·ma·yim',
            },
            {
              'h': 'וְאֵ֥ת',
              'd': 'וְ • אֵ֥ת',
              's': 'H853',
              'g': 2,
              'a': 5,
              't': 'wə·’êṯ',
            },
            // Le sof pasuq est du texte : il va dans `h`, jamais dans `d` —
            // et il se translittère en `.`.
            {
              'h': 'הָאָֽרֶץ׃',
              'd': 'הָ • אָֽרֶץ',
              's': 'H776',
              'g': 0,
              'a': 6,
              't': 'hā·’ā·reṣ.',
            },
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
      expect(mot.analysis, 'Nom commun· féminin singulier· état absolu— '
          'Préposition');
      expect(mot.gloss, isNull, reason: laSourceNAPasDeGlose);
    });

    test('l’analyse se lit en français, le code OSHB seul n’explique rien', () {
      // `R/Ncfsa` ne dit rien à qui ne connaît pas la table OSHB. La
      // feuille affiche `analysis`, qui est donc rendu lisible — et le
      // morphème de tête s'écrit d'abord, le préfixe ensuite, comme la
      // lecture se fait.
      final livre = bookFromAti(genese1, bymIndex: 1);
      final mots = livre.chapters.first.verses.first.mots!;

      expect(mots[0].analysis, contains('Préposition'),
          reason: 'la préposition est la tête, elle ferme la lecture');
      expect(mots[0].analysis, endsWith('Préposition'));
      expect(mots[3].analysis, 'Particule marqueur d’objet direct');
      expect(mots[4].analysis,
          'Nom commun· masculin pluriel· état absolu— Particule article '
          'défini');
      for (final mot in mots) {
        expect(mot.analysis, isNotNull);
        expect(mot.analysis, isNotEmpty);
        expect(mot.analysis!.contains('/'), isFalse,
            reason: 'un code comme `Td/Ncmpa` n’aurait aucun sens pour le '
                'lecteur ; la table est appliquée, pas affichée');
      }
    });

    test('la translittération est lue dans `t`, syllabes et ponctuation', () {
      // Le champ existe et l'app le lit : c'est `AtiWord.translit`, la même
      // clé que l'ATI. Le contenu, lui, vient des points du codex.
      final livre = bookFromAti(genese1, bymIndex: 1);
      final mots = livre.chapters.first.verses.first.mots!;

      expect(mots[0].translit, 'bə·rê·šîṯ');
      expect(mots[2].translit, '’ĕ·lō·hîm;',
          reason: 'etnahta devient `;`, et le mot garde ses syllabes');
      expect(mots[6].translit, 'hā·’ā·reṣ.',
          reason: 'le sof pasuq devient `.`');
    });

    test('chaque mot du verset porte une translittération, jamais vide', () {
      final livre = bookFromAti(genese1, bymIndex: 1);
      final mots = livre.chapters.first.verses.first.mots!;

      for (final mot in mots) {
        expect(mot.translit, isNotNull);
        expect(mot.translit, isNotEmpty);
      }
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

    test('P est un pronom et R une préposition, dans le sens de la table OSHM', () {
      // Table officielle hb.openscriptures.org : P = pronoun,
      // R = preposition. La première version de la table les avait
      // inversés — 31 679 mots en portaient l'étiquette fausse.
      expect(etiquetteCourte('HP'), 'Pronom');
      expect(etiquetteCourte('HR'), 'Préposition');
      expect(etiquetteCourte('HP3ms'), 'Pronom');
      expect(etiquetteCourte('HP/Sp3ms'), 'Pronom',
          reason: 'le suffixe ne prend pas la tête, et le P reste seul');
    });

    test('le code de langue araméen n\'est pas une partie de speech', () {
      // « One language code is prefixed to the entire parsing string » :
      // H hébreu, A araméen. Sans retrait, le A de l'araméen est lu comme
      // un Adjectif — 2 749 étiquettes en portaient la faute.
      expect(etiquetteCourte('ANcmsa'), 'Nom');
      expect(etiquetteCourte('AVq3ms'), 'Verbe');
      expect(etiquetteCourte('AAcmsa'), 'Adjectif',
          reason: 'un vrai adjectif araméen porte AA, pas A');
    });

    test('l\'article araméen postposé ne prend pas la tête du mot', () {
      // `ANcmsd/Td` : nom suivi de son article. Le dernier morphème
      // porteur serait la particule, alors que la tête reste le nom —
      // 816 mots disaient Particule au lieu de Nom.
      expect(etiquetteCourte('ANcmsd/Td'), 'Nom');
      expect(etiquetteCourte('AC/Ncmsd/Td'), 'Nom');
      // Un `Td` seul, en tête, garde au contraire la tête qu'il porte.
      expect(etiquetteCourte('HTd/Ncmpa'), 'Nom');
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

const laSourceNAPasDeGlose =
    'La WLC est le texte hébreu : aucun français ne doit y être ajouté';

/// L'étiquette que `cg` porte pour un code morphologique OSHB.
///
/// Reproduit la règle de `WLC/wlc_to_json.py` pour la poser à côté des
/// valeurs qu'elle produit : le code de langue est retiré, la tête du mot
/// est le dernier morphème qui porte une partie de speech — un suffixe n'en
/// portant pas — et l'article araméen postposé ne prend pas cette tête.
String etiquetteCourte(String morph) {
  const pos = {
    'A': 'Adjectif',
    'C': 'Conjonction',
    'D': 'Adverbe',
    'N': 'Nom',
    'P': 'Pronom',
    'R': 'Préposition',
    'T': 'Particule',
    'V': 'Verbe',
  };
  var sans = morph;
  if (morph.length > 1 && 'HA'.contains(morph[0]) && pos.containsKey(morph[1])) {
    sans = morph.substring(1);
  }
  final morceaux = sans.split('/').where((m) => m.isNotEmpty).toList();
  final porteurs = morceaux.where((m) => pos.containsKey(m[0])).toList();
  if (porteurs.isEmpty) {
    return morceaux.isNotEmpty ? morceaux.last : sans;
  }
  var tete = porteurs.last;
  // Article araméen postposé : la tête est le nom qui le porte.
  if (porteurs.length > 1 && tete.startsWith('Td')) {
    tete = porteurs[porteurs.length - 2];
  }
  return pos[tete[0]] ?? sans;
}
