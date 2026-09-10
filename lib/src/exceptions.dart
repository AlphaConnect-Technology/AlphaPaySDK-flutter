/// Toute erreur API passe par apps.core.renderers.StandardJSONRenderer côté
/// AlphaPayBack :
///   {"success": false, "error": <forme variable>, "code": <statut HTTP>}
/// `error` n'a PAS une forme unique :
///   - erreurs de validation DRF      -> {"champ": ["message", ...], ...}
///   - erreurs métier personnalisées  -> {"message": "...", "code": "<code_machine>"}
///   - erreurs d'authentification/permission -> {"detail": "..."}
/// [message] normalise ces trois formes en une seule chaîne lisible ;
/// [raw] garde la forme originale pour qui a besoin du détail par champ.
class AlphaPayException implements Exception {
  AlphaPayException(
    this.message, {
    required this.status,
    this.errorCode,
    this.raw,
    this.fieldErrors,
    this.requestId,
  });

  final String message;
  final int status;

  /// Code machine, quand l'API en fournit un (ex. "invalid_file_type",
  /// "missing_country") -- absent sur les erreurs de validation par champ.
  final String? errorCode;

  /// Corps d'erreur brut, tel que renvoyé par l'API.
  final Object? raw;

  /// Présent uniquement sur une erreur de validation DRF ({"champ": [...]}).
  final Map<String, List<String>>? fieldErrors;

  final String? requestId;

  @override
  String toString() => 'AlphaPayException($status${errorCode != null ? ', $errorCode' : ''}): $message';

  /// Construit l'exception normalisée à partir de la réponse HTTP. [body] est
  /// déjà le contenu de la clé "error" de l'enveloppe (pas l'enveloppe entière).
  factory AlphaPayException.fromResponse(int status, Object? body, {String? requestId}) {
    final (message, errorCode, fieldErrors) = _interpretErrorBody(body);
    final args = (status: status, errorCode: errorCode, raw: body, fieldErrors: fieldErrors, requestId: requestId);

    if (status == 401) {
      return AlphaPayAuthenticationException(message, status: args.status, errorCode: args.errorCode, raw: args.raw, fieldErrors: args.fieldErrors, requestId: args.requestId);
    }
    if (status == 403) {
      return AlphaPayPermissionException(message, status: args.status, errorCode: args.errorCode, raw: args.raw, fieldErrors: args.fieldErrors, requestId: args.requestId);
    }
    if (status == 404) {
      return AlphaPayNotFoundException(message, status: args.status, errorCode: args.errorCode, raw: args.raw, fieldErrors: args.fieldErrors, requestId: args.requestId);
    }
    if (status == 409) {
      // "payment_already_pending" (double-soumission) le plus souvent sur ce SDK -- cf. CheckoutSessionPayView.
      return AlphaPayConflictException(message, status: args.status, errorCode: args.errorCode, raw: args.raw, fieldErrors: args.fieldErrors, requestId: args.requestId);
    }
    if (status == 410) {
      // Session expirée/annulée/payée -- cf. CheckoutSession.is_usable.
      return AlphaPaySessionGoneException(message, status: args.status, errorCode: args.errorCode, raw: args.raw, fieldErrors: args.fieldErrors, requestId: args.requestId);
    }
    if (status == 429) {
      return AlphaPayRateLimitException(message, status: args.status, errorCode: args.errorCode, raw: args.raw, fieldErrors: args.fieldErrors, requestId: args.requestId);
    }
    if (status == 400 || status == 422) {
      return AlphaPayValidationException(message, status: args.status, errorCode: args.errorCode, raw: args.raw, fieldErrors: args.fieldErrors, requestId: args.requestId);
    }
    if (status >= 500) {
      return AlphaPayServerException(message, status: args.status, errorCode: args.errorCode, raw: args.raw, fieldErrors: args.fieldErrors, requestId: args.requestId);
    }
    return AlphaPayException(message, status: args.status, errorCode: args.errorCode, raw: args.raw, fieldErrors: args.fieldErrors, requestId: args.requestId);
  }

  static (String, String?, Map<String, List<String>>?) _interpretErrorBody(Object? body) {
    if (body == null) return ('Erreur AlphaPay inconnue.', null, null);
    if (body is String) return (body, null, null);
    if (body is Map) {
      final message = body['message'];
      if (message is String) {
        final code = body['code'];
        return (message, code is String ? code : null, null);
      }
      final detail = body['detail'];
      if (detail is String) return (detail, null, null);

      final fieldErrors = <String, List<String>>{};
      body.forEach((key, value) {
        if (key is String && value is List && value.isNotEmpty && value.every((v) => v is String)) {
          fieldErrors[key] = value.cast<String>();
        }
      });
      if (fieldErrors.isNotEmpty) {
        final summary = fieldErrors.entries.map((e) => '${e.key}: ${e.value.join(', ')}').join(' — ');
        return (summary, null, fieldErrors);
      }
    }
    return ('Erreur AlphaPay inconnue.', null, null);
  }
}

class AlphaPayAuthenticationException extends AlphaPayException {
  AlphaPayAuthenticationException(super.message, {required super.status, super.errorCode, super.raw, super.fieldErrors, super.requestId});
}

class AlphaPayPermissionException extends AlphaPayException {
  AlphaPayPermissionException(super.message, {required super.status, super.errorCode, super.raw, super.fieldErrors, super.requestId});
}

class AlphaPayNotFoundException extends AlphaPayException {
  AlphaPayNotFoundException(super.message, {required super.status, super.errorCode, super.raw, super.fieldErrors, super.requestId});
}

class AlphaPayValidationException extends AlphaPayException {
  AlphaPayValidationException(super.message, {required super.status, super.errorCode, super.raw, super.fieldErrors, super.requestId});
}

/// 409 -- le plus souvent `errorCode == "payment_already_pending"` sur ce
/// SDK : un paiement est déjà en cours sur cette session (double-soumission).
class AlphaPayConflictException extends AlphaPayException {
  AlphaPayConflictException(super.message, {required super.status, super.errorCode, super.raw, super.fieldErrors, super.requestId});
}

/// 410 -- la session n'est plus utilisable (payée/expirée/annulée). `errorCode`
/// vaut le statut en minuscule ("paid", "expired", "cancelled").
class AlphaPaySessionGoneException extends AlphaPayException {
  AlphaPaySessionGoneException(super.message, {required super.status, super.errorCode, super.raw, super.fieldErrors, super.requestId});
}

class AlphaPayRateLimitException extends AlphaPayException {
  AlphaPayRateLimitException(super.message, {required super.status, super.errorCode, super.raw, super.fieldErrors, super.requestId, this.retryAfter});

  /// Secondes à attendre avant de réessayer, quand l'API le précise (header Retry-After).
  int? retryAfter;
}

class AlphaPayServerException extends AlphaPayException {
  AlphaPayServerException(super.message, {required super.status, super.errorCode, super.raw, super.fieldErrors, super.requestId});
}

/// Connexion/DNS/timeout -- jamais atteint le serveur AlphaPay, `status` vaut 0.
class AlphaPayConnectionException extends AlphaPayException {
  AlphaPayConnectionException(super.message, {super.status = 0, super.errorCode, super.raw, super.fieldErrors, super.requestId});
}

/// Levée par [AlphaPayCheckout.pollStatus]/vérification de signature -- pas une erreur HTTP.
class AlphaPayWebhookSignatureException implements Exception {
  AlphaPayWebhookSignatureException(this.message);
  final String message;
  @override
  String toString() => 'AlphaPayWebhookSignatureException: $message';
}
