import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'booking_models.dart';
import 'booking_notifier.dart';

class TicketWalletScreen extends ConsumerWidget {
  const TicketWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingProvider);
    final paymentStatus = ref.watch(paymentStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tickets & Booking')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: booking == null
            ? const _EmptyState()
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BookingSummary(booking: booking),
                    const SizedBox(height: 16),
                    _BookingActions(booking: booking, paymentStatus: paymentStatus),
                    if (booking.ticket != null) ...[
                      const SizedBox(height: 16),
                      _TicketView(ticket: booking.ticket!),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_2, size: 64),
          const SizedBox(height: 12),
          const Text('No booking yet'),
          const SizedBox(height: 8),
          const Text('Pick a departure from Stops to create a booking.'),
        ],
      ),
    );
  }
}

class _BookingSummary extends StatelessWidget {
  const _BookingSummary({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(booking.departureTime).format(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${booking.route.shortName} to ${booking.trip.headsign}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('From ${booking.stop.name} at $time'),
            const SizedBox(height: 4),
            Text('Price: ${booking.price.toStringAsFixed(0)} kr'),
            const SizedBox(height: 4),
            Text('Status: ${booking.status.name}'),
            const SizedBox(height: 4),
            Text('Resenär: ${booking.user.name} (${booking.user.gender}, född ${booking.user.birthdate})'),
          ],
        ),
      ),
    );
  }
}

class _BookingActions extends ConsumerWidget {
  const _BookingActions({required this.booking, required this.paymentStatus});
  final Booking booking;
  final PaymentStatus paymentStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(bookingProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: booking.status == BookingStatus.draft && paymentStatus != PaymentStatus.processing
                    ? () => notifier.authorizePayment(ref)
                    : null,
                child: const Text('Authorize'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: booking.status == BookingStatus.authorized && paymentStatus != PaymentStatus.processing
                    ? () => notifier.capturePayment(ref)
                    : null,
                child: const Text('Capture'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: booking.status == BookingStatus.captured && booking.ticket == null
              ? notifier.issueTicket
              : booking.ticket != null
                  ? () {}
                  : null,
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Issue demo QR ticket'),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: notifier.reset,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Clear booking'),
        ),
      ],
    );
  }
}

class _TicketView extends StatelessWidget {
  const _TicketView({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Demo ticket', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Demo - not a real ticket'),
            const SizedBox(height: 12),
            Center(
              child: QrImageView(
                data: ticket.id,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text('Ticket ID: ${ticket.id}'),
            ...ticket.metadata.entries.map((e) => Text('${e.key}: ${e.value}')),
          ],
        ),
      ),
    );
  }
}
