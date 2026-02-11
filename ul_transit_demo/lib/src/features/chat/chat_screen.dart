import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';

import '../../app_shell.dart';
import '../gtfs/gtfs_models.dart';
import '../gtfs/gtfs_providers.dart';
import '../map/map_route_provider.dart';
import '../map/map_route_service.dart';
import '../settings/settings_controller.dart';
import 'chat_notifier.dart';

class TripChatScreen extends ConsumerStatefulWidget {
  const TripChatScreen({super.key});

  @override
  ConsumerState<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends ConsumerState<TripChatScreen> {
  final _controller = TextEditingController();
  Set<int>? _expandedMaps;
  Map<int, Stop>? _selectedDestinations;

  Set<int> get _expandedMapIndexes => _expandedMaps ??= <int>{};
  Map<int, Stop> get _chosenDestinations => _selectedDestinations ??= <int, Stop>{};

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatSessionProvider);
    final config = ref.watch(azureConfigProvider);
    final stopsValue = ref.watch(stopsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chat Trip Planner')),
      body: Column(
        children: [
          if (config.hasValue && !config.value!.isComplete)
            const _ConfigBanner(text: 'Add Azure OpenAI settings to enable live chat.'),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final renderedText = _plainText(msg.text);
                final looksLikeTrip = !msg.isUser && _looksLikeTrip(msg.text);
                MapRouteRequest? routeReq;
                Stop? originStop;
                Stop? destStop;
                if (looksLikeTrip && stopsValue.hasValue) {
                  routeReq = MapRouteRequest.fromText(msg.text);
                  final stops = stopsValue.value!;
                  destStop = _chosenDestinations[index] ?? _matchStop(stops, routeReq.destination);
                  if (routeReq.origin != null) {
                    originStop = _matchStop(stops, routeReq.origin!);
                  }
                  if (kDebugMode) {
                    debugPrint('[chat] msg#$index looksLikeTrip=$looksLikeTrip originRaw="${routeReq.origin}" destRaw="${routeReq.destination}" originMatch=${originStop?.name} destMatch=${destStop?.name}');
                  }
                } else {
                  if (kDebugMode) {
                    debugPrint('[chat] msg#$index skipped trip parse: looksLikeTrip=$looksLikeTrip stopsLoaded=${stopsValue.hasValue}');
                  }
                }

                return Column(
                  crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: msg.isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          renderedText,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: msg.isUser ? FontWeight.w500 : FontWeight.w400,
                              ),
                        ),
                      ),
                    ),
                      if (looksLikeTrip && routeReq != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton.icon(
                              onPressed: destStop == null
                                  ? null
                                  : () {
                                      setState(() {
                                        if (_expandedMapIndexes.contains(index)) {
                                          _expandedMapIndexes.remove(index);
                                        } else {
                                          _expandedMapIndexes.add(index);
                                        }
                                        if (kDebugMode) {
                                          debugPrint('[chat] toggle map for msg#$index expanded=${_expandedMapIndexes.contains(index)}');
                                        }
                                      });
                                    },
                              icon: const Icon(Icons.map_outlined),
                              label: Text(_expandedMapIndexes.contains(index) ? 'Dölj karta' : 'Visa karta här'),
                            ),
                          ),
                        ),
                      if (looksLikeTrip && destStop != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Destination (matchad hållplats): ${destStop!.name}'),
                        ),
                      if (looksLikeTrip && routeReq != null && destStop == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: stopsValue.when(
                            loading: () => const Row(
                              children: [
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 8),
                                Text('Laddar hållplatser...'),
                              ],
                            ),
                            error: (e, _) => Text('Kunde inte ladda hållplatser: $e'),
                            data: (stops) {
                              final q = routeReq!.destination;
                              return _DestinationPicker(
                                query: q,
                                stops: stops,
                                onSelect: (stop) => setState(() {
                                  _chosenDestinations[index] = stop;
                                  if (kDebugMode) debugPrint('[chat] user selected destination for msg#$index -> ${stop.name}');
                                }),
                              );
                            },
                          ),
                        ),
                      if (looksLikeTrip && routeReq != null && destStop != null && _expandedMapIndexes.contains(index))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _InlineRouteMap(routeReq: routeReq!, origin: originStop, destination: destStop!),
                        ),
                    ],
                );
              },
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(labelText: 'Where do you want to go?'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(chatSessionProvider.notifier).send(text);
    _controller.clear();
  }
}

