import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gtfs/gtfs_providers.dart';
import '../gtfs/gtfs_models.dart';
import '../../widgets/async_value_view.dart';
import 'stop_detail_screen.dart';

class StopsScreen extends ConsumerWidget {
  const StopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearest = ref.watch(nearestStopsProvider);
    final all = ref.watch(stopsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Stops')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(nearestStopsProvider);
          ref.invalidate(stopsProvider);
        },
        child: ListView(
          children: [
            _SectionHeader(title: 'Nearby stops'),
            SizedBox(
              height: 180,
              child: AsyncValueView(
                value: nearest,
                builder: (stops) => ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: stops.length,
                  itemBuilder: (context, index) => _StopCard(stop: stops[index]),
                ),
              ),
            ),
            _SectionHeader(title: 'All stops'),
            AsyncValueView(
              value: all,
              builder: (stops) => Column(
                children: stops
                    .map((s) => ListTile(
                          title: Text(s.name),
                          subtitle: Text('${s.lat.toStringAsFixed(4)}, ${s.lon.toStringAsFixed(4)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => StopDetailScreen(stop: s)),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.stop});
  final Stop stop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => StopDetailScreen(stop: stop)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(stop.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Lat ${stop.lat.toStringAsFixed(4)}, Lon ${stop.lon.toStringAsFixed(4)}'),
                const SizedBox(height: 8),
                const Text('Tap for departures'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
