import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../gtfs/gtfs_models.dart';
import 'booking_models.dart';

final bookingProvider = StateNotifierProvider<BookingNotifier, Booking?>((ref) => BookingNotifier());
final paymentStatusProvider = StateProvider<PaymentStatus>((ref) => PaymentStatus.idle);

class BookingNotifier extends StateNotifier<Booking?> {
  BookingNotifier() : super(null);

  void startBooking({required Stop stop, required RouteInfo route, required TripInfo trip, required DateTime departureTime}) {
    state = Booking.createDraft(stop: stop, route: route, trip: trip, departure: departureTime);
  }

  void authorizePayment(WidgetRef ref) {
    if (state == null) return;
    ref.read(paymentStatusProvider.notifier).state = PaymentStatus.processing;
    Future.delayed(const Duration(seconds: 1), () {
      ref.read(paymentStatusProvider.notifier).state = PaymentStatus.succeeded;
      state = state!.copyWith(status: BookingStatus.authorized);
    });
  }

  void capturePayment(WidgetRef ref) {
    if (state == null) return;
    ref.read(paymentStatusProvider.notifier).state = PaymentStatus.processing;
    Future.delayed(const Duration(seconds: 1), () {
      ref.read(paymentStatusProvider.notifier).state = PaymentStatus.succeeded;
      state = state!.copyWith(status: BookingStatus.captured);
    });
  }

  void issueTicket() {
    if (state == null) return;
    final ticket = Ticket(id: const Uuid().v4(), metadata: {
      'route': state!.route.shortName,
      'stop': state!.stop.name,
      'departure': state!.departureTime.toIso8601String(),
      'passenger': state!.user.name,
      'gender': state!.user.gender,
      'birthdate': state!.user.birthdate,
      'demo': 'Demo - not a real ticket',
    });
    state = state!.copyWith(status: BookingStatus.ticketed, ticket: ticket);
  }

  void reset() {
    state = null;
  }
}
