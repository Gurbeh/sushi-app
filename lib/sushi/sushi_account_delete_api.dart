import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fladder/sushi/sushi_env.dart';

class SushiAccountDeleteException implements Exception {
  SushiAccountDeleteException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Self-service tombstone via POST /me/account/delete.
class SushiAccountDeleteApi {
  SushiAccountDeleteApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> deleteAccount({required String accessToken}) async {
    final base = SushiEnv.apiBaseUrl;
    if (base == null) {
      throw SushiAccountDeleteException('SUSHI_API_BASE_URL is not configured');
    }
    final uri = Uri.parse('$base/me/account/delete');
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'MediaBrowser Token="$accessToken"',
      },
      body: '{}',
    );
    if (response.statusCode == 200) {
      return;
    }
    throw SushiAccountDeleteException(_errorMessage(response));
  }

  String _errorMessage(http.Response response) {
    try {
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final err = map['error'];
      if (err is String && err.isNotEmpty) return err;
    } catch (_) {}
    return 'Could not delete account (${response.statusCode})';
  }
}
