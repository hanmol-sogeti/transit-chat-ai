import 'package:flutter_riverpod/flutter_riverpod.dart';

class MapRouteRequest {
  MapRouteRequest({required this.destination, this.origin});

  final String destination;
  final String? origin;

  static const defaultOrigin = 'Bredgränd 14, 753 20 Uppsala';
  static const defaultDestination = 'Börjetull, Uppsala';

  factory MapRouteRequest.fromText(String text) {
    final cleanedText = text.replaceAll(RegExp(r'[\*`_]'), '');
    final lower = cleanedText.toLowerCase();
    final fromTo = RegExp(r'from\s+(.+?)\s+to\s+(.+)', caseSensitive: false).firstMatch(cleanedText);
    final franTill = RegExp(r'från\s+(.+?)\s+till\s+(.+)', caseSensitive: false).firstMatch(lower);
    final structuredOrigin = RegExp(r'(ursprung|origin)[:\-]\s*(.+)', caseSensitive: false).firstMatch(lower);
    final structuredDest = RegExp(r'(destination|destin)[:\-]\s*(.+)', caseSensitive: false).firstMatch(lower);

    String? origin;
    String? dest;

    if (fromTo != null) {
      origin = fromTo.group(1)?.trim();
      dest = fromTo.group(2)?.trim();
    } else if (franTill != null) {
      origin = franTill.group(1)?.trim();
      dest = franTill.group(2)?.trim();
    } else {
      if (structuredOrigin != null) origin = structuredOrigin.group(2)?.trim();
      if (structuredDest != null) dest = structuredDest.group(2)?.trim();
    }

    // Try line-by-line parsing for numbered markdown lists (e.g., "1. Ursprung: ...").
    if (dest == null || dest.isEmpty) {
      for (final rawLine in cleanedText.split(RegExp(r'[\r\n]+'))) {
        final line = rawLine.trim();
        final numberedMatch = RegExp(r'^\d+\.\s*(.+)').firstMatch(line);
        final content = numberedMatch != null ? (numberedMatch.group(1) ?? '') : line;
        final dLine = RegExp(r'(destination|destin|mål|till)[:\-]\s*(.+)', caseSensitive: false).firstMatch(content);
        if (dLine != null) {
          dest = dLine.group(2)?.trim();
          break;
        }
      }
    }

    origin = (origin == null || origin.isEmpty) ? defaultOrigin : origin.trim();
    dest = (dest == null || dest.isEmpty) ? defaultDestination : dest.trim();

    return MapRouteRequest(destination: dest, origin: origin);
  }
}

final mapRouteRequestProvider = StateProvider<MapRouteRequest?>((ref) => null);
