import 'package:uuid/uuid.dart';

import '../gtfs/gtfs_models.dart';

enum BookingStatus { draft, authorized, captured, ticketed }

enum PaymentStatus { idle, processing, succeeded, failed }

class Booking {
  Booking({
    required this.id,
    required this.stop,
    required this.route,
    required this.trip,
    required this.departureTime,
    required this.status,
    required this.price,
    this.ticket,
  });

  final String id;
  final Stop stop;
  final RouteInfo route;
  final TripInfo trip;
  final DateTime departureTime;
  final BookingStatus status;
  final double price;
  final Ticket? ticket;

  Booking copyWith({
    BookingStatus? status,
    Ticket? ticket,
  }) {
    return Booking(
      id: id,
      stop: stop,
      route: route,
      trip: trip,
      departureTime: departureTime,
      status: status ?? this.status,
      price: price,
      ticket: ticket ?? this.ticket,
    );
  }

  static Booking createDraft({required Stop stop, required RouteInfo route, required TripInfo trip, required DateTime departure}) {
    return Booking(
      id: const Uuid().v4(),
      stop: stop,
      route: route,
      trip: trip,
      departureTime: departure,
      status: BookingStatus.draft,
      price: 39.0,
      ticket: null,
    );
  }
}

class Ticket {
  Ticket({required this.id, required this.metadata});
  final String id;
  final Map<String, String> metadata;
}