bool _looksLikeTrip(String text) {
  final lower = text.toLowerCase();
  return lower.contains(' till ') ||
      lower.contains('till ') ||
      lower.contains(' från ') ||
      lower.contains('från ') ||
      lower.contains('destination') ||
      lower.contains('destin');
}

String _plainText(String text) {
  var cleaned = text.replaceAll(RegExp(r'[\*`_]'), '');
  cleaned = cleaned.replaceAll(RegExp(r'^\s*-\s+', multiLine: true), '• ');
  cleaned = cleaned.replaceAll(RegExp(r'^\s*\+\s+', multiLine: true), '• ');
  cleaned = cleaned.replaceAll(RegExp(r'^\s*Nästa åtgärd:.*$', multiLine: true), '');
  cleaned = cleaned.replaceAll(RegExp(r'\r?\n\s*\r?\n'), '\n');
  return cleaned.trim();
}

class _InlineRouteMap extends ConsumerWidget {
  const _InlineRouteMap({required this.routeReq, required this.origin, required this.destination});
  final MapRouteRequest routeReq;
  final Stop? origin;
  final Stop destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final originPoint = origin != null ? LatLng(origin!.lat, origin!.lon) : null;
    final destPoint = LatLng(destination.lat, destination.lon);
    if (originPoint == null) {
      return const Text('Kunde inte matcha avresehållplats.');
    }

    final query = RouteQuery(origin: originPoint, destination: destPoint);
    final legs = ref.watch(mapRouteLegsProvider(query));

    return SizedBox(
      height: 220,
      child: Card(
        margin: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: legs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Rutt kunde inte beräknas: $e'),
            ),
            data: (items) {
              final polylines = items
                  .map(
                    (leg) => Polyline(
                      points: leg.points,
                      color: leg.isWalk ? Colors.blueGrey : Colors.orange,
                      strokeWidth: leg.isWalk ? 3 : 4,
                      strokeCap: StrokeCap.round,
                    ),
                  )
                  .toList();
              final markers = <Marker>[
                Marker(
                  point: destPoint,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.flag, color: Colors.red, size: 32),
                ),
                Marker(
                  point: originPoint,
                  width: 32,
                  height: 32,
                  child: const Icon(Icons.circle, color: Colors.green, size: 24),
                ),
              ];

              final center = LatLng(
                (originPoint.latitude + destPoint.latitude) / 2,
                (originPoint.longitude + destPoint.longitude) / 2,
              );

              return FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 13),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.ul.demo',
                  ),
                  PolylineLayer(polylines: polylines),
                  MarkerLayer(markers: markers),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DestinationPicker extends StatelessWidget {
  const _DestinationPicker({required this.query, required this.stops, required this.onSelect});
  final String query;
  final List<Stop> stops;
  final ValueChanged<Stop> onSelect;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) debugPrint('[dest] picker query="$query" stops=${stops.length}');
    final baseCandidates = _findCandidates(stops, query);

    return FutureBuilder<List<Stop>>(
      future: _searchStopsByArea(query, stops),
      builder: (context, snapshot) {
        final geoCandidates = snapshot.data ?? const <Stop>[];
        final candidates = geoCandidates.isNotEmpty ? geoCandidates : baseCandidates;

        if (snapshot.hasError && candidates.isEmpty) {
          return Text('Kunde inte hitta område för destinationen. (${snapshot.error})');
        }
        if (snapshot.connectionState == ConnectionState.waiting && candidates.isEmpty) {
          return const Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Hittar hållplatser i området...'),
            ],
          );
        }
        if (candidates.isEmpty) {
          return const Text('Kunde inte matcha destination mot hållplatser.');
        }

        final label = geoCandidates.isNotEmpty
            ? 'Välj destination i området (OpenStreetMap):'
            : 'Välj destination bland förslag:';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: candidates
                  .map(
                    (stop) => ActionChip(
                      label: Text(stop.name),
                      onPressed: () => onSelect(stop),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
    );
  }
}

