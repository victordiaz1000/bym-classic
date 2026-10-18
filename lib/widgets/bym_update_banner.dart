import 'package:flutter/material.dart';

import '../data/bym_update_service.dart';
import 'marquee_text.dart';
import 'premium_style.dart';

/// Bandeau défilant annonçant qu'une correction du texte BYM attend l'accord du
/// lecteur : « Mettre à jour le texte BYM dans les Réglages · 21 livres ».
///
/// Troisième surface d'annonce, avec la pastille de la Bibliothèque et la section
/// de Réglages. Toutes trois écoutent [BymUpdateChecker.available], donc elles ne
/// peuvent pas se contredire, et **aucune n'installe quoi que ce soit** : celle-ci
/// conduit à Réglages, seul endroit qui décide d'un téléchargement. Elle existe
/// parce que les deux autres se laissent manquer — la lecture est l'écran où le
/// lecteur passe son temps.
///
/// Elle disparaît d'elle-même : `BymUpdateChecker.clear()` remet [available] à
/// null dès que la mise à jour est installée, ou que le lecteur revient au texte
/// embarqué.
///
/// **Rien à l'écran** sans mise à jour disponible — pas un `SizedBox` de quelques
/// pixels, rien. C'est ce qui garantit qu'aucune animation ne tourne dans le cas
/// ordinaire, donc que les tests widget des écrans hôtes continuent de se
/// stabiliser : un défilement en boucle programme des frames sans fin et
/// `pumpAndSettle` attendrait pour toujours. Un test **de ce bandeau** doit donc
/// pomper des durées explicites, jamais `pumpAndSettle` — sauf dans les deux cas
/// où l'on vérifie précisément que rien ne bouge (aucune mise à jour, ou
/// « réduire les animations »).
///
/// Le défilement a lieu sur **toutes** les largeurs, téléphone comme tablette :
/// c'est le mouvement qui fait remarquer l'annonce, et une tablette où la phrase
/// tient en entier n'a pas moins besoin d'être vue. Seule l'option système
/// « réduire les animations » l'arrête (voir [MarqueeText]).
class BymUpdateBanner extends StatelessWidget {
  /// Conduit à la section « MISE À JOUR DU TEXTE » de Réglages.
  ///
  /// Null quand l'écran hôte n'a pas de route vers Réglages (lecteur isolé,
  /// tests) : le bandeau reste alors une annonce à lire, il ne devient pas un
  /// faux bouton inerte — la phrase dit déjà où aller.
  final VoidCallback? onOpenSettings;

  const BymUpdateBanner({super.key, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BymUpdateCheck?>(
      valueListenable: BymUpdateChecker.available,
      builder: (context, check, _) {
        if (check == null || !check.hasUpdate) return const SizedBox.shrink();
        return _Banner(
          // Le compte vient du plan lui-même : c'est le même nombre que la
          // pastille de la Bibliothèque et que le bouton de Réglages.
          label: 'Mettre à jour le texte BYM dans les Réglages '
              '· ${check.bookLabel}',
          onTap: onOpenSettings,
        );
      },
    );
  }
}

/// La bande elle-même : liseré d'accent, icône, texte défilant, chevron.
class _Banner extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _Banner({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Material(
      color: p.primarySoft,
      child: InkWell(
        key: const Key('bymUpdateBanner'),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: p.primary.withValues(alpha: .28)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: p.primary),
              const SizedBox(width: 8),
              // Le texte défile dans la place qui reste : icône et chevron sont
              // posés en premier, donc ils ne se font jamais rogner par une
              // phrase longue ou une police agrandie.
              Expanded(
                child: MarqueeText(
                  text: label,
                  style: premiumText(context, 12.5, FontWeight.w700, p.primary),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 16, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }
}
