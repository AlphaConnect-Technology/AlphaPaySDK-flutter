# alphapay_checkout

Client Dart officiel pour les sessions de checkout hébergé AlphaPay.

> **Statut : v0.1.0, non publié.** Voir [CHECKLIST.md](./CHECKLIST.md) pour
> ce qui manque avant une publication pub.dev.

**Pure Dart, pas de dépendance Flutter** — fonctionne dans une app Flutter
(iOS/Android/web/desktop) comme dans un script Dart/serveur classique. Une
seule dépendance : [`package:http`](https://pub.dev/packages/http), le
client HTTP officiel de l'équipe Dart.

## ⚠️ Ce SDK est fondamentalement différent des SDK Node.js/PHP/Python

Ce paquet **ne prend jamais de clé API secrète** — c'est un client
volontairement limité aux endpoints publics de paiement
(`/checkout/{slug}/*`, `authentication_classes = []` côté API, cf.
`apps.checkout.views.public._PublicCheckoutMixin`), fait pour tourner
**côté client** (app mobile, web) sans jamais exposer de secret.

Le flux complet, en 2 parties :

1. **Côté serveur** (votre backend), avec le
   [SDK Node.js](../AlphaPaySDK-node), [PHP](../AlphaPaySDK-php) ou
   [Python](../AlphaPaySDK-python) — qui, eux, portent la clé secrète :
   ```ts
   const session = await alphapay.checkoutSessions.create({
     amount: 5000, currency: "XOF",
     customer_email: "client@exemple.com", customer_name: "Client",
   });
   // Transmettez UNIQUEMENT session.slug à l'app (jamais la clé API).
   ```
2. **Côté app**, avec ce paquet — aucun secret, seul le `slug` suffit :
   ```dart
   final checkout = AlphaPayCheckout();
   final session = await checkout.getSession(slug);
   ```

**Ne mettez jamais une clé `sk_live_.../sk_test_...` dans le code d'une app
mobile ou web** — n'importe qui peut l'extraire du bundle. Le `slug` d'une
session de checkout (24 octets d'entropie, à usage unique) est conçu pour
être exposé côté client ; une clé API secrète ne l'est pas.

## Installation

```yaml
dependencies:
  alphapay_checkout: ^0.1.0
```

## Démarrage rapide

```dart
import 'package:alphapay_checkout/alphapay_checkout.dart';

final checkout = AlphaPayCheckout();

// 1. Affiche le montant et les réseaux payables.
final session = await checkout.getSession(slug);
print('${session.amount} ${session.currency} chez ${session.merchantName}');

// 2. Si la session n'impose pas de pays, demandez-le et rechargez les réseaux.
final networks = session.networks.isNotEmpty
    ? session.networks
    : (await checkout.getNetworks(slug, country: 'BJ')).networks;

// 3. Le client choisit un réseau et saisit son numéro.
final result = await checkout.pay(
  slug,
  network: 'MTN_BJ',
  customer: const CheckoutCustomer(phone: '+22900000000', firstName: 'Ayaba'),
);

// 4. Si un OTP est requis (Coris Bénin, Wizall Sénégal...), collectez-le et confirmez.
if (result.otpRequired) {
  await checkout.confirmOtp(slug, otp: '123456');
}

// 5. Sondez jusqu'à confirmation.
await for (final status in checkout.pollStatus(slug)) {
  print(status.status); // PENDING, puis PAID/FAILED/EXPIRED/CANCELLED
  if (status.isTerminal) break;
}
```

## Gestion des erreurs

```dart
try {
  await checkout.pay(slug, network: 'MTN_BJ', customer: customer);
} on AlphaPaySessionGoneException catch (e) {
  // 410 -- session déjà payée/expirée/annulée. e.errorCode = "paid"/"expired"/"cancelled".
} on AlphaPayConflictException catch (e) {
  // 409, e.errorCode == "payment_already_pending" -- un paiement est déjà en vol sur cette session.
} on AlphaPayValidationException catch (e) {
  print(e.fieldErrors); // erreurs de validation par champ, si applicable
} on AlphaPayException catch (e) {
  print('${e.status} ${e.errorCode}: ${e.message}');
}
```

Le client retente automatiquement (backoff exponentiel + gigue) sur
429/5xx/erreur réseau — 2 tentatives supplémentaires par défaut,
configurable via `maxRetries:`.

## Réseaux nécessitant un OTP pré-paiement

Certains réseaux (Orange Money Côte d'Ivoire/Burkina notamment) exigent que
le client génère un code USSD **avant** de payer. Vérifiez
`NetworkOption.otpRequired`/`otpInstructions` avant d'afficher le champ
numéro, et transmettez le code via le paramètre `otp:` de [pay]
directement — ce n'est pas la même chose que [confirmOtp] (utilisé, lui,
pour les réseaux qui confirment APRÈS le push initial).

## Endpoints couverts

| Méthode | Endpoint | Description |
|---|---|---|
| `getSession(slug)` | `GET /checkout/{slug}/` | Détails d'affichage |
| `getNetworks(slug, country:)` | `GET /checkout/{slug}/networks/` | Réseaux payables pour un pays |
| `pay(slug, ...)` | `POST /checkout/{slug}/pay/` | Initie le paiement |
| `getStatus(slug)` | `GET /checkout/{slug}/status/` | Un instantané du statut |
| `pollStatus(slug)` | (sonde `getStatus` en boucle) | Attend un statut terminal |
| `confirmOtp(slug, otp:)` | `POST /checkout/{slug}/confirm-otp/` | 2e étape pour les réseaux qui l'exigent |

Pas couvert par design : tout endpoint marchand (`/transactions/`,
`/payment-links/`, etc.) — ceux-là exigent une clé API secrète et
appartiennent aux SDK Node/PHP/Python, jamais à un client embarqué dans une
app.

## Développement

```bash
dart pub get
dart analyze
dart test
```

## Licence

MIT
