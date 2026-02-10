import 'package:flutter_riverpod/flutter_riverpod.dart';

class MapRouteRequest {
  MapRouteRequest({required this.destination, this.origin});

  final String destination;
  final String? origin;

  static const defaultOrigin = 'Bredgränd 14, 753 20 Uppsala';

  factory MapRouteRequest.fromText(String text) {
    final lower = text.toLowerCase();
    final fromTo = RegExp(r'from\s+(.+?)\s+to\s+(.+)', caseSensitive: false).firstMatch(text);
    final franTill = RegExp(r'från\s+(.+?)\s+till\s+(.+)', caseSensitive: false).firstMatch(lower);
    final structuredOrigin = RegExp(r'ursprung[:\-]\s*(.+)', caseSensitive: false).firstMatch(lower);
    final structuredDest = RegExp(r'destination[:\-]\s*(.+)', caseSensitive: false).firstMatch(lower);

    if (fromTo != null) {
      return MapRouteRequest(
        origin: fromTo.group(1)?.trim(),
        destination: fromTo.group(2)?.trim() ?? text,
      );
    }
    if (franTill != null) {
      return MapRouteRequest(
        origin: franTill.group(1)?.trim(),
        destination: franTill.group(2)?.trim() ?? text,
      );
    }
    if (structuredDest != null) {
      return MapRouteRequest(
        origin: structuredOrigin?.group(1)?.trim(),
        destination: structuredDest.group(1)?.trim() ?? text,
      );
    }
    return MapRouteRequest(destination: text.trim(), origin: defaultOrigin);
  }
}

final mapRouteRequestProvider = StateProvider<MapRouteRequest?>((ref) => null);
