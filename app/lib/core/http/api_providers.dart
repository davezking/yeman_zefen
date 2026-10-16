import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import 'api_client.dart';

/// The authenticated client for the API Worker.
final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authServiceProvider);
  final client = ApiClient(baseUrl: AppConfig.apiBase, idToken: auth.idToken);
  ref.onDispose(client.close);
  return client;
});
