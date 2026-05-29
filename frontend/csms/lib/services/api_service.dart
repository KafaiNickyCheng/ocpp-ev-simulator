// lib/services/api_service.dart
// Handles REST API calls to the backend for data that doesn't need real-time push.
// Used for: tag management, transaction history, message logs.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/csms_models.dart';

class ApiService {
  String _baseUrl = 'https://ocpp-ev-api.up.railway.app';

  void setBaseUrl(String url) {
    _baseUrl = url.trimRight().replaceAll(RegExp(r'/$'), '');
  }

  // ─── IdTag CRUD ──────────────────────────────────────────────────────────

  Future<List<IdTagModel>> getTags() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/tags'));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        return list.map((j) => IdTagModel.fromJson(j as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('[API] getTags failed: $e');
    }
    return [];
  }

  Future<bool> createTag({
    required String tagId,
    String? userName,
    String? note,
    DateTime? expiryDate,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/tags'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tagId': tagId,
          'userName': userName,
          'note': note,
          'expiryDate': expiryDate?.toIso8601String(),
        }),
      );
      return res.statusCode == 201;
    } catch (e) {
      debugPrint('[API] createTag failed: $e');
      return false;
    }
  }

  Future<bool> updateTagStatus(String tagId, String status) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/api/tags/$tagId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[API] updateTagStatus failed: $e');
      return false;
    }
  }

  Future<bool> deleteTag(String tagId) async {
    try {
      final res = await http.delete(Uri.parse('$_baseUrl/api/tags/$tagId'));
      return res.statusCode == 204;
    } catch (e) {
      debugPrint('[API] deleteTag failed: $e');
      return false;
    }
  }

  // ─── Transactions ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getTransactions({
    String? cpId,
    String? idTag,
    String? status,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final params = {
        if (cpId != null) 'cpId': cpId,
        if (idTag != null) 'idTag': idTag,
        if (status != null) 'status': status,
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      final uri = Uri.parse('$_baseUrl/api/transactions').replace(queryParameters: params);
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[API] getTransactions failed: $e');
    }
    return {'items': [], 'total': 0};
  }

  Future<Map<String, dynamic>?> getTransactionDetail(int txId) async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/transactions/$txId'));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[API] getTransactionDetail failed: $e');
    }
    return null;
  }

  // ─── Message Logs ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getLogs({String? cpId, int page = 1, int pageSize = 50}) async {
    try {
      final params = {
        if (cpId != null) 'cpId': cpId,
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      final uri = Uri.parse('$_baseUrl/api/logs').replace(queryParameters: params);
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[API] getLogs failed: $e');
    }
    return {'items': [], 'total': 0};
  }

  // ─── Health check ────────────────────────────────────────────────────────

  Future<bool> healthCheck(String url) async {
    try {
      final base = url.trimRight().replaceAll(RegExp(r'/$'), '');
      final res = await http.get(Uri.parse('$base/api/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
