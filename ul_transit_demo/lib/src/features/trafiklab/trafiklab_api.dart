import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'trafiklab_models.dart';

/// Minimal TrafikLab HTTP client scaffold.
/// Reads API key from constructor (or environment via providers).
class TrafikLabApi {
  TrafikLabApi(this._http, this.apiKey, {this.baseUrl = 'https://api.trafiklab.se'});

  final http.Client _http;
  final String apiKey;
  final String baseUrl;

  Uri _build(String path, [Map<String, String>? query]) {
    final q = <String, String>{'key': apiKey};
    if (query != null) q.addAll(query);
    return Uri.parse(baseUrl).replace(path: path, queryParameters: q);
  }

  /// Search stops by text. The exact TrafikLab endpoint/parameters will depend
  /// on the selected TrafikLab API; this is a simple scaffold.
  Future<List<Stop>> searchStops(String text) async {
    // Placeholder path: override baseUrl or update to the real endpoint.
    final uri = Uri.parse('$baseUrl/v2/stops?key=$apiKey&search=${Uri.encodeQueryComponent(text)}');
    final resp = await _http.get(uri);
    if (resp.statusCode >= 300) throw Exception('TrafikLab searchStops error ${resp.statusCode}: ${resp.body}');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = (json['stops'] as List<dynamic>?) ?? (json['ResponseData'] as List<dynamic>?) ?? [];
    return raw.map((e) => Stop.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Departure>> departuresForStop(String stopId) async {
    final uri = Uri.parse('$baseUrl/v2/departures?key=$apiKey&stopId=$stopId');
    final resp = await _http.get(uri);
    if (resp.statusCode >= 300) throw Exception('TrafikLab departures error ${resp.statusCode}: ${resp.body}');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = (json['departures'] as List<dynamic>?) ?? [];
    return raw.map((e) => Departure.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<TripPlan> planTrip(LatLng origin, LatLng destination) async {
    final uri = Uri.parse('$baseUrl/v2/trip?key=$apiKey'
        '&origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}');
    final resp = await _http.get(uri);
    if (resp.statusCode >= 300) throw Exception('TrafikLab trip error ${resp.statusCode}: ${resp.body}');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    // Parse using TripPlan.fromJson if the shape matches; otherwise adapt later.
    return TripPlan.fromJson(json);
  }
}
