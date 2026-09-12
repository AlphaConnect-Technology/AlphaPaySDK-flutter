import 'dart:convert';

import 'package:alphapay_checkout/alphapay_checkout.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Response _json(Map<String, dynamic> body, {int status = 200, Map<String, String> headers = const {}}) {
  return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});
}

void main() {
  const baseUrl = 'https://api.test/api/v1';

  test('getSession unwraps the envelope and parses the session', () async {
    late Uri calledUri;
    final client = MockClient((request) async {
      calledUri = request.url;
      return _json({
        'success': true,
        'code': 200,
        'data': {
          'slug': 'abc123',
          'merchant_name': 'Boutique Test',
          'amount': '5000.00',
          'currency': 'XOF',
          'status': 'PENDING',
          'is_usable': true,
          'networks': [
            {'code': 'MTN_BJ', 'name': 'MTN Bénin', 'otp_required': false, 'fee': '75.00', 'total': '5075.00', 'currency': 'XOF', 'unavailable': false},
          ],
        },
      });
    });
    final checkout = AlphaPayCheckout(baseUrl: baseUrl, httpClient: client);

    final session = await checkout.getSession('abc123');

    expect(calledUri.toString(), '$baseUrl/checkout/abc123/');
    expect(session.merchantName, 'Boutique Test');
    expect(session.networks, hasLength(1));
    expect(session.networks.first.code, 'MTN_BJ');
    expect(session.networks.first.unavailable, isFalse);
  });

  test('pay() sends the customer/network/otp body and no auth header at all', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return _json({
        'success': true,
        'code': 201,
        'data': {
          'message': 'Paiement initié',
          'transaction_id': 'tx_1',
          'status': 'PENDING',
          'payment_url': '',
          'otp_required': false,
          'instructions': 'Composez #144#',
        },
      });
    });
    final checkout = AlphaPayCheckout(baseUrl: baseUrl, httpClient: client);

    final result = await checkout.pay(
      'abc123',
      network: 'MTN_BJ',
      country: 'BJ',
      customer: const CheckoutCustomer(phone: '+22900000000', firstName: 'Client'),
    );

    expect(result.transactionId, 'tx_1');
    expect(result.paymentUrl, isNull); // "" normalisé en null
    expect(captured.headers.containsKey('Authorization'), isFalse); // JAMAIS de clé secrète ici
    final sentBody = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(sentBody['network'], 'MTN_BJ');
    expect((sentBody['customer'] as Map)['phone'], '+22900000000');
  });

  test('maps a 410 (session no longer usable) to AlphaPaySessionGoneException', () async {
    final client = MockClient((request) async {
      return _json(
        {'success': false, 'code': 410, 'error': {'message': 'Cette session de paiement n\'est plus utilisable.', 'code': 'paid'}},
        status: 410,
      );
    });
    final checkout = AlphaPayCheckout(baseUrl: baseUrl, httpClient: client);

    await expectLater(
      checkout.pay('abc123', network: 'MTN_BJ'),
      throwsA(isA<AlphaPaySessionGoneException>().having((e) => e.errorCode, 'errorCode', 'paid')),
    );
  });

  test('maps a 409 double-submission to AlphaPayConflictException', () async {
    final client = MockClient((request) async {
      return _json(
        {'success': false, 'code': 409, 'error': {'message': 'Un paiement est déjà en cours...', 'code': 'payment_already_pending'}},
        status: 409,
      );
    });
    final checkout = AlphaPayCheckout(baseUrl: baseUrl, httpClient: client);

    await expectLater(
      checkout.pay('abc123', network: 'MTN_BJ'),
      throwsA(isA<AlphaPayConflictException>().having((e) => e.errorCode, 'errorCode', 'payment_already_pending')),
    );
  });

  test('retries a 429 honoring Retry-After, then resolves', () async {
    var attempts = 0;
    final client = MockClient((request) async {
      attempts++;
      if (attempts < 2) {
        return _json({'success': false, 'code': 429, 'error': {'detail': 'Throttled'}}, status: 429, headers: {'retry-after': '0'});
      }
      return _json({'success': true, 'code': 200, 'data': {'slug': 'abc123', 'status': 'PAID', 'amount': '5000', 'currency': 'XOF', 'otp_required': false}});
    });
    final checkout = AlphaPayCheckout(baseUrl: baseUrl, httpClient: client, maxRetries: 2);

    final status = await checkout.getStatus('abc123');

    expect(attempts, 2);
    expect(status.status, 'PAID');
    expect(status.isTerminal, isTrue);
  });

  test('pollStatus emits intermediate PENDING results then stops at a terminal status', () async {
    var attempts = 0;
    final client = MockClient((request) async {
      attempts++;
      final status = attempts < 3 ? 'PENDING' : 'PAID';
      return _json({'success': true, 'code': 200, 'data': {'slug': 'abc123', 'status': status, 'amount': '5000', 'currency': 'XOF', 'otp_required': false}});
    });
    final checkout = AlphaPayCheckout(baseUrl: baseUrl, httpClient: client);

    final results = await checkout.pollStatus('abc123', interval: Duration.zero).toList();

    expect(results.map((r) => r.status).toList(), ['PENDING', 'PENDING', 'PAID']);
    expect(results.last.isTerminal, isTrue);
  });

  test('getPaymentLink parses public options and custom fields', () async {
    final client = MockClient((request) async {
      return _json({
        'success': true,
        'code': 200,
        'data': {
          'name': 'Facture #42',
          'merchant_name': 'Boutique Test',
          'amount_type': 'FIXED',
          'amount': '5000.00',
          'currency': 'XOF',
          'slug': 'demo-slug',
          'is_usable': true,
          'require_phone': false,
          'google_ads_id': 'AW-123456789',
          'custom_fields': [
            {'key': 'reference_client', 'label': 'Référence client', 'required': true},
          ],
        },
      });
    });
    final checkout = AlphaPayCheckout(baseUrl: baseUrl, httpClient: client);

    final link = await checkout.getPaymentLink('demo-slug');

    expect(link.googleAdsId, 'AW-123456789');
    expect(link.customFields, hasLength(1));
    expect(link.customFields.first.key, 'reference_client');
    expect(link.customFields.first.required, isTrue);
  });

  test('createCheckoutFromPaymentLink sends customer/custom fields and no auth header', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return _json({
        'success': true,
        'code': 201,
        'data': {'slug': 'checkout-slug', 'checkout_url': 'https://checkout.example.test/checkout-slug'},
      });
    });
    final checkout = AlphaPayCheckout(baseUrl: baseUrl, httpClient: client);

    final result = await checkout.createCheckoutFromPaymentLink(
      'demo-slug',
      customer: const CheckoutCustomer(email: 'client@example.com', firstName: 'Client', lastName: 'Test'),
      customFieldValues: {'reference_client': 'CMD-42'},
    );

    expect(result.slug, 'checkout-slug');
    expect(captured.headers.containsKey('Authorization'), isFalse);
    final sentBody = jsonDecode(captured.body) as Map<String, dynamic>;
    expect((sentBody['customer'] as Map)['email'], 'client@example.com');
    expect((sentBody['custom_field_values'] as Map)['reference_client'], 'CMD-42');
  });
}
