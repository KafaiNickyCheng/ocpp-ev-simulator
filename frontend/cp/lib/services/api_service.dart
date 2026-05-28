// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {

  String _base(String url) =>
      url.trimRight().replaceAll(RegExp(r'/$'), '');

  // ── Health ──────────────────────────────────────────────────────────────

  Future<bool> healthCheck(String baseUrl) async {
    try {
      final url = Uri.parse('${_base(baseUrl)}/api/health');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) { return false; }
  }

  // ── GET charge point from backend ───────────────────────────────────────

  Future<Map<String, dynamic>?> getChargePointInfo(
      String baseUrl, String cpId) async {
    try {
      final url = Uri.parse(
          '${_base(baseUrl)}/api/chargepoints/${Uri.encodeComponent(cpId)}');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null; // 404 = CP not in DB yet (never booted)
    } catch (_) { return null; }
  }

  // ── PUT update charge point in backend ──────────────────────────────────

  Future<bool> updateChargePointInfo(
    String baseUrl,
    String cpId, {
    required String vendor,
    required String model,
    required String serialNumber,
    required String firmwareVersion,
    required int connectorCount,
  }) async {
    try {
      final url = Uri.parse(
          '${_base(baseUrl)}/api/chargepoints/${Uri.encodeComponent(cpId)}');
      final res = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'vendor':          vendor,
          'model':           model,
          'serialNumber':    serialNumber,
          'firmwareVersion': firmwareVersion,
          'connectorCount':  connectorCount,
        }),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) { return false; }
  }
}