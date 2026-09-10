# Avant publication pub.dev

Ce SDK est maintenant compilé et testé (`dart analyze` : aucun problème ;
`dart test` : 6/6 tests, stable sur 2 exécutions consécutives) — le
toolchain Dart/Flutter (snap) de cet environnement était cassé au niveau du
wrapper `/snap/bin/dart` (silencieux/bloqué indéfiniment), mais le vrai
binaire (`~/snap/flutter/common/flutter/bin/dart`) fonctionne
parfaitement une fois appelé directement. La relecture manuelle faite avant
(super-paramètres avec valeur par défaut, records Dart 3, `library;` sans
nom) s'est révélée correcte à la compilation.

## Bloquant

- [ ] **Tester contre une vraie session de checkout** (créée avec le SDK
      Node/PHP/Python) sur `api.alphapay.me` -- aucun des 4 SDK n'a
      d'endpoint de checkout PUBLIC testé en conditions réelles pour
      l'instant (les vérifications précédentes portaient sur l'API marchand
      à clé API, jamais `/checkout/{slug}/*`).
- [ ] Décider si ce paquet doit rester pur Dart (choix actuel -- fonctionne
      partout, y compris hors Flutter) ou ajouter une dépendance `flutter`
      explicite si des widgets prêts à l'emploi (formulaire de paiement,
      sélecteur de réseau) sont attendus en plus du client API.
- [ ] Choisir le nom de package pub.dev définitif si `alphapay_checkout` est
      déjà pris.
- [ ] `dart pub get` signale 9 paquets avec des versions plus récentes
      incompatibles avec les contraintes actuelles (`dart pub outdated` pour
      le détail) -- rien de bloquant, juste à revoir avant publication.

## Souhaitable avant v1.0.0

- [ ] Fournir un exemple Flutter complet (`example/`) avec un écran de
      paiement réel (formulaire réseau/numéro, indicateur de polling, gestion
      des erreurs) -- ce SDK n'expose que la couche client API, pas de widgets.
- [ ] CI (GitHub Actions) : `dart analyze` + `dart test` sur chaque PR.
- [ ] `dart doc` pour publier la documentation générée sur pub.dev.
- [ ] Committer `pubspec.lock` est déconseillé pour un package (par
      opposition à une app) -- déjà dans `.gitignore`, à confirmer que c'est
      le bon choix pour ce cas précis.

## Fait

- [x] Endpoints publics de checkout entièrement retracés depuis le code
      source réel d'AlphaPayBack (`apps.checkout.views.public`,
      `apps.checkout.serializers.public`) -- formes de requête/réponse
      vérifiées champ par champ, pas devinées depuis les noms d'endpoints.
- [x] Architecture volontairement SANS clé API secrète -- ce SDK ne peut
      physiquement pas exposer un secret marchand, contrairement à un
      copier-coller mal dégradé des 3 autres SDK.
- [x] Enveloppe `{success, data, code}` déballée, exceptions typées incluant
      2 codes spécifiques à ce flux (`AlphaPaySessionGoneException` 410,
      `AlphaPayConflictException` 409 `payment_already_pending`) qui
      n'existent pas dans les 3 autres SDK -- propres à la sémantique
      one-shot d'une session de checkout.
- [x] `pollStatus()` -- sondage automatique jusqu'à statut terminal, pas
      présent dans les autres SDK (qui n'ont pas de notion de "session à
      suivre en direct" de la même façon).
- [x] 6 tests (mock `http.Client`, cf. `package:http/testing.dart`),
      couvrant l'enveloppe, l'absence totale de header d'auth, les 2 codes
      d'erreur propres à ce flux, le retry 429, et `pollStatus` -- **exécutés
      avec succès, 2 fois d'affilée.**
- [x] `dart analyze` : aucun problème détecté.
