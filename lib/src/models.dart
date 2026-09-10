/// Modèles typés -- reflètent les serializers réels d'AlphaPayBack
/// (apps.checkout.serializers.public), vérifiés contre le code source, pas
/// devinés depuis un nom d'endpoint.
library;

/// Réponse de `GET /checkout/{slug}/` -- ce que voit la page de paiement :
/// jamais l'id interne du marchand ni ses métadonnées privées.
class CheckoutSessionDetail {
  const CheckoutSessionDetail({
    required this.slug,
    required this.merchantName,
    required this.amount,
    required this.currency,
    required this.status,
    required this.isUsable,
    required this.networks,
    this.description,
    this.customerEmail,
    this.customerName,
    this.customerPhone,
    this.expiresAt,
    this.transactionStatus,
    this.paymentUrl,
    this.returnUrl,
  });

  final String slug;
  final String merchantName;
  final String amount;
  final String currency;
  final String? description;
  final String? customerEmail;
  final String? customerName;
  final String? customerPhone;

  /// PENDING / PAID / EXPIRED / CANCELLED / FAILED (cf. CheckoutStatus côté API).
  final String status;
  final DateTime? expiresAt;

  /// False dès que [status] n'accepte plus de paiement (payée, expirée, annulée).
  final bool isUsable;

  /// Vide si la session n'impose pas de pays -- appelez alors
  /// [AlphaPayCheckout.getNetworks] une fois le pays choisi par le client.
  final List<NetworkOption> networks;

  /// Statut du dernier paiement tenté sur cette session, si un paiement est en cours
  /// (un client peut être reparti sur la page d'un fournisseur puis être revenu ici).
  final String? transactionStatus;
  final String? paymentUrl;
  final String? returnUrl;

  factory CheckoutSessionDetail.fromJson(Map<String, dynamic> json) {
    return CheckoutSessionDetail(
      slug: json['slug'] as String,
      merchantName: json['merchant_name'] as String,
      amount: json['amount'] as String,
      currency: json['currency'] as String,
      description: json['description'] as String?,
      customerEmail: json['customer_email'] as String?,
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      status: json['status'] as String,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : null,
      isUsable: json['is_usable'] as bool,
      networks: (json['networks'] as List<dynamic>? ?? []).map((e) => NetworkOption.fromJson(e as Map<String, dynamic>)).toList(),
      transactionStatus: json['transaction_status'] as String?,
      paymentUrl: (json['payment_url'] as String?)?.let((v) => v.isEmpty ? null : v),
      returnUrl: json['return_url'] as String?,
    );
  }
}

/// Un réseau payable (MTN Bénin, Orange Money CI, carte...), avec son
/// estimation de frais pour le montant de la session.
class NetworkOption {
  const NetworkOption({
    required this.code,
    required this.name,
    required this.otpRequired,
    this.otpInstructions,
    this.fee,
    this.total,
    this.currency,
    required this.unavailable,
  });

  /// Code réseau à passer tel quel à [AlphaPayCheckout.pay] (ex. "MTN_BJ").
  final String code;
  final String name;

  /// True pour les réseaux exigeant un code généré par le client AVANT de
  /// payer (ex. Orange Money CI/Burkina, #144*82#) -- affichez [otpInstructions]
  /// et collectez le code avant d'appeler [AlphaPayCheckout.pay] avec `otp:`.
  final bool otpRequired;
  final String? otpInstructions;

  /// Frais estimés à la charge du client (0 en mode frais déduits du marchand) -- `null` si [unavailable].
  final String? fee;

  /// Montant total estimé que le client paiera -- `null` si [unavailable].
  final String? total;
  final String? currency;

  /// True si ce réseau n'a aucune règle de tarification active : le paiement y échouerait à coup sûr, ne le proposez pas.
  final bool unavailable;

  factory NetworkOption.fromJson(Map<String, dynamic> json) {
    return NetworkOption(
      code: json['code'] as String,
      name: json['name'] as String,
      otpRequired: json['otp_required'] as bool? ?? false,
      otpInstructions: (json['otp_instructions'] as String?)?.let((v) => v.isEmpty ? null : v),
      fee: json['fee'] as String?,
      total: json['total'] as String?,
      currency: json['currency'] as String?,
      unavailable: json['unavailable'] as bool? ?? false,
    );
  }
}

/// Réponse de `GET /checkout/{slug}/networks/?country=XX`.
class NetworksResult {
  const NetworksResult({required this.networks, required this.amount, required this.currency, required this.exchangeRateError});

  final List<NetworkOption> networks;

