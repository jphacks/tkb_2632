import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/browser_client.dart';

import 'api.dart';
import 'models.dart';

Gateway createGateway() => BrowserGateway();

/// Web版はNodeサーバーと同じオリジンで配信する。
/// HttpOnly Cookieはブラウザが送受信し、Dart側には保存しない。
class BrowserGateway implements Gateway {
  final BrowserClient _client = BrowserClient()..withCredentials = true;
  final Uri origin;
  BrowserGateway({Uri? origin}) : origin = origin ?? Uri.base;

  @override
  Future<Json> request(String route, [Json? data]) async {
    try {
      final uri = origin.resolve('/api/$route');
      final response =
          await (data == null
                  ? _client.get(uri)
                  : _client.post(
                      uri,
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(data),
                    ))
              .timeout(const Duration(seconds: 45));
      final result = jsonDecode(utf8.decode(response.bodyBytes)) as Json;
      if (response.statusCode >= 400) {
        throw ApiException(
          response.statusCode,
          result['error'] as String? ?? '通信に失敗しました',
        );
      }
      return result;
    } on TimeoutException {
      throw const ApiException(0, '通信がタイムアウトしました。接続を確認し、受信履歴を見てから再度お試しください。');
    } on FormatException {
      throw const ApiException(0, 'サーバーの応答を読み取れません。npm startで起動したURLを開いてください。');
    }
  }

  @override
  Future<Uint8List> photo(String roundId, String photoId) async {
    final response = await _client
        .get(origin.resolve('/api/photos/$roundId/$photoId'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const ApiException(0, '写真を読み込めませんでした');
    }
    return response.bodyBytes;
  }

  @override
  void close() => _client.close();
}
