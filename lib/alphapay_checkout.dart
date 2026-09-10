/// Client Dart pour les sessions de checkout hébergé AlphaPay -- sans clé
/// secrète, à utiliser côté client (app mobile/web). La session elle-même
/// doit être créée côté serveur avec le SDK Node/PHP/Python.
library alphapay_checkout;

export 'src/checkout.dart';
export 'src/exceptions.dart';
export 'src/models.dart';