List<Stop> _findCandidates(List<Stop> stops, String query) {
  final q = _normalize(query);
  if (q.isEmpty) return [];
  final contains = stops.where((s) => _normalize(s.name).contains(q)).toList();
  if (kDebugMode) debugPrint('[dest] contains-match query="$query" -> ${contains.length}');
  if (contains.isNotEmpty) return contains.take(6).toList();
  // fallback: startsWith
  final starts = stops.where((s) => _normalize(s.name).startsWith(q)).toList();
  if (kDebugMode) debugPrint('[dest] startswith-match query="$query" -> ${starts.length}');
  if (starts.isNotEmpty) return starts.take(6).toList();
  // No fallback: if we can't match, return empty so we don't show unrelated stops.
  if (kDebugMode) debugPrint('[dest] no match for "$query"');
  return [];
}

class _ConfigBanner extends StatelessWidget {
  const _ConfigBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

Stop? _matchStop(List<Stop> stops, String query) {
  final cleaned = _normalize(query);
  for (final s in stops) {
    final name = _normalize(s.name);
    if (name.contains(cleaned) || cleaned.contains(name)) return s;
  }
  return null;
}

String _normalize(String input) {
  final lower = input.toLowerCase();
  final stripped = lower.replaceAll(RegExp(r'[^a-z0-9åäöé\s]'), '');
  return stripped.trim();
}

final Distance _distance = const Distance();

bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].longitude, yi = polygon[i].latitude;
    final xj = polygon[j].longitude, yj = polygon[j].latitude;
    final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude < (xj - xi) * (point.latitude - yi) / ((yj - yi) != 0 ? (yj - yi) : 1e-9) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

List<LatLng>? _extractPolygon(Map<String, dynamic> geojson) {
  final type = (geojson['type'] ?? '').toString().toLowerCase();
  if (type == 'polygon') {
    final coords = geojson['coordinates'] as List<dynamic>?;
    if (coords == null || coords.isEmpty) return null;
    final ring = coords.first as List<dynamic>;
    return ring
        .map<LatLng>((p) {
      final list = p as List<dynamic>;
      final lat = (list[1] as num).toDouble();
      final lon = (list[0] as num).toDouble();
      return LatLng(lat, lon);
    })
        .toList();
  }
  if (type == 'multipolygon') {
    final polys = geojson['coordinates'] as List<dynamic>?;
    if (polys == null || polys.isEmpty) return null;
    final ring = (polys.first as List<dynamic>).first as List<dynamic>;
    return ring
        .map<LatLng>((p) {
      final list = p as List<dynamic>;
      final lat = (list[1] as num).toDouble();
      final lon = (list[0] as num).toDouble();
      return LatLng(lat, lon);
    })
        .toList();
  }
  return null;
}

class GeoArea {
  const GeoArea({
    required this.south,
    required this.north,
    required this.west,
    required this.east,
    required this.center,
    this.radiusMeters,
    this.polygon,
  });
  final double south;
  final double north;
  final double west;
  final double east;
  final LatLng center;
  final double? radiusMeters;
  final List<LatLng>? polygon; // Optional polygon boundary for better containment.

  bool contains(Stop stop) {
    // If polygon provided, prefer polygon containment first.
    if (polygon != null && polygon!.length >= 3) {
      if (_pointInPolygon(LatLng(stop.lat, stop.lon), polygon!)) return true;
    }

    final insideBox = stop.lat >= south && stop.lat <= north && stop.lon >= west && stop.lon <= east;
    if (radiusMeters == null) return insideBox;
    final d = _distance(center, LatLng(stop.lat, stop.lon));
    return insideBox && d <= radiusMeters!;
  }
}

typedef GeocodeFn = Future<GeoArea?> Function(String query);

@visibleForTesting
Future<List<Stop>> searchStopsByAreaForTest(String query, List<Stop> stops, {GeocodeFn? geocodeFn}) {
  return _searchStopsByArea(query, stops, geocodeFn: geocodeFn);
}

