class Stop {
  Stop({required this.id, required this.name, required this.lat, required this.lon});
  final String id;
  final String name;
  final double lat;
  final double lon;
}

class RouteInfo {
  RouteInfo({required this.id, required this.shortName, required this.longName});
  final String id;
  final String shortName;
  final String longName;
}

class TripInfo {
  TripInfo({required this.id, required this.routeId, required this.serviceId, required this.headsign});
  final String id;
  final String routeId;
  final String serviceId;
  final String headsign;
}

class StopTime {
  StopTime({required this.tripId, required this.stopId, required this.arrival});
  final String tripId;
  final String stopId;
  final DateTime arrival;
}

class ShapePoint {
  ShapePoint({required this.shapeId, required this.lat, required this.lon, required this.sequence});
  final String shapeId;
  final double lat;
  final double lon;
  final int sequence;
}

class Departure {
  Departure({required this.trip, required this.route, required this.arrivalTime, required this.stop});
  final TripInfo trip;
  final RouteInfo route;
  final DateTime arrivalTime;
  final Stop stop;
}
