import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../data/theme_catalog.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import 'premium_style.dart';
import 'verse_tile.dart' show ReadingRhythm;

/// L'aperçu de lecture, en tête de la carte LECTURE des Réglages : la page du
/// lecteur en miniature.
///
/// Les onze réglages de lecture vivent dans une seule carte, longue de trois
/// écrans : pour savoir ce qu'ils donnent ensemble, il fallait les régler,
/// sortir, ouvrir un chapitre, revenir, corriger. L'aperçu répond sur place —
/// il porte le verset d'ouverture de la Genèse posé sur le panneau du thème en
/// vigueur (fond, voile, opacité) et suit chaque curseur en direct.
///
/// Ses formules sont celles du lecteur ([ReadingRhythm], les bornes du chiffre
/// de verset, la carte de note), reprises telles quelles puis multipliées par
/// [_miniature] : il ne peut pas montrer autre chose que ce que la lecture
/// affichera, à l'échelle de la carte près. L'échantillon est le Ge. 1:1 du
/// texte BYM — le verset que la feuille « Police » emploie déjà — et sa note
/// est la vraie note du texte, pas un texte inventé.
class ReadingPreview extends StatelessWidget {
  /// Les préférences de lecture que l'écran vient de charger. L'aperçu les
  /// lit telles quelles : un curseur qui bouge ici fait bouger l'aperçu,
  /// exactement comme le lecteur derrière sa feuille ⋯.
  final AppPreferences prefs;

  const ReadingPreview({super.key, required this.prefs});

  /// Résolution de la miniature : tout ce que le lecteur calcule est repris
  /// tel quel, puis multiplié par ce facteur. .62 fait tomber le corps par
  /// défaut (22 pt) à ~13,6 pt — la taille à laquelle la feuille « Police »
  /// montre déjà son échantillon — et tient le verset, sa note et sa légende
  /// dans la hauteur d'une carte.
  static const double _miniature = .62;

  /// Ge. 1:1, verbatim du texte BYM. Public : c'est l'échantillon que les
  /// tests cherchent à l'écran pour vérifier que l'aperçu suit les réglages.
  static const String sampleText =
      'Au commencement Elohîm créa les cieux et la Terre.';

  /// Le mot noté de ce verset et la tête de sa note. La note entière fait
  /// trois cents signes : l'aperçu dit ce qu'une note occupe sous un verset,
  /// pas ce qu'elle raconte — la carte la coupe à deux lignes.
  static const String _noteWord = 'commencement';
  static const String _noteHead =
      'Bereshit bara elohîm èth hashamaïm vehèth ah aretz.';

  /// Position du mot noté, cherchée plutôt qu'écrite en dur : l'échantillon
  /// peut être retouché sans que la note se détache de son mot.
  static final int _noteStart = sampleText.indexOf(_noteWord);

  /// Le thème en vigueur, couleur du texte appliquée — même dérivation que le
  /// lecteur (`withTextColor` recompute notes et liens), pour qu'un texte
  /// personnalisé se voie ici comme en lecture.
  BibleTheme _theme() {
    final theme = themeById(prefs.themeId);
    final override = int.tryParse(prefs.textColorOverride ?? '');
    return override == null ? theme : theme.withTextColor(Color(override));
  }