  /// Montant converti dans la devise de CE pays si elle diffère de celle de la session -- affichez celui-ci, pas celui de [CheckoutSessionDetail.amount].
  final String amount;
  final String currency;

  /// True si la conversion a échoué (taux indisponible) -- les réseaux non globaux (carte/crypto exceptés) sont alors marqués `unavailable`.
  final bool exchangeRateError;

  factory NetworksResult.fromJson(Map<String, dynamic> json) {
    return NetworksResult(
      networks: (json['networks'] as List<dynamic>).map((e) => NetworkOption.fromJson(e as Map<String, dynamic>)).toList(),
      amount: json['amount'] as String,
      currency: json['currency'] as String,
      exchangeRateError: json['exchange_rate_error'] as bool? ?? false,
    );
  }
}

/// Coordonnées du client final -- optionnel si la session vient déjà d'un
/// lien de paiement (déjà pré-remplies côté serveur), requis sinon.
class CheckoutCustomer {
  const CheckoutCustomer({this.email, this.firstName, this.lastName, this.phone});

  final String? email;
  final String? firstName;
  final String? lastName;
  final String? phone;

  Map<String, dynamic> toJson() => {
        if (email != null) 'email': email,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (phone != null) 'phone': phone,
      };
}

/// Réponse de `POST /checkout/{slug}/pay/`.
class PayResult {
  const PayResult({required this.message, required this.transactionId, required this.status, this.paymentUrl, required this.otpRequired, this.instructions});

  final String message;
  final String transactionId;
  final String status;

  /// Non-vide UNIQUEMENT si l'opérateur impose une redirection (Wave, Orange
  /// QR, Djamo, carte 3DS) -- jamais une page brandée de gateway. Vide pour
  /// tous les réseaux à push USSD direct (MTN, Moov, Celtiis...).
  final String? paymentUrl;

  /// True pour Coris Bénin/Wizall Sénégal notamment -- appelez
  /// [AlphaPayCheckout.confirmOtp] avec le code reçu par SMS au lieu
  /// d'attendre/sonder [AlphaPayCheckout.getStatus].
  final bool otpRequired;

  /// Consigne à afficher au client MAINTENANT (composer un code USSD, etc.) -- forme libre, peut être vide.
  final Object? instructions;

  factory PayResult.fromJson(Map<String, dynamic> json) {
    return PayResult(
      message: json['message'] as String,
      transactionId: json['transaction_id'] as String,
      status: json['status'] as String,
      paymentUrl: (json['payment_url'] as String?)?.let((v) => v.isEmpty ? null : v),
      otpRequired: json['otp_required'] as bool? ?? false,
      instructions: json['instructions'],
    );
  }
}

/// Réponse de `GET /checkout/{slug}/status/` -- à sonder après [AlphaPayCheckout.pay]
/// jusqu'à un statut terminal (cf. [AlphaPayCheckout.pollStatus]).
class StatusResult {
  const StatusResult({
    required this.slug,
    required this.status,
    required this.amount,
    required this.currency,
    this.transactionStatus,
    this.transactionId,
    this.transactionReference,
    this.returnUrl,
    required this.otpRequired,
    this.instructions,
    this.paymentUrl,
  });

  final String slug;

  /// PENDING / PAID / EXPIRED / CANCELLED / FAILED.
  final String status;
  final String amount;
  final String currency;
  final String? transactionStatus;
  final String? transactionId;
  final String? transactionReference;
  final String? returnUrl;
  final bool otpRequired;
  final Object? instructions;
  final String? paymentUrl;

  /// True une fois [status] sorti de PENDING -- plus la peine de sonder après ça.
  bool get isTerminal => status != 'PENDING';

  factory StatusResult.fromJson(Map<String, dynamic> json) {
    return StatusResult(
      slug: json['slug'] as String,
      status: json['status'] as String,
      amount: json['amount'] as String,
      currency: json['currency'] as String,
      transactionStatus: json['transaction_status'] as String?,
      transactionId: json['transaction_id'] as String?,
      transactionReference: json['transaction_reference'] as String?,
      returnUrl: json['return_url'] as String?,
      otpRequired: json['otp_required'] as bool? ?? false,
      instructions: json['instructions'],
      paymentUrl: (json['payment_url'] as String?)?.let((v) => v.isEmpty ? null : v),
    );
  }
}

/// Réponse de `POST /checkout/{slug}/confirm-otp/`.
class OtpConfirmResult {
  const OtpConfirmResult({required this.transactionId, required this.status});

  final String transactionId;
  final String status;

  factory OtpConfirmResult.fromJson(Map<String, dynamic> json) {
    return OtpConfirmResult(transactionId: json['transaction_id'] as String, status: json['status'] as String);
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
