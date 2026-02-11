import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../gtfs/gtfs_models.dart';
import '../gtfs/gtfs_providers.dart';
import '../stops/stop_detail_screen.dart';
import '../../widgets/async_value_view.dart';
import 'map_route_provider.dart';
import 'map_route_service.dart';

class GtfsMapScreen extends ConsumerStatefulWidget {
  const GtfsMapScreen({super.key});

  @override
  ConsumerState<GtfsMapScreen> createState() => _GtfsMapScreenState();
}

class _GtfsMapScreenState extends ConsumerState<GtfsMapScreen> {
  LatLng _center = const LatLng(59.8586, 17.6454);
  Position? _position;

  static const LatLng _defaultOrigin = LatLng(59.8580, 17.6389); // Bredgränd 14
  static const LatLng _defaultDest = LatLng(59.8725, 17.6150); // Börjetull
  static const String _defaultDestName = 'Börjetull';

  @override
  void initState() {
    super.initState();
    _ensurePermission();
  }

  Future<void> _ensurePermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _position = pos;
        _center = LatLng(pos.latitude, pos.longitude);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final stops = ref.watch(stopsProvider);
    final routeRequest = ref.watch(mapRouteRequestProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: AsyncValueView(
        value: stops,
        builder: (stopsData) {
          debugPrint('[map] render stops=${stopsData.length} routeReq=${routeRequest?.destination}');
          Stop? destStop;
          Stop? originStop;
          bool originMatched = false;
          bool destMatched = false;
          LatLng? destPoint;
          LatLng? originPoint;
          AsyncValue<List<Departure>>? departures;
          AsyncValue<List<MapRouteLeg>>? legsValue;
          String? routingError;

          if (routeRequest != null) {
            destStop = _matchStop(stopsData, routeRequest.destination) ?? _matchStop(stopsData, _defaultDestName);
            originStop = routeRequest.origin != null ? _matchStop(stopsData, routeRequest.origin!) : null;

            // Log matching outcome for debugging
            debugPrint('[map] match origin=${routeRequest.origin} -> ${originStop?.name} dest=${routeRequest.destination} -> ${destStop?.name}');

            if (destStop != null) {
              destMatched = true;
              destPoint = LatLng(destStop!.lat, destStop!.lon);
              departures = ref.watch(stopDeparturesProvider(destStop!.id));
            }

            if (originStop != null) {
              originMatched = true;
              originPoint = LatLng(originStop!.lat, originStop!.lon);
            }

            if (destPoint == null || originPoint == null) {
              routingError = 'Kunde inte matcha start eller mål mot hållplatser. Ingen rutt beräknad.';
            } else {
              final query = RouteQuery(origin: originPoint, destination: destPoint);
              legsValue = ref.watch(mapRouteLegsProvider(query));
              debugPrint('[map] route query origin=${query.origin.latitude},${query.origin.longitude} dest=${query.destination.latitude},${query.destination.longitude}');
            }
          }

          final markers = stopsData
              .map(
                (stop) => Marker(
                  point: LatLng(stop.lat, stop.lon),
                  width: 16,
                  height: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StopDetailScreen(stop: stop),
                    )),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              )
              .toList();

          if (destPoint != null) {
            markers.add(
              Marker(
                point: destPoint,
                width: 50,
                height: 50,
                child: const Icon(Icons.flag, color: Colors.red, size: 40),
              ),
            );
          }

          if (originPoint != null) {
            markers.add(
              Marker(
                point: originPoint,
                width: 50,
                height: 50,
                child: const Icon(Icons.circle, color: Colors.green, size: 28),
              ),
            );
          }

          final polylines = <Polyline>[];
          if (legsValue != null) {
            legsValue!.maybeWhen(
              data: (legs) {
                polylines.addAll(
                  legs.map(
                    (leg) => Polyline(
                      points: leg.points,
                      color: leg.isWalk ? Colors.blueGrey : Colors.orange,
                      strokeWidth: leg.isWalk ? 3 : 4,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                );
              },
              loading: () {},
              error: (e, _) {
                routingError = 'Rutt kunde inte beräknas: $e';
              },
              orElse: () {},
            );
          }

          final userMarker = _position == null
              ? <Marker>[]
              : [
                  Marker(
                    point: LatLng(_position!.latitude, _position!.longitude),
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.person_pin_circle, size: 36, color: Colors.blue),
                  ),
                ];

          LatLng mapCenter = destPoint ?? _center;
          if (originPoint != null && destPoint != null) {
            mapCenter = LatLng(
              (originPoint.latitude + destPoint.latitude) / 2,
              (originPoint.longitude + destPoint.longitude) / 2,
            );
          }

          if (legsValue != null) {
            legsValue!.maybeWhen(
              data: (legs) => debugPrint('[map] legs received count=${legs.length} firstPoints=${legs.isNotEmpty ? legs.first.points.length : 0}'),
              error: (e, st) => debugPrint('[map] legs error: $e'),
              loading: () => debugPrint('[map] legs loading'),
              orElse: () {},
            );
          }

          return Column(
            children: [
              if (routeRequest != null)
                Container(
                  width: double.infinity,
                  color: routingError == null ? Theme.of(context).colorScheme.surfaceVariant : Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rutt', style: Theme.of(context).textTheme.titleMedium),
                      Text('Från: ${originStop?.name ?? routeRequest.origin ?? 'Bredgränd 14'}${originMatched ? '' : ' (ingen match)'}'),
                      Text('Till: ${destStop?.name ?? routeRequest.destination}${destMatched ? '' : ' (ingen match)'}'),
                      if (routingError != null) ...[
                        const SizedBox(height: 4),
                        Text(routingError!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(initialCenter: mapCenter, initialZoom: 13),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ul.demo',
                    ),
                    PolylineLayer(polylines: polylines),
                    MarkerLayer(markers: [...markers, ...userMarker]),
                  ],
                ),
              ),
              if (destStop != null && departures != null)
                SizedBox(
                  height: 160,
                  child: AsyncValueView(
                    value: departures!,
                    builder: (items) {
                      final top3 = items.take(3).toList();
                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: top3.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final dep = top3[index];
                          final time = TimeOfDay.fromDateTime(dep.arrivalTime).format(context);
                          return ListTile(
                            leading: Text(dep.route.shortName, style: Theme.of(context).textTheme.titleMedium),
                            title: Text(dep.trip.headsign),
                            subtitle: Text('Avgång $time • ${dep.stop.name}'),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          );
        },
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
