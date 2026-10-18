import 'package:flutter/material.dart';

import '../data/app_update_service.dart';
import 'marquee_text.dart';
import 'premium_style.dart';

/// Bandeau annonçant qu'une nouvelle version **de l'application** est publiée :
/// « Nouvelle version 1.0.1 — mettre à jour dans les Réglages ».
///
/// Jumeau de [BymUpdateBanner] : mêmes règles, même conduite. Il n'installe
/// rien — l'appui mène à Réglages, seul endroit qui télécharge et vérifie — et
/// il disparaît de lui-même quand [AppUpdateChecker.available] retombe à null.
///
/// **Rien à l'écran** sans version plus récente, pas même un `SizedBox` de
/// quelques pixels : le cas ordinaire ne doit programmer aucune frame, sinon les
/// tests widget des écrans hôtes ne se stabiliseraient plus.
class AppUpdateBanner extends StatelessWidget {
  /// Conduit à la section « MISE À JOUR DE L'APPLICATION » de Réglages. Null
  /// quand l'écran hôte n'a pas de route vers Réglages (tests) : le bandeau
  /// reste une annonce à lire, pas un faux bouton inerte.
  final VoidCallback? onOpenSettings;

  const AppUpdateBanner({super.key, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUpdateRelease?>(
      valueListenable: AppUpdateChecker.available,
      builder: (context, release, _) {
        if (release == null) return const SizedBox.shrink();
        return _Banner(
          label: 'Nouvelle version ${release.version} — mettre à jour dans '
              'les Réglages',
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
        key: const Key('appUpdateBanner'),
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
              Icon(Icons.system_update_alt, size: 14, color: p.primary),
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
