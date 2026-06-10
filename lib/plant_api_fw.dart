import 'dart:convert';
import 'package:http/http.dart' as http;

class PlantApiService {
  static const String baseUrl = 'http://10.16.160.40:80';

  Future<Map<String, dynamic>> fetchPlantData(int plantId) async {
    try {
      print('Sending request to: $baseUrl/get_plant_data');
      print('Plant ID: $plantId');

      final response = await http.post(
        Uri.parse('$baseUrl/get_plant_data'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'plant_id': plantId}),
      ).timeout(Duration(seconds: 5));

      print('Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'status': 'error',
          'message': 'Server error ${response.statusCode}'
        };
      }
    } catch (e) {
      print('Network error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }
}