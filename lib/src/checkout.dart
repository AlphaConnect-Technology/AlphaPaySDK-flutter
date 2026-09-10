import 'dart:async';

import 'package:http/http.dart' as http;

import 'http.dart';
import 'models.dart';

/// Client de checkout hébergé AlphaPay -- SANS clé secrète, conçu pour être
/// embarqué dans une app mobile/web (contrairement aux SDK Node/PHP/Python,
/// qui portent la clé API complète et ne doivent jamais tourner côté client).
///
/// Le flux complet :
/// 1. Votre backend crée une session avec le SDK Node/PHP/Python
///    (`client.checkoutSessions.create(...)`) et transmet le `slug` obtenu à
///    l'app (jamais la clé API).
/// 2. L'app affiche le montant/les réseaux via [getSession]/[getNetworks].
/// 3. Le client choisit un réseau et saisit son numéro -> [pay].
/// 4. Si [PayResult.otpRequired], collectez le code SMS et appelez [confirmOtp].
/// 5. Sondez le paiement avec [pollStatus] jusqu'à un statut terminal.
///
/// Chaque appel réseau ici porte le `slug` -- 24 octets d'entropie généré
/// côté serveur -- comme SEULE preuve d'autorisation (cf.
/// apps.checkout.views.public._PublicCheckoutMixin, `authentication_classes
/// = []` assumé côté API). Ne journalisez/n'exposez jamais un `slug` en
/// dehors du flux de paiement qu'il représente.
class AlphaPayCheckout {
  AlphaPayCheckout({String? baseUrl, http.Client? httpClient, Duration timeout = const Duration(seconds: 30), int maxRetries = 2})
      : _http = Http(baseUrl: baseUrl, client: httpClient, timeout: timeout, maxRetries: maxRetries);

  final Http _http;

  /// Données d'affichage de la page : montant, marchand, réseaux payables.
  Future<CheckoutSessionDetail> getSession(String slug) async {
    final data = await _http.request('GET', '/checkout/$slug/');
    return CheckoutSessionDetail.fromJson(data as Map<String, dynamic>);
  }

  /// Réseaux payables pour un pays donné -- à appeler quand [CheckoutSessionDetail.networks]
  /// est vide (la session n'impose pas de pays, demandez-le d'abord au client).
  Future<NetworksResult> getNetworks(String slug, {required String country}) async {
    final data = await _http.request('GET', '/checkout/$slug/networks/', query: {'country': country});
    return NetworksResult.fromJson(data as Map<String, dynamic>);
  }

  /// Pousse le paiement (push USSD/mobile money direct, ou renvoie
  /// [PayResult.paymentUrl] pour les rares réseaux à redirection).
  ///
  /// [idempotencyKey] est optionnelle : sans elle, l'API dérive elle-même une
  /// clé depuis le slug + le contenu de la requête (cf.
  /// CheckoutSessionPayView.get_idempotency_key côté API) -- une resoumission
  /// identique (double-tap, retry réseau) est donc déjà protégée par défaut.
  /// Ne la fournissez explicitement que si vous voulez distinguer vous-même
  /// deux tentatives qui auraient autrement le même payload.
  Future<PayResult> pay(
    String slug, {
    required String network,
    String? country,
    CheckoutCustomer? customer,
    String? otp,
    String? idempotencyKey,
  }) async {
    final body = <String, dynamic>{
      'network': network,
      if (country != null) 'country': country,
      if (customer != null) 'customer': customer.toJson(),
      if (otp != null) 'otp': otp,
    };
    final data = await _http.request('POST', '/checkout/$slug/pay/', body: body, idempotencyKey: idempotencyKey);
    return PayResult.fromJson(data as Map<String, dynamic>);
  }

  /// Un seul appel de statut -- préférez [pollStatus] pour attendre une
  /// confirmation, ce endpoint seul ne fait qu'un instantané.
  Future<StatusResult> getStatus(String slug) async {
    final data = await _http.request('GET', '/checkout/$slug/status/');
    return StatusResult.fromJson(data as Map<String, dynamic>);
  }

  /// 2e étape pour les réseaux qui l'exigent (cf. [PayResult.otpRequired]/
  /// [NetworkOption.otpRequired]) -- le code que le client a reçu par SMS de
  /// son opérateur après [pay].
  Future<OtpConfirmResult> confirmOtp(String slug, {required String otp}) async {
    final data = await _http.request('POST', '/checkout/$slug/confirm-otp/', body: {'otp': otp});
    return OtpConfirmResult.fromJson(data as Map<String, dynamic>);
  }

  /// Sonde [getStatus] à intervalle régulier jusqu'à un statut terminal
  /// (payé/échoué/expiré/annulé) ou jusqu'à [timeout]. Émet chaque résultat
  /// intermédiaire (utile pour un indicateur "en attente de confirmation...")
  /// puis se termine après avoir émis le résultat terminal -- ne lève jamais
  /// pour un simple statut PENDING persistant, seulement sur une vraie
  /// erreur réseau/API ou si [timeout] est atteint sans statut terminal.
  ///
  /// ```dart
  /// await for (final status in checkout.pollStatus(slug)) {
  ///   print(status.status);
  ///   if (status.isTerminal) break;
  /// }
  /// ```
  Stream<StatusResult> pollStatus(
    String slug, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 5),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final status = await getStatus(slug);
      yield status;
      if (status.isTerminal) return;
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Le paiement est resté PENDING au-delà de $timeout.');
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Libère la connexion HTTP sous-jacente -- appelez ceci quand le client
  /// n'est plus utilisé (ex. `dispose()` d'un widget), pas obligatoire pour
  /// un usage ponctuel de courte durée.
  void close() => _http.close();
}