  /// L'échantillon ne vaut que ce que la version active sait porter : « Texte
  /// + notes » restaure le vrai verset ; une LSGS, qui ne porte pas de notes,
  /// montre le texte seul — c'est ce que la rangée « Notes » annonce.
  bool _showNotes() =>
      prefs.notesMode &&
      (versionByCode(prefs.versionCode)?.carriesNotes ?? false);

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final theme = _theme();
    // Le rythme du lecteur, calculé à la taille réelle : ce sont **ses**
    // proportions qu'on miniature, pas celles d'une autre échelle.
    final rhythm = ReadingRhythm(
      fontSize: prefs.fontSize,
      spacing: prefs.spacing,
    );
    final body = TextStyle(
      fontFamily: prefs.readingFont.fontFamily,
      fontSize: prefs.fontSize * _miniature,
      fontWeight: prefs.fontWeight.weight,
      color: theme.textColor,
      height: rhythm.lineHeight,
      letterSpacing: rhythm.letterSpacing * _miniature,
    );
    final showNotes = _showNotes();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'APERÇU',
              style: premiumText(
                context,
                11,
                FontWeight.w800,
                p.textGrey,
                spacing: 1.2,
              ),
            ),
            const Spacer(),
            // Ce que l'échantillon porte, et qu'on ne voit pas ailleurs sur
            // cette carte : le thème (dont la rangée vit dans APPARENCE) et le
            // texte d'où le verset est tiré.
            Text(
              '${theme.name} · ${VersionRepository.embeddedCode}',
              style: premiumText(context, 11, FontWeight.w600, p.textGrey),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _page(theme, body, rhythm, showNotes),
        const SizedBox(height: 8),
        Text(
          // Ce qu'un coup d'œil ne déduit pas du dessin : la police, la
          // taille, l'alignement, les marges, le voile.
          _caption(),
          style: premiumText(context, 11, FontWeight.w500, p.textGrey),
        ),
      ],
    );
  }

  /// La page : le fond du thème sous son voile, le panneau, le verset.
  ///
  /// Le fond est en pleine largeur, le panneau centré sur la mesure du
  /// lecteur — sur une carte large, la ligne ne s'étire pas plus que dans la
  /// lecture (≈ 74 signes par ligne, à toutes les tailles).
  Widget _page(
    BibleTheme theme,
    TextStyle body,
    ReadingRhythm rhythm,
    bool showNotes,
  ) {
    final measure = (prefs.fontSize * 37).clamp(600.0, 860.0) * _miniature;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16 * _miniature),
      child: DecoratedBox(
        decoration: theme.hasBackground
            // Le vrai fond du lecteur : texture tuilée ou composition
            // couvrante, sous le même voile.
            ? BoxDecoration(image: theme.decorationImage())
            : BoxDecoration(color: theme.backgroundTone),
        child: Padding(
          // Le panneau du lecteur flotte à 8 px du bord de son fond.
          padding: EdgeInsets.all(8 * _miniature),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: measure),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.readingPanelColor(prefs.panelOpacity),
                  borderRadius: BorderRadius.circular(18 * _miniature),
                  border: Border.all(color: theme.panelBorderColor),
                ),
                // L'air du lecteur : les 16 pt du haut du panneau et la
                // respiration propre de la tuile (le 26 du bas appartient au
                // dernier verset d'un chapitre, pas à un verset seul).
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    (prefs.sidePadding + 6) * _miniature,
                    (16 + 2 * rhythm.s) * _miniature,
                    (prefs.sidePadding + 6) * _miniature,
                    (16 + 2 * rhythm.s) * _miniature,
                  ),
                  child: _verse(theme, body, rhythm, showNotes),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Le verset, dans la grammaire exacte du lecteur : la tuile à gouttière,
  /// ou le flux continu à exposant.
  Widget _verse(
    BibleTheme theme,
    TextStyle body,
    ReadingRhythm rhythm,
    bool showNotes,
  ) {
    if (prefs.layout == ReadingLayout.paragraph) {
      // Le flux ne connaît qu'une façon de porter une note — tissée dans la
      // phrase, entre parenthèses : « Sous » ne s'y applique pas.
      return Text.rich(
        TextSpan(children: _flowSpans(theme, body, showNotes)),
        style: body,
        textAlign: prefs.textAlign.align,
      );
    }

    // Le chiffre et sa pastille, aux bornes de la tuile (× .7, borné 11–16 ;
    // l'étoile reste à 11), puis à la miniature.
    final number = (prefs.fontSize * .7).clamp(11.0, 16.0) * _miniature;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            right: rhythm.gutterRightPad * _miniature,
            top: rhythm.gutterTopPad * _miniature,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '1',
                style: TextStyle(
                  fontFamily: body.fontFamily,
                  fontSize: number,
                  fontWeight: FontWeight.bold,
                  color: theme.verseNumColor,
                ),
              ),
              // Le verset porte une note du texte : la pastille du lecteur le
              // dit même quand les notes sont éteintes.
              Text(
                '✦',
                style: TextStyle(
                  fontSize: 11 * _miniature,
                  color: theme.verseNumColor,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: _tileSpans(theme, body, showNotes)),
                style: body,
                textAlign: prefs.textAlign.align,
              ),
              if (showNotes && prefs.disposition == NoteDisposition.below)
                _noteCard(theme, body),
            ],
          ),
        ),
      ],
    );
  }

  /// Le corps du verset découpé autour de son mot noté — le mot garde le
  /// corps du texte et ne porte qu'un souligné pointillé, comme dans la
  /// tuile ; ce qui suit dit la note : un exposant, ou la note elle-même.
  List<InlineSpan> _tileSpans(
    BibleTheme theme,
    TextStyle body,
    bool showNotes,
  ) {
    if (!showNotes) return [TextSpan(text: sampleText)];
    final end = _noteStart + _noteWord.length;
    final note = _noteStyle(theme, body);
    return [
      TextSpan(text: sampleText.substring(0, _noteStart)),
      TextSpan(text: _noteWord, style: _notedWord),
      if (prefs.disposition == NoteDisposition.below)
        TextSpan(
          text: '1',
          style: TextStyle(
            fontSize: body.fontSize! * .56,
            color: theme.linkColor,
            fontWeight: FontWeight.bold,
          ),
        )
      else
        TextSpan(
          children: [
            const TextSpan(text: ' ('),
            TextSpan(text: _noteHead, style: note),
            const TextSpan(text: ')'),
          ],
          style: note,
        ),
      TextSpan(text: sampleText.substring(end)),
    ];
  }

  /// Le flux continu : le numéro passe en exposant et la note est tissée dans
  /// la phrase, entre parenthèses — `disposition` ne s'applique qu'aux tuiles.
  List<InlineSpan> _flowSpans(
    BibleTheme theme,
    TextStyle body,
    bool showNotes,
  ) {
    final number = TextSpan(
      text: '1 ',
      style: TextStyle(
        fontFamily: body.fontFamily,
        fontSize: body.fontSize! * .58,
        color: theme.verseNumColor,
        fontWeight: FontWeight.w700,
      ),
    );
    if (!showNotes) {
      return [number, TextSpan(text: sampleText)];
    }
    final end = _noteStart + _noteWord.length;
    final note = _noteStyle(theme, body);
    return [
      number,
      TextSpan(text: sampleText.substring(0, _noteStart)),
      TextSpan(text: _noteWord, style: _notedWord),
      TextSpan(
        children: [
          const TextSpan(text: ' ('),
          TextSpan(text: _noteHead, style: note),
          const TextSpan(text: ')'),
        ],
        style: note,
      ),
      TextSpan(text: sampleText.substring(end)),
    ];
  }

  /// La carte de note du lecteur : le filet d'accent, le fond du panneau,
  /// « 1 · commencement : » en tête. Coupée à deux lignes : un aperçu montre
  /// la forme d'une note, et la note réelle en fait vingt.
  Widget _noteCard(BibleTheme theme, TextStyle body) {
    final size = body.fontSize! * .78;
    return Container(
      margin: EdgeInsets.only(top: 6 * _miniature),
      padding: EdgeInsets.only(
        left: 10 * _miniature,
        top: 6 * _miniature,
        bottom: 6 * _miniature,
      ),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.linkColor, width: 3 * _miniature),
        ),
        color: theme.panelColor,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '1 · $_noteWord : ',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: size,
                color: theme.linkColor,
              ),
            ),
            TextSpan(
              text: _noteHead,
              style: TextStyle(fontSize: size, color: theme.noteColor),
            ),
          ],
        ),
        // Le seul style commun aux deux fragments : la famille du corps. Le
        // reste (taille, couleurs) est porté par les fragments — l'interligne
        // de la lecture ne doit pas gagner la carte de note, qui n'en a pas.
        style: TextStyle(fontFamily: body.fontFamily),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Le mot noté : ni graisse, ni couleur, ni surlignage — un souligné
  /// pointillé, assez pour le situer sans peser sur la phrase.
  static const TextStyle _notedWord = TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
  );

  /// Le corps d'une note : la taille de la marge du lecteur (× .81 en ligne,
  /// × .78 en carte), la couleur du thème.
  TextStyle _noteStyle(BibleTheme theme, TextStyle body) => TextStyle(
    fontSize: body.fontSize! * .81,
    color: theme.noteColor,
  );

  /// La légende sous le verset : les cinq valeurs dont le dessin ne dit pas
  /// le chiffre. La graisse, l'aération et la disposition des notes se
  /// lisent, elles, sur l'échantillon.
  String _caption() {
    final percent =
        (prefs.fontSize / ReadingTextSize.extraLarge.fontSize * 100).round();
    return '${prefs.readingFont.fontFamily} · $percent % · '
        '${prefs.textAlign.label} · marges ${prefs.sidePadding.round()} px · '
        'panneau ${(prefs.panelOpacity * 100).round()} %';
  }
}
