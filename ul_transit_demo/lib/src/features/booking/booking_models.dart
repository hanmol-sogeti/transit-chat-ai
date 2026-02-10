import 'package:uuid/uuid.dart';

import '../gtfs/gtfs_models.dart';

enum BookingStatus { draft, authorized, captured, ticketed }

enum PaymentStatus { idle, processing, succeeded, failed }

class UserProfile {
  const UserProfile({required this.name, required this.gender, required this.birthdate});
  final String name;
  final String gender;
  final String birthdate;
}

const demoUserProfile = UserProfile(name: 'John Doe', gender: 'Man', birthdate: '1975-01-01');

class Booking {
  Booking({
    required this.id,
    required this.stop,
    required this.route,
    required this.trip,
    required this.departureTime,
    required this.status,
    required this.price,
    required this.user,
    this.ticket,
  });

  final String id;
  final Stop stop;
  final RouteInfo route;
  final TripInfo trip;
  final DateTime departureTime;
  final BookingStatus status;
  final double price;
  final UserProfile user;
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
      user: user,
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
      user: demoUserProfile,
      ticket: null,
    );
  }
}

class Ticket {
  Ticket({required this.id, required this.metadata});
  final String id;
  final Map<String, String> metadata;
}
