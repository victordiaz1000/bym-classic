import 'package:flutter/material.dart';

/// Une ligne de texte qui défile de droite à gauche, sans fin.
///
/// Extrait du bandeau de mise à jour du texte pour être partagé avec celui de
/// l'application : deux défilements qui ne se ressembleraient pas se verraient
/// comme un défaut.
///
/// Sur toutes les largeurs : c'est le mouvement qui attire l'œil, et une tablette
/// où la phrase tient en entier n'a pas moins besoin qu'on la remarque. Seule
/// l'option système « réduire les animations » l'arrête — là, le défilement
/// perpétuel est précisément ce qu'on demande d'éviter, et la phrase reste
/// lisible, tronquée.
///
/// Deux copies séparées d'un intervalle défilent ensemble sur la largeur d'une
/// copie plus l'intervalle, puis l'animation reprend à zéro : à cet instant la
/// seconde copie occupe exactement la place de la première, donc la boucle est
/// invisible. C'est ce qui impose de **mesurer** le texte ([TextPainter]) au lieu
/// de le laisser se dimensionner tout seul : la translation et la période en
/// dépendent.
///
/// La vitesse est en pixels par seconde, pas une durée fixe : une phrase deux
/// fois plus longue défile deux fois plus longtemps, au même rythme de lecture.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// Blanc entre la fin d'une copie et le début de la suivante.
  static const double gap = 56;

  /// Vitesse du défilement. Réglages, pas paramètres : les deux bandeaux qui
  /// l'emploient doivent défiler au même rythme.
  static const double pixelsPerSecond = 42;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Remplacée par [_syncTicker] avant le premier tour : `repeat(period:)` fixe
    // la vraie période, celle que la largeur mesurée commande.
    duration: const Duration(seconds: 1),
  );

  /// Largeur d'**une** copie, dans le style et l'échelle de texte en vigueur.
  double _textWidth = 0;

  /// Hauteur de cette même copie. Mesurée, et pas déduite du style : c'est elle
  /// qui borne le défilement. Sans elle, `OverflowBox` lève « was given an
  /// infinite size during layout » — le bandeau vit dans une `Column`, qui
  /// n'impose aucune hauteur, et la `Row` la relaie telle quelle.
  double _textHeight = 0;

  /// Accessibilité : « réduire les animations » coupe le défilement.
  bool _reducedMotion = false;

  /// Période en cours, pour ne pas relancer un défilement qui tourne déjà :
  /// `repeat` repartirait de zéro, et le saut se verrait.
  Duration? _running;

  /// La largeur offerte n'entre pas dans cette décision : on défile aussi quand
  /// la phrase tient. Seul le réglage d'accessibilité l'emporte.
  bool get _shouldScroll => !_reducedMotion && _textWidth > 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ici et pas dans `initState` : la mesure a besoin de l'échelle de texte
    // ambiante (`ResponsiveTextScaling` en pose une), qui est une dépendance
    // héritée — un changement de taille système repasse donc par ici.
    _measure();
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _measure();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: Directionality.of(context),
      maxLines: 1,
      // La même échelle que celle avec laquelle `Text` peindra : sans elle, la
      // largeur mesurée dérive de la largeur réelle dès que le lecteur grossit
      // la police, et la reprise de boucle se voit.
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    _textWidth = painter.width;
    _textHeight = painter.height;
    painter.dispose();

    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncTicker();
  }

  /// Aligne le ticker sur ce que la mesure commande : il tourne dès qu'il y a un
  /// texte, il est à l'arrêt si le lecteur a demandé moins d'animations.
  void _syncTicker() {
    if (!_shouldScroll) {
      // Un défilement perpétuel qu'on ne peut pas arrêter est exactement ce que
      // « réduire les animations » demande d'éviter. La phrase reste lisible.
      //
      // `stop()` seul, sans remise à zéro de la valeur : écrire `value`
      // préviendrait les auditeurs, or on arrive ici depuis
      // `didChangeDependencies`, donc en pleine construction d'arbre. De toute
      // façon `repeat()` repart de la borne basse s'il faut redéfiler un jour.
      _controller.stop();
      _running = null;
      return;
    }
    final period = Duration(
      milliseconds:
          ((_textWidth + MarqueeText.gap) / MarqueeText.pixelsPerSecond * 1000)
              .round()
              .clamp(1200, 60000),
    );
    if (_controller.isAnimating && period == _running) return;
    _running = period;
    _controller.repeat(period: period);
  }

  @override
  Widget build(BuildContext context) {
    // Plus de `LayoutBuilder` : la largeur offerte n'entre plus dans la
    // décision, et la translation ne dépend que du texte mesuré. Un `ClipRect`
    // borné par l'`Expanded` parent suffit à couper ce qui dépasse.
    if (!_shouldScroll) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final copy = Text(
      widget.text,
      style: widget.style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
    );
    final span = _textWidth + MarqueeText.gap;
    return SizedBox(
      height: _textHeight,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Transform.translate(
            key: const Key('marqueeText'),
            offset: Offset(-_controller.value * span, 0),
            // `OverflowBox` relâche la contrainte de largeur : les deux copies
            // dépassent à droite au lieu d'être comprimées, et le `ClipRect`
            // au-dessus les coupe au bord du bandeau.
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  copy,
                  const SizedBox(width: MarqueeText.gap),
                  copy,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
