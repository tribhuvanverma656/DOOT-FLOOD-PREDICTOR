import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Live Render Backend Base URL
  static const String baseUrl = 'https://doot-flood-predictor.onrender.com';

  /// Live LightGBM ML Model se Flood Risk Fetch karta hai
  static Future<Map<String, dynamic>> predictFloodRisk(List<double> features) async {
    final uri = Uri.parse('$baseUrl/predict');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'features': features}),
      ).timeout(const Duration(seconds: 40));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'prediction': data['prediction'] ?? 0,
          'probability': (data['probability'] as num?)?.toDouble() ?? 0.0,
          'raw': data,
        };
      } else {
        return {
          'success': false,
          'error': 'Server Error (${response.statusCode})',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection Error: $e',
      };
    }
  }
}