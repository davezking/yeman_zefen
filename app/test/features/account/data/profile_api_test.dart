import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeman_zefen/core/http/api_client.dart';
import 'package:yeman_zefen/features/account/data/profile_api.dart';
import 'package:yeman_zefen/features/account/ui/register_sheet.dart';
import 'package:yeman_zefen/prototype/models.dart';

Future<String?> _token({bool forceRefresh = false}) async => 'token';

void main() {
  group('nameLengthError', () {
    test('a name needs at least 2 characters after trimming', () {
      expect(nameLengthError(' a '), NameError.tooShort);
      expect(nameLengthError(''), NameError.tooShort);
      expect(nameLengthError(' ab '), NameError.none);
    });

    test('counts characters, not UTF-16 units (an Amharic letter is one)', () {
      expect(nameLengthError('ሰላም'), NameError.none);
      expect(nameLengthError('ሰ'), NameError.tooShort);
    });
  });

  group('nameErrorFor', () {
    test('name_taken shows the taken message', () {
      const e = RequestException('name_taken', 'taken', status: 409);

      expect(nameErrorFor(e), NameError.taken);
    });

    test('any other failure is not the name\'s fault', () {
      const network = NetworkException('offline');
      const server = ServerException('internal', 'boom', status: 500);

      expect(nameErrorFor(network), NameError.none);
      expect(nameErrorFor(server), NameError.none);
    });
  });

  group('saveDisplayName', () {
    test('sends PUT /v1/me with the name', () async {
      late http.Request sent;
      final api = ApiClient(
        baseUrl: 'https://api.test',
        idToken: _token,
        client: MockClient((req) async {
          sent = req;
          return http.Response(
            jsonEncode({'displayName': 'Selam'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await saveDisplayName(api, 'Selam');

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/v1/me');
      expect(jsonDecode(sent.body), {'displayName': 'Selam'});
    });
  });

  group('emailErrorFor', () {
    test('maps Firebase codes to the two email messages', () {
      expect(emailErrorFor('invalid-email'), EmailError.email);
      expect(emailErrorFor('weak-password'), EmailError.password);
      expect(emailErrorFor('wrong-password'), EmailError.password);
      expect(emailErrorFor('invalid-credential'), EmailError.password);
      expect(emailErrorFor('something-else'), EmailError.none);
    });
  });
}
