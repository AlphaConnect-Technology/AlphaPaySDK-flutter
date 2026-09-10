import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'exceptions.dart';

const _defaultBaseUrl = 'https://api.alphapay.me/api/v1';
const _defaultTimeout = Duration(seconds: 30);
const _defaultMaxRetries = 2;

/// Client HTTP bas niveau, partagé par [AlphaPayCheckout]. Gère l'enveloppe
/// standard {success, data, code}, les retries avec backoff sur 429/5xx/erreur
/// réseau, et le mapping vers des exceptions typées (cf. exceptions.dart).
///
/// AUCUN header d'authentification -- ces endpoints sont publics par design
/// (`authentication_classes = []` côté AlphaPayBack, cf.
/// apps.checkout.views.public._PublicCheckoutMixin) : le slug de la session
/// fait office de capacité, jamais une clé API secrète.
class Http {
  Http({String? baseUrl, http.Client? client, Duration timeout = _defaultTimeout, int maxRetries = _defaultMaxRetries})
      : baseUrl = (baseUrl ?? _defaultBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _timeout = timeout,
        _maxRetries = maxRetries;

  final String baseUrl;
  final http.Client _client;
  final Duration _timeout;
  final int _maxRetries;
  final _random = Random();

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    // `path` est une URL absolue quand on suit un lien "next" (inutilisé
    // directement par ce SDK -- les sessions de checkout ne sont pas
    // paginées -- mais conservé pour cohérence avec les SDK jumeaux).
    final uri = path.startsWith('http://') || path.startsWith('https://')
        ? Uri.parse(path)
        : Uri.parse('$baseUrl$path').replace(queryParameters: _filterNulls(query));

    final headers = <String, String>{'Accept': 'application/json'};
    String? jsonBody;
    if (body != null) {
      headers['Content-Type'] = 'application/json';
      jsonBody = jsonEncode(body);
    }
    if (idempotencyKey != null) {
      headers['Idempotency-Key'] = idempotencyKey;
    }

    var attempt = 0;
    while (true) {
      try {
        return await _attempt(method, uri, headers, jsonBody);
      } on AlphaPayRateLimitException catch (e) {
        if (attempt >= _maxRetries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: (e.retryAfter ?? 0) > 0 ? e.retryAfter! * 1000 : _backoffMs(attempt)));
        attempt++;
      } on AlphaPayServerException {
        if (attempt >= _maxRetries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: _backoffMs(attempt)));
        attempt++;
      } on AlphaPayConnectionException {
        if (attempt >= _maxRetries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: _backoffMs(attempt)));
        attempt++;
      }
    }
  }

  Future<dynamic> _attempt(String method, Uri uri, Map<String, String> headers, String? body) async {
    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = body;
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException catch (e) {
      throw AlphaPayConnectionException('Requête AlphaPay expirée.', raw: e);
    } catch (e) {
      throw AlphaPayConnectionException("Impossible de joindre l'API AlphaPay : $e", raw: e);
    }

    final requestId = response.headers['x-request-id'];
    dynamic json;
    if (response.body.isNotEmpty) {
      try {
        json = jsonDecode(response.body);
      } on FormatException {
        // Réponse non-JSON (page d'erreur d'un proxy en amont) -- traité
        // comme une absence de corps exploitable ci-dessous.
        json = null;
      }
    }

    if (response.statusCode < 400) {
      if (json is Map && json.containsKey('data')) return json['data'];
      return json;
    }

    final errorBody = (json is Map && json.containsKey('error')) ? json['error'] : json;
    final exception = AlphaPayException.fromResponse(response.statusCode, errorBody, requestId: requestId);
    if (exception is AlphaPayRateLimitException) {
      final retryAfter = response.headers['retry-after'];
      exception.retryAfter = retryAfter != null ? int.tryParse(retryAfter) : null;
    }
    throw exception;
  }

  int _backoffMs(int attempt) {
    // Backoff exponentiel + gigue : 400-600ms, 800-1200ms, 1600-2400ms...
    final base = 400 * pow(2, attempt);
    return (base + _random.nextDouble() * base * 0.5).round();
  }

  Map<String, String>? _filterNulls(Map<String, String>? query) {
    if (query == null) return null;
    return {for (final entry in query.entries) if (entry.value.isNotEmpty) entry.key: entry.value};
  }

  void close() => _client.close();
}
