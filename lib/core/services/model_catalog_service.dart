import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/baizi_gateway.dart';
import 'network/dio_http_client.dart';

enum ModelCatalogFailureType {
  unauthorized,
  forbidden,
  server,
  network,
  invalidResponse,
  empty,
}

final class ModelCatalogException implements Exception {
  const ModelCatalogException(this.type, {this.statusCode, this.cause});

  final ModelCatalogFailureType type;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() {
    return 'ModelCatalogException(type: $type, statusCode: $statusCode)';
  }
}

final class ModelCatalogService {
  const ModelCatalogService();

  Future<List<String>> fetchModels({
    required String apiKey,
    http.Client? client,
  }) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      throw const ModelCatalogException(
        ModelCatalogFailureType.unauthorized,
        statusCode: HttpStatus.unauthorized,
      );
    }

    final ownsClient = client == null;
    final effectiveClient = client ?? DioHttpClient();
    try {
      final response = await effectiveClient.get(
        BaiziGateway.modelsUri,
        headers: <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer $normalizedKey',
          HttpHeaders.acceptHeader: 'application/json',
        },
      );

      if (response.statusCode == HttpStatus.unauthorized) {
        throw const ModelCatalogException(
          ModelCatalogFailureType.unauthorized,
          statusCode: HttpStatus.unauthorized,
        );
      }
      if (response.statusCode == HttpStatus.forbidden) {
        throw const ModelCatalogException(
          ModelCatalogFailureType.forbidden,
          statusCode: HttpStatus.forbidden,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ModelCatalogException(
          ModelCatalogFailureType.server,
          statusCode: response.statusCode,
        );
      }

      final dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (error) {
        throw ModelCatalogException(
          ModelCatalogFailureType.invalidResponse,
          statusCode: response.statusCode,
          cause: error,
        );
      }
      if (decoded is! Map || decoded['data'] is! List) {
        throw ModelCatalogException(
          ModelCatalogFailureType.invalidResponse,
          statusCode: response.statusCode,
        );
      }

      final seen = <String>{};
      final models = <String>[];
      for (final item in decoded['data'] as List) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id is! String) continue;
        final normalizedId = id.trim();
        if (normalizedId.isEmpty || !seen.add(normalizedId)) continue;
        models.add(normalizedId);
      }
      if (models.isEmpty) {
        throw const ModelCatalogException(ModelCatalogFailureType.empty);
      }
      return List<String>.unmodifiable(models);
    } on ModelCatalogException {
      rethrow;
    } on http.ClientException catch (error) {
      throw ModelCatalogException(
        ModelCatalogFailureType.network,
        cause: error,
      );
    } on SocketException catch (error) {
      throw ModelCatalogException(
        ModelCatalogFailureType.network,
        cause: error,
      );
    } finally {
      if (ownsClient) effectiveClient.close();
    }
  }
}
