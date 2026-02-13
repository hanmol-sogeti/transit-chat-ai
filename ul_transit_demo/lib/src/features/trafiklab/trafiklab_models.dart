import 'package:latlong2/latlong.dart';

class Stop {
  Stop({required this.id, required this.name, required this.lat, required this.lon});
  final String id;
  final String name;
  final double lat;
  final double lon;

  LatLng get point => LatLng(lat, lon);

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      id: (json['id'] ?? json['stop_id'] ?? '').toString(),
      name: (json['name'] ?? json['stop_name'] ?? '').toString(),
      lat: (json['lat'] ?? json['stop_lat'] ?? 0).toDouble(),
      lon: (json['lon'] ?? json['stop_lon'] ?? 0).toDouble(),
    );
  }
}

class Departure {
  Departure({required this.stop, required this.route, required this.time});
  final Stop stop;
  final String route;
  final DateTime time;

  factory Departure.fromJson(Map<String, dynamic> json) {
    return Departure(
      stop: Stop.fromJson(json['stop'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      route: (json['route'] ?? '').toString(),
      time: DateTime.tryParse((json['time'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}

class TripLeg {
  TripLeg({required this.mode, required this.points});
  final String mode;
  final List<LatLng> points;

  factory TripLeg.fromJson(Map<String, dynamic> json) {
    final coords = (json['geometry'] as List<dynamic>? ?? [])
        .map((p) => LatLng((p as List)[0] as double, (p)[1] as double))
        .toList();
    return TripLeg(mode: (json['mode'] ?? '').toString(), points: coords);
  }
}

class TripPlan {
  TripPlan({required this.legs});
  final List<TripLeg> legs;

  factory TripPlan.fromJson(Map<String, dynamic> json) {
    final rawLegs = (json['legs'] as List<dynamic>? ?? []);
    return TripPlan(legs: rawLegs.map((l) => TripLeg.fromJson(l as Map<String, dynamic>)).toList());
  }
}
