import 'dart:typed_data';

import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  const ApiException(this.status, this.message);
  @override
  String toString() => message;
}

abstract class Gateway {
  Future<Json> request(String route, [Json? data]);
  Future<Uint8List> photo(String roundId, String photoId);
  void close();
}