const _knownAreas = <String, GeoArea>{
  // Hand-tuned Flogsta area with a radius gate to avoid missing nearby stops.
  'flogsta': GeoArea(
    south: 59.8425,
    north: 59.8520,
    west: 17.5805,
    east: 17.6005,
    center: LatLng(59.8469, 17.5899),
    radiusMeters: 1500,
  ),
  // Common typo of Flogsta.
  'flogsat': GeoArea(
    south: 59.8425,
    north: 59.8520,
    west: 17.5805,
    east: 17.6005,
    center: LatLng(59.8469, 17.5899),
    radiusMeters: 1500,
  ),
};

Future<List<Stop>> _searchStopsByArea(String query, List<Stop> stops, {GeocodeFn? geocodeFn}) async {
  if (_normalize(query).length < 3) return const [];
  final geocode = geocodeFn ?? _geocodeArea;
  final area = await geocode(query);
  if (area == null) return const [];

  final inside = stops.where(area.contains).toList();
  if (kDebugMode) debugPrint('[geo] area "$query" bbox=(${area.south},${area.north},${area.west},${area.east}) inside=${inside.length}');
  inside.sort((a, b) {
    final da = _distance(area.center, LatLng(a.lat, a.lon));
    final db = _distance(area.center, LatLng(b.lat, b.lon));
    return da.compareTo(db);
  });

  if (inside.isNotEmpty) return inside.take(10).toList();

  if (kDebugMode) debugPrint('[geo] area "$query" no inside stops; returning empty (no fallback)');
  return const [];
}

Future<GeoArea?> _geocodeArea(String query) async {
  final normalized = _normalize(query);
  final alias = _knownAreas[normalized];
  if (alias != null) {
    if (kDebugMode) debugPrint('[geo] alias hit for "$query" -> flogsta bbox');
    return alias;
  }

  final trimmed = query.trim();
  final preferred = trimmed.length < 40 ? '$trimmed, Uppsala, Sweden' : trimmed;
  final queries = <String>{preferred, trimmed};

  for (final q in queries) {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?format=json&polygon_geojson=1&limit=1&q=${Uri.encodeComponent(q)}',
    );
    if (kDebugMode) debugPrint('[geo] lookup "$q" -> $url');
    final resp = await http.get(url, headers: {'User-Agent': 'ul-transit-demo/1.0'});
    if (resp.statusCode >= 300) {
      if (kDebugMode) debugPrint('[geo] $q status=${resp.statusCode} body=${resp.body}');
      continue;
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    if (kDebugMode) debugPrint('[geo] $q results=${data.length}');
    if (data.isEmpty) continue;
  final first = data.first as Map<String, dynamic>;
  final bbox = first['boundingbox'] as List<dynamic>?;
  final lat = double.tryParse(first['lat']?.toString() ?? '');
  final lon = double.tryParse(first['lon']?.toString() ?? '');
  final geojson = first['geojson'];
  if (bbox == null || bbox.length < 4 || lat == null || lon == null) return null;

  final south = double.tryParse(bbox[0].toString());
  final north = double.tryParse(bbox[1].toString());
  final west = double.tryParse(bbox[2].toString());
  final east = double.tryParse(bbox[3].toString());
  if (south == null || north == null || west == null || east == null) return null;

    // Estimate a conservative radius from the bbox diagonal to allow slight geocode imprecision.
    final diagMeters = _distance(LatLng(south, west), LatLng(north, east));
    final radiusMeters = (diagMeters / 2).clamp(300.0, 3000.0);

    if (kDebugMode) debugPrint('[geo] bbox south=$south north=$north west=$west east=$east center=($lat,$lon) radius~${radiusMeters.toStringAsFixed(0)}m');

    List<LatLng>? polygon;
    if (geojson is Map<String, dynamic>) {
      polygon = _extractPolygon(geojson);
      if (kDebugMode && polygon != null) debugPrint('[geo] polygon points=${polygon.length}');
    }

    return GeoArea(
      south: south,
      north: north,
      west: west,
      east: east,
      center: LatLng(lat, lon),
      radiusMeters: radiusMeters,
      polygon: polygon,
    );
  }

  return null;
}
