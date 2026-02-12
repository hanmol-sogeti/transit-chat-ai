import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';
import 'package:geolocator/geolocator.dart';

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
  Map<int, Stop>? _selectedOrigins;
  Map<int, Future<Stop?>?>? _originResolveFutures;
  Map<int, Future<Stop?>?>? _destResolveFutures;

  Set<int> get _expandedMapIndexes => _expandedMaps ??= <int>{};
  Map<int, Stop> get _chosenDestinations => _selectedDestinations ??= <int, Stop>{};
  Map<int, Stop> get _chosenOrigins => _selectedOrigins ??= <int, Stop>{};

  @override
  void initState() {
    super.initState();
    _originResolveFutures ??= <int, Future<Stop?>?>{};
    _destResolveFutures ??= <int, Future<Stop?>?>{};
  }

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
                  // Prefer a user-chosen origin override when present for this message.
                  originStop = _chosenOrigins[index] ?? originStop;
                  if (kDebugMode) {
                    debugPrint('[chat] msg#$index looksLikeTrip=$looksLikeTrip originRaw="${routeReq.origin}" destRaw="${routeReq.destination}" originMatch=${originStop?.name} destMatch=${destStop?.name}');
                  }
                } else {
                  if (kDebugMode) {
                    debugPrint('[chat] msg#$index skipped trip parse: looksLikeTrip=$looksLikeTrip stopsLoaded=${stopsValue.hasValue}');
                  }
                }

                final displayText = (!msg.isUser && looksLikeTrip && routeReq != null) ? 'Här är din reseplan' : renderedText;

                return Column(
                  key: ValueKey(msg.id),
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
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                                SelectableText(
                              displayText,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: (!msg.isUser && looksLikeTrip)
                                    ? FontWeight.bold
                                    : (msg.isUser ? FontWeight.w500 : FontWeight.w400),
                                  ),
                                ),
                            if (looksLikeTrip && routeReq != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: stopsValue.when(
                                  loading: () => const Row(
                                    children: [
                                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                      SizedBox(width: 8),
                                      SelectableText('Laddar hållplatser...'),
                                    ],
                                  ),
                                  error: (e, _) => SelectableText('Kunde inte ladda hållplatser: $e'),
                                  data: (stops) {
                                    // Build origin candidates future
                                    Future<List<Stop>> originFuture() async {
                                      final q = routeReq!.origin ?? '';
                                      if (q.isEmpty || q.toLowerCase().contains('avrese')) {
                                        try {
                                          final permission = await Geolocator.checkPermission();
                                          if (permission == LocationPermission.denied) await Geolocator.requestPermission();
                                          final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
                                          final user = LatLng(pos.latitude, pos.longitude);
                                          final repo = ref.read(gtfsRepositoryProvider);
                                          final nearest = await repo.nearestStops(user, limit: 6);
                                          if (nearest.isNotEmpty) return nearest;
                                        } catch (_) {}
                                        return _findCandidates(stops, q);
                                      }
                                      final geoCandidates = await _searchStopsByArea(q, stops);
                                      return geoCandidates.isNotEmpty ? geoCandidates : _findCandidates(stops, q);
                                    }

                                    Future<List<Stop>> destFuture() async {
                                      final q = routeReq!.destination;
                                      final geoCandidates = await _searchStopsByArea(q, stops);
                                      return geoCandidates.isNotEmpty ? geoCandidates : _findCandidates(stops, q);
                                    }

                                    return FutureBuilder<List<List<Stop>>>(
                                      future: Future.wait([originFuture(), destFuture()]),
                                      builder: (context, snap) {
                                        if (snap.connectionState == ConnectionState.waiting) {
                                          return const Row(
                                            children: [
                                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                              SizedBox(width: 8),
                                              SelectableText('Söker förslag på hållplatser...'),
                                            ],
                                          );
                                        }
                                        final lists = snap.data ?? [<Stop>[], <Stop>[]];
                                        final originCandidates = lists[0];
                                        final destCandidates = lists[1];

                                        final originSelected = _chosenOrigins[index] ?? (originStop ?? (originCandidates.isNotEmpty ? originCandidates.first : null));
                                        final destSelected = _chosenDestinations[index] ?? (destStop ?? (destCandidates.isNotEmpty ? destCandidates.first : null));
                                        final Stop? _destForMap = destSelected ?? destStop;

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox.shrink(),
                                            const SizedBox(height: 6),
                                            SelectableText('Ursprung:'),
                                            const SizedBox(height: 4),
                                            if (originCandidates.length > 1) ...[
                                              DropdownButton<Stop>(
                                                value: originSelected,
                                                items: originCandidates
                                                    .map((s) => DropdownMenuItem<Stop>(value: s, child: SelectableText(s.name)))
                                                    .toList(),
                                                onChanged: (s) => setState(() {
                                                  if (s != null) _chosenOrigins[index] = s;
                                                }),
                                              ),
                                            ] else if (originSelected != null) ...[
                                              SelectableText('Föreslagen avgångsplats: ${originSelected.name}'),
                                            ] else ...[
                                              FutureBuilder<Stop?>(
                                                future: (_originResolveFutures ??= {})[index] ??= resolveOriginStop(ref, routeReq!),
                                                builder: (context, snapOrigin) {
                                                  if (snapOrigin.connectionState == ConnectionState.waiting) {
                                                    return const Row(
                                                      children: [
                                                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                                        SizedBox(width: 8),
                                                        SelectableText('Söker avgångsplats...'),
                                                      ],
                                                    );
                                                  }
                                                  final resolved = snapOrigin.data;
                                                  if (resolved != null) {
                                                    // Cache the resolved origin as chosen default for this message
                                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                                      if (!_chosenOrigins.containsKey(index)) {
                                                        setState(() {
                                                          _chosenOrigins[index] = resolved;
                                                        });
                                                      }
                                                    });
                                                    return SelectableText('Föreslagen avgångsplats: ${resolved.name}');
                                                  }
                                                  return const SelectableText('Föreslagen avgångsplats: (ingen hittad)');
                                                },
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            SelectableText('Destination:'),
                                            const SizedBox(height: 4),
                                            if (destCandidates.length > 1) ...[
                                              DropdownButton<Stop>(
                                                value: destSelected,
                                                items: destCandidates
                                                    .map((s) => DropdownMenuItem<Stop>(value: s, child: SelectableText(s.name)))
                                                    .toList(),
                                                onChanged: (s) => setState(() {
                                                  if (s != null) _chosenDestinations[index] = s;
                                                }),
                                              ),
                                            ] else if (destSelected != null) ...[
                                              SelectableText('Föreslagen destinations plats: ${destSelected.name}'),
                                            ] else ...[
                                              FutureBuilder<Stop?>(
                                                future: (_destResolveFutures ??= {})[index] ??= () async {
                                                  final q = routeReq!.destination;
                                                  try {
                                                    final stops = await ref.read(stopsProvider.future);
                                                    final geoCandidates = await _searchStopsByArea(q, stops);
                                                    if (geoCandidates.isNotEmpty) return geoCandidates.first;
                                                    final base = _findCandidates(stops, q);
                                                    if (base.isNotEmpty) return base.first;
                                                    final geo = await _geocodeArea(q);
                                                    if (geo != null) {
                                                      final repo = ref.read(gtfsRepositoryProvider);
                                                      final nearest = await repo.nearestStops(geo.center, limit: 1);
                                                      if (nearest.isNotEmpty) return nearest.first;
                                                    }
                                                  } catch (_) {}
                                                  return null;
                                                }(),
                                                builder: (context, snapDest) {
                                                  if (snapDest.connectionState == ConnectionState.waiting) {
                                                    return const Row(
                                                      children: [
                                                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                                        SizedBox(width: 8),
                                                        SelectableText('Söker destinationsplats...'),
                                                      ],
                                                    );
                                                  }
                                                  final resolved = snapDest.data;
                                                  if (resolved != null) {
                                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                                      if (!_chosenDestinations.containsKey(index)) {
                                                        setState(() {
                                                          _chosenDestinations[index] = resolved;
                                                        });
                                                      }
                                                    });
                                                    return SelectableText('Föreslagen destinations plats: ${resolved.name}');
                                                  }
                                                  return const SelectableText('Föreslagen destinations plats: (ingen hittad)');
                                                },
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            const SelectableText('Avgångstid: Nu'),
                                            const SizedBox(height: 8),
                                            Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: ElevatedButton.icon(
                                                  onPressed: _destForMap == null
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
                                                  label: SelectableText(_expandedMapIndexes.contains(index) ? 'Dölj karta' : 'Visa karta här'),
                                                ),
                                              ),
                                            ),
                                            // Inline route map (shows dropdown for route alternatives and renders the selected route)
                                            if (_expandedMapIndexes.contains(index) && _destForMap != null)
                                              _InlineRouteMap(
                                                routeReq: routeReq!,
                                                origin: originSelected,
                                                destination: _destForMap,
                                                originResolveFuture: (_originResolveFutures ??= {})[index] ??= resolveOriginStop(ref, routeReq!),
                                              ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
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

class _InlineRouteMap extends ConsumerStatefulWidget {
  const _InlineRouteMap({required this.routeReq, required this.origin, required this.destination, this.originResolveFuture});
  final MapRouteRequest routeReq;
  final Stop? origin;
  final Stop destination;
  final Future<Stop?>? originResolveFuture;

  @override
  ConsumerState<_InlineRouteMap> createState() => _InlineRouteMapState();
}

class _InlineRouteMapState extends ConsumerState<_InlineRouteMap> {
  int? _selectedAlternative;

  @override
  Widget build(BuildContext context) {
    final originPoint = widget.origin != null ? LatLng(widget.origin!.lat, widget.origin!.lon) : null;
    final destPoint = LatLng(widget.destination.lat, widget.destination.lon);

    if (originPoint == null) {
      return FutureBuilder<Map<String, dynamic>>(
        future: () async {
          final resolved = await (widget.originResolveFuture ?? resolveOriginStop(ref, widget.routeReq));
          if (resolved == null) return {'resolved': null};
          final resolvedPoint = LatLng(resolved.lat, resolved.lon);
          final alternatives = await _fetchRouteAlternatives(resolvedPoint, destPoint);
          return {'resolved': resolved, 'alternatives': alternatives};
        }(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), SelectableText('Söker avresehållplats...')]);
          }
          final data = snap.data;
          if (data == null || data['resolved'] == null) return const Text('Kunde inte matcha avresehållplats.');
          final resolved = data['resolved'] as Stop;
          final alternatives = (data['alternatives'] as List<Map<String, dynamic>>?) ?? [];

          if (_selectedAlternative == null && alternatives.isNotEmpty) {
            int best = 0;
            double bestDur = double.infinity;
            for (var i = 0; i < alternatives.length; i++) {
              final d = (alternatives[i]['duration'] as num?)?.toDouble() ?? double.infinity;
              if (d < bestDur) {
                bestDur = d;
                best = i;
              }
            }
            _selectedAlternative = best;
          }

          final resolvedPoint = LatLng(resolved.lat, resolved.lon);
          final points = (alternatives.isNotEmpty && _selectedAlternative != null) ? alternatives[_selectedAlternative!]['points'] as List<LatLng> : <LatLng>[];
          final asyncLegs = AsyncValue<List<MapRouteLeg>>.data(points.isNotEmpty ? [MapRouteLeg(mode: 'BUS', points: points)] : []);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (alternatives.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const SelectableText('Förslag på linje/rutt:'),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: _selectedAlternative,
                        items: alternatives
                            .asMap()
                            .entries
                            .map((e) => DropdownMenuItem<int>(
                                  value: e.key,
                                  child: SelectableText('Förslag ${e.key + 1} — ${_formatDuration(e.value['duration'])}'),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedAlternative = v),
                      ),
                    ],
                  ),
                ),
              ],
              _buildRouteMap(context, ref, asyncLegs, resolvedPoint, destPoint),
            ],
          );
        },
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchRouteAlternatives(originPoint, destPoint),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final alternatives = snap.data ?? [];
        if (_selectedAlternative == null && alternatives.isNotEmpty) {
          int best = 0;
          double bestDur = double.infinity;
          for (var i = 0; i < alternatives.length; i++) {
            final d = (alternatives[i]['duration'] as num?)?.toDouble() ?? double.infinity;
            if (d < bestDur) {
              bestDur = d;
              best = i;
            }
          }
          _selectedAlternative = best;
        }
        final points = (alternatives.isNotEmpty && _selectedAlternative != null) ? alternatives[_selectedAlternative!]['points'] as List<LatLng> : <LatLng>[];
        final asyncLegs = AsyncValue<List<MapRouteLeg>>.data(points.isNotEmpty ? [MapRouteLeg(mode: 'BUS', points: points)] : []);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alternatives.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Text('Förslag på linje/rutt:'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: _selectedAlternative,
                      items: alternatives
                          .asMap()
                          .entries
                          .map((e) => DropdownMenuItem<int>(
                                value: e.key,
                                child: Text('Förslag ${e.key + 1} — ${_formatDuration(e.value['duration'])}'),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedAlternative = v),
                    ),
                  ],
                ),
              ),
            _buildRouteMap(context, ref, asyncLegs, originPoint, destPoint),
          ],
        );
      },
    );
  }

  String _formatDuration(dynamic seconds) {
    if (seconds == null) return '-';
    final s = (seconds as num).toInt();
    final mins = (s / 60).round();
    if (mins < 60) return '${mins} min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h} h' : '${h} h ${m} min';
  }

  Future<List<Map<String, dynamic>>> _fetchRouteAlternatives(LatLng originPoint, LatLng destPoint) async {
    final url = 'https://router.project-osrm.org/route/v1/driving/${originPoint.longitude},${originPoint.latitude};${destPoint.longitude},${destPoint.latitude}?overview=full&geometries=geojson&alternatives=true';
    final uri = Uri.parse(url);
    final resp = await http.get(uri);
    if (resp.statusCode >= 300) throw Exception('OSRM failed ${resp.statusCode}: ${resp.body}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final routes = (data['routes'] as List<dynamic>? ?? []);
    final out = <Map<String, dynamic>>[];
    for (final r in routes) {
      final route = r as Map<String, dynamic>;
      final geom = route['geometry'] as Map<String, dynamic>?;
      final coords = (geom?['coordinates'] as List<dynamic>? ?? [])
          .map((p) => LatLng((p as List)[1] as double, (p)[0] as double))
          .toList();
      final duration = (route['duration'] as num?)?.toDouble();
      final distance = (route['distance'] as num?)?.toDouble();
      if (coords.length >= 2) {
        out.add({'points': coords, 'duration': duration, 'distance': distance});
      }
    }
    return out;
  }

  Widget _buildRouteMap(BuildContext context, WidgetRef ref, AsyncValue<List<MapRouteLeg>> legs, LatLng originPoint, LatLng destPoint) {
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
                    (MapRouteLeg leg) => Polyline(
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

Future<Stop?> resolveOriginStop(WidgetRef ref, MapRouteRequest routeReq) async {
  final originText = routeReq.origin?.toLowerCase() ?? '';
  try {
    if (kDebugMode) debugPrint('[resolve] originText="$originText"');
    // If the origin text mentions avrese/avresehållplats, treat as "nearest to user".
    if (originText.contains('avrese') || originText.contains('avresehållplats')) {
      try {
        if (kDebugMode) debugPrint('[resolve] detected avrese token, attempting device geolocation');
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) await Geolocator.requestPermission();
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        final user = LatLng(pos.latitude, pos.longitude);
        final repo = ref.read(gtfsRepositoryProvider);
        final nearest = await repo.nearestStops(user, limit: 1);
        if (nearest.isNotEmpty) return nearest.first;
      } catch (_) {
        // ignore and fallthrough to area search
      }
    }

    // Otherwise, try geocoding first. If the query looks like an exact
    // address (contains digits, comma, or street keywords), prefer the
    // nearest stop to the geocoded center. For area-like queries, prefer
    // polygon/bbox containment first.
    final stops = await ref.read(stopsProvider.future);
    final geo = await _geocodeArea(routeReq.origin ?? '');
    bool looksLikeAddress(String q) {
      if (q.contains(RegExp(r"\\d"))) return true; // street number
      if (q.contains(',')) return true; // comma-separated address
      if (RegExp(r'\\b(gatan|vägen|väg|gata|street|road|st|allee)\\b', caseSensitive: false).hasMatch(q)) return true;
      return false;
    }

    if (geo != null && looksLikeAddress(routeReq.origin ?? '')) {
      if (kDebugMode) debugPrint('[resolve] looksLikeAddress -> using geocode center ${geo.center} to find nearest stop');
      try {
        final repo = ref.read(gtfsRepositoryProvider);
        final nearest = await repo.nearestStops(geo.center, limit: 1);
        if (nearest.isNotEmpty) {
          if (kDebugMode) debugPrint('[resolve] nearest to geocode center -> ${nearest.first.name}');
          return nearest.first;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[resolve] nearestStops error: $e');
      }
    }

    // For area-like queries, prefer the polygon/bbox matching first.
    final areaResults = await _searchStopsByArea(routeReq.origin ?? '', stops);
    if (areaResults.isNotEmpty) return areaResults.first;

    // As a final fallback, if we have a geo center, try nearest stop to it.
    if (geo != null) {
      if (kDebugMode) debugPrint('[resolve] area search empty; falling back to nearest to geo center ${geo.center}');
      try {
        final repo = ref.read(gtfsRepositoryProvider);
        final nearest = await repo.nearestStops(geo.center, limit: 1);
        if (nearest.isNotEmpty) {
          if (kDebugMode) debugPrint('[resolve] fallback nearest -> ${nearest.first.name}');
          return nearest.first;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[resolve] fallback nearestStops error: $e');
      }
    }

    // Fallback: try direct name matching.
    final direct = _matchStop(stops, routeReq.origin ?? '');
    return direct;
  } catch (_) {
    return null;
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
            SelectableText(label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: candidates
                  .map(
                    (stop) => ActionChip(
                      label: SelectableText(stop.name),
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

class _OriginPicker extends StatelessWidget {
  const _OriginPicker({required this.ref, required this.query, required this.stops, required this.onSelect});
  final WidgetRef ref;
  final String query;
  final List<Stop> stops;
  final ValueChanged<Stop> onSelect;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) debugPrint('[origin] picker query="$query" stops=${stops.length}');
    final baseCandidates = _findCandidates(stops, query);

    // If user asked for 'avrese' prefer nearest stops to device location.
    if (query.toLowerCase().contains('avrese')) {
      return FutureBuilder<List<Stop>>(
        future: () async {
          try {
            final permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) await Geolocator.requestPermission();
            final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
            final user = LatLng(pos.latitude, pos.longitude);
            final repo = ref.read(gtfsRepositoryProvider);
            final nearest = await repo.nearestStops(user, limit: 6);
            if (nearest.isNotEmpty) return nearest;
          } catch (_) {
            // ignore and fallthrough to baseCandidates
          }
          return baseCandidates;
        }(),
        builder: (context, snapshot) {
          final candidates = snapshot.data ?? baseCandidates;
          if (snapshot.hasError && candidates.isEmpty) {
            return Text('Kunde inte hitta närliggande hållplatser. (${snapshot.error})');
          }
          if (snapshot.connectionState == ConnectionState.waiting && candidates.isEmpty) {
            return const Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Hittar närliggande hållplatser...'),
              ],
            );
          }
          if (candidates.isEmpty) {
            return const Text('Kunde inte matcha avreseplats mot hållplatser.');
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Välj avresehållplats (närmast):'),
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

    // Fallback: behave like destination picker (area-based suggestions first)
    return FutureBuilder<List<Stop>>(
      future: _searchStopsByArea(query, stops),
      builder: (context, snapshot) {
        final geoCandidates = snapshot.data ?? const <Stop>[];
        final candidates = geoCandidates.isNotEmpty ? geoCandidates : baseCandidates;

        if (snapshot.hasError && candidates.isEmpty) {
          return SelectableText('Kunde inte hitta område för avreseplatsen. (${snapshot.error})');
        }
        if (snapshot.connectionState == ConnectionState.waiting && candidates.isEmpty) {
          return const Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              SelectableText('Hittar hållplatser i området...'),
            ],
          );
        }
        if (candidates.isEmpty) {
          return const SelectableText('Kunde inte matcha avreseplats mot hållplatser.');
        }

        final label = geoCandidates.isNotEmpty
            ? 'Välj avresehållplats i området (OpenStreetMap):'
            : 'Välj avresehållplats bland förslag:';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: candidates
                  .map(
                    (stop) => ActionChip(
                      label: SelectableText(stop.name),
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

List<Stop> stopsWithinPolygon(List<Stop> stops, List<LatLng> polygon, {int limit = 50}) {
  if (polygon.length < 3) return const [];
  // centroid as simple average of vertices
  double latSum = 0, lonSum = 0;
  for (final p in polygon) {
    latSum += p.latitude;
    lonSum += p.longitude;
  }
  final centroid = LatLng(latSum / polygon.length, lonSum / polygon.length);

  final inside = <Stop>[];
  for (final s in stops) {
    final p = LatLng(s.lat, s.lon);
    if (_pointInPolygon(p, polygon)) inside.add(s);
  }

  inside.sort((a, b) {
    final da = _distance(centroid, LatLng(a.lat, a.lon));
    final db = _distance(centroid, LatLng(b.lat, b.lon));
    return da.compareTo(db);
  });

  if (inside.length <= limit) return inside;
  return inside.take(limit).toList();
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
  // Prefer stops that are inside the provided polygon first (if polygon exists),
  // then stops inside the bbox. Within each group, sort by distance to center.
  final polygon = area.polygon;
  List<Stop> polygonMatches = [];
  List<Stop> boxMatches = [];
  for (final s in inside) {
    final inPoly = polygon != null && polygon.length >= 3 && _pointInPolygon(LatLng(s.lat, s.lon), polygon);
    if (inPoly) {
      polygonMatches.add(s);
    } else {
      boxMatches.add(s);
    }
  }

  int sortByDist(Stop a, Stop b) {
    final da = _distance(area.center, LatLng(a.lat, a.lon));
    final db = _distance(area.center, LatLng(b.lat, b.lon));
    return da.compareTo(db);
  }

  polygonMatches.sort(sortByDist);
  boxMatches.sort(sortByDist);

  final combined = [...polygonMatches, ...boxMatches];
  if (combined.isNotEmpty) return combined.take(10).toList();

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
