import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/booking_notifier.dart';
import '../booking/booking_models.dart';
import '../gtfs/gtfs_models.dart';
import '../gtfs/gtfs_providers.dart';
import '../../widgets/async_value_view.dart';

class StopDetailScreen extends ConsumerWidget {
  const StopDetailScreen({super.key, required this.stop});

  final Stop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departures = ref.watch(stopDeparturesProvider(stop.id));

    return Scaffold(
      appBar: AppBar(title: Text(stop.name)),
      body: AsyncValueView(
        value: departures,
        builder: (items) => ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final dep = items[index];
            final time = TimeOfDay.fromDateTime(dep.arrivalTime).format(context);
            return ListTile(
              title: Text('${dep.route.shortName} to ${dep.trip.headsign}'),
              subtitle: Text('Arrives $time'),
              trailing: ElevatedButton(
                onPressed: () {
                  ref.read(bookingProvider.notifier).startBooking(
                        stop: dep.stop,
                        route: dep.route,
                        trip: dep.trip,
                        departureTime: dep.arrivalTime,
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to booking. Continue in Tickets tab.')),
                  );
                },
                child: const Text('Book'),
              ),
            );
          },
        ),
      ),
    );
  }
}
