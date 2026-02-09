import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../gtfs/gtfs_models.dart';
import '../gtfs/gtfs_providers.dart';
import '../stops/stop_detail_screen.dart';
import '../../widgets/async_value_view.dart';

class GtfsMapScreen extends ConsumerStatefulWidget {
  const GtfsMapScreen({super.key});

  @override
  ConsumerState<GtfsMapScreen> createState() => _GtfsMapScreenState();
}

class _GtfsMapScreenState extends ConsumerState<GtfsMapScreen> {
  LatLng _center = const LatLng(59.8586, 17.6454);
  Position? _position;

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
    final shape = ref.watch(shapeProvider('UL101'));

    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: AsyncValueView(
        value: stops,
        builder: (stopsData) {
          final markers = stopsData
              .map(
                (stop) => Marker(
                  point: LatLng(stop.lat, stop.lon),
                  width: 160,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StopDetailScreen(stop: stop),
                    )),
                    child: Card(
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(stop.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                ),
              )
              .toList();

          final polylines = shape.maybeWhen(
            data: (points) => [
              Polyline(
                points: points.map((p) => LatLng(p.lat, p.lon)).toList(),
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 4,
              ),
            ],
            orElse: () => <Polyline>[],
          );

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

          return FlutterMap(
            options: MapOptions(initialCenter: _center, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ul.demo',
              ),
              PolylineLayer(polylines: polylines),
              MarkerLayer(markers: [...markers, ...userMarker]),
            ],
          );
        },
      ),
    );
  }
}
