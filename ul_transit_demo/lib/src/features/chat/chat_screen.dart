import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app_shell.dart';
import '../gtfs/gtfs_models.dart';
import '../gtfs/gtfs_providers.dart';
import '../map/map_route_provider.dart';
import '../settings/settings_controller.dart';
import 'chat_notifier.dart';

class TripChatScreen extends ConsumerStatefulWidget {
  const TripChatScreen({super.key});

  @override
  ConsumerState<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends ConsumerState<TripChatScreen> {
  final _controller = TextEditingController();

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
                final looksLikeTrip = !msg.isUser && _looksLikeTrip(msg.text);
                MapRouteRequest? routeReq;
                Stop? originStop;
                Stop? destStop;
                if (looksLikeTrip && stopsValue.hasValue) {
                  routeReq = MapRouteRequest.fromText(msg.text);
                  final stops = stopsValue.value!;
                  destStop = _matchStop(stops, routeReq.destination) ?? (stops.isNotEmpty ? stops.first : null);
                  if (routeReq.origin != null) {
                    originStop = _matchStop(stops, routeReq.origin!);
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
                          msg.text,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: msg.isUser ? FontWeight.w500 : FontWeight.w400,
                              ),
                        ),
                      ),
                    ),
                    if (looksLikeTrip)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FilledButton.icon(
                              icon: const Icon(Icons.directions_bus),
                              label: const Text('Visa rutt och boka'),
                              onPressed: () {
                                ref.read(mapRouteRequestProvider.notifier).state = MapRouteRequest.fromText(msg.text);
                                ref.read(navIndexProvider.notifier).state = 1; // Map tab
                              },
                            ),
                            const SizedBox(height: 8),
                            if (destStop != null)
                              _TripSuggestionCard(
                                routeRequest: routeReq,
                                origin: originStop,
                                destination: destStop,
                              ),
                          ],
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

class _TripSuggestionCard extends ConsumerWidget {
  const _TripSuggestionCard({this.routeRequest, this.origin, required this.destination});

  final MapRouteRequest? routeRequest;
  final Stop? origin;
  final Stop destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departures = ref.watch(stopDeparturesProvider(destination.id));
    final now = DateTime.now();

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hållplats: ${destination.name}', style: Theme.of(context).textTheme.titleMedium),
            if (origin != null) Text('Från: ${origin!.name}'),
            if (routeRequest?.destination.isNotEmpty == true && destination.name.toLowerCase() != routeRequest!.destination.toLowerCase())
              Text('Matchad mot: ${routeRequest!.destination}'),
            const SizedBox(height: 8),
            departures.when(
              loading: () => const Text('Laddar tidtabell...'),
              error: (e, _) => Text('Kunde inte hämta avgångar: $e'),
              data: (items) {
                final next = items.take(3).toList();
                if (next.isEmpty) return const Text('Inga avgångar hittades.');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nästa avgångar:'),
                    const SizedBox(height: 6),
                    ...next.map((dep) {
                      final time = TimeOfDay.fromDateTime(dep.arrivalTime).format(context);
                      final mins = dep.arrivalTime.difference(now).inMinutes;
                      final eta = mins <= 0 ? 'nu' : 'om ${mins} min';
                      return Text('• ${dep.route.shortName} → ${dep.trip.headsign} · $time ($eta)');
                    }),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _MiniMap(origin: origin, destination: destination),
          ],
        ),
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({this.origin, required this.destination});
  final Stop? origin;
  final Stop destination;

  @override
  Widget build(BuildContext context) {
    final destPoint = LatLng(destination.lat, destination.lon);
    final originPoint = origin != null ? LatLng(origin!.lat, origin!.lon) : null;
    final center = originPoint != null
        ? LatLng((originPoint.latitude + destPoint.latitude) / 2, (originPoint.longitude + destPoint.longitude) / 2)
        : destPoint;

    final markers = <Marker>[
      Marker(
        point: destPoint,
        width: 40,
        height: 40,
        child: const Icon(Icons.flag, color: Colors.red, size: 32),
      ),
    ];
    if (originPoint != null) {
      markers.add(
        Marker(
          point: originPoint,
          width: 32,
          height: 32,
          child: const Icon(Icons.circle, color: Colors.green, size: 24),
        ),
      );
    }

    final polylines = <Polyline>[];
    if (originPoint != null) {
      polylines.add(
        Polyline(
          points: [originPoint, destPoint],
          color: Colors.orange,
          strokeWidth: 3,
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 13),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.ul.demo',
            ),
            if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),
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
