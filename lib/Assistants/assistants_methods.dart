import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:users/Assistants/request_assistants.dart';
import 'package:users/global/global.dart';
import 'package:users/infoHandler/app_info.dart';
import 'package:users/models/directions.dart';
import 'package:users/models/user_model.dart';

import '../models/direction_details_info.dart';

class AssistantsMehods {
  /// قراءة بيانات المستخدم الحالي من Firebase
  static void readCurrentOnlineUserInfo() async {
    currentUser = firebaseAuth.currentUser;

    DatabaseReference userRef = FirebaseDatabase.instance
        .ref()
        .child("users")
        .child(currentUser!.uid);

    userRef.once().then((snap) {
      if (snap.snapshot.value != null) {
        userModelCurrentInfo = UserModel.formSnapshot(snap.snapshot);
      }
    });
  }

  /// جلب العنوان البشري من الإحداثيات (Geocoding)
  static Future<String> searchAddressForGeographCoOrdinates(
      Position position, context) async {
    final apiUrl =
        "https://maps.googleapis.com/maps/api/geocode/json"
        "?latlng=${position.latitude},${position.longitude}"
        "&key=AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0";

    String humanReadableAddress = "";

    final response = await RequestAssistants.receiveRequest(apiUrl);

    // تأكد إن الرد صحيح
    if (response is! Map) return humanReadableAddress;

    if (response["status"] == "OK" &&
        response["results"] is List &&
        (response["results"] as List).isNotEmpty) {
      humanReadableAddress =
          response["results"][0]["formatted_address"] ?? "";

      final userPickUpAddress = Directions()
        ..locationLatitude = position.latitude
        ..locationLongitude = position.longitude
        ..locationName = humanReadableAddress;

      Provider.of<AppInfo>(context, listen: false)
          .updatePickUpLocationAddress(userPickUpAddress);
    }

    return humanReadableAddress;
  }

  /// جلب تفاصيل الاتجاهات من Google Directions API
  static Future<DirectionDetailsInfo?> obtainOriginToDestinationDirectionDetails(
      LatLng originPosition,
      LatLng destinationPosition,
      ) async {
    final url =
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=${originPosition.latitude},${originPosition.longitude}"
        "&destination=${destinationPosition.latitude},${destinationPosition.longitude}"
        "&mode=driving"
        "&key=AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0";

    final response = await RequestAssistants.receiveRequest(url);

    if (response is! Map || response["status"] != "OK") {
      return null;
    }

    final routes = response["routes"] as List?;
    if (routes == null || routes.isEmpty) return null;

    final legs = routes[0]["legs"] as List?;
    if (legs == null || legs.isEmpty) return null;

    final info = DirectionDetailsInfo()
      ..e_points = routes[0]["overview_polyline"]?["points"] as String?
      ..distance_text = legs[0]["distance"]?["text"] as String?
      ..distance_value = (legs[0]["distance"]?["value"] as num?)?.toInt()
      ..duration_text = legs[0]["duration"]?["text"] as String?
      ..duration_value = (legs[0]["duration"]?["value"] as num?)?.toInt();

    return info;
  }

  static double calculateFareAmountFormOriginToDestination(DirectionDetailsInfo directionDetailsInfo) {
    final durationInSeconds = directionDetailsInfo.duration_value ?? 0;
    final distanceInMeters = directionDetailsInfo.distance_value ?? 0;

    const double baseFare = 7;
    const double costPerMinute = 0.50;
    const double costPerKm = 1.5;
    const double minimumFare = 20.0;

    final timeTraveledFare = (durationInSeconds / 60) * costPerMinute;
    final distanceTraveledFare = (distanceInMeters / 1000) * costPerKm;

    double totalFare = baseFare + timeTraveledFare + distanceTraveledFare;

    if (totalFare < minimumFare) {
      totalFare = minimumFare;
    }

    return double.parse(totalFare.toStringAsFixed(2));
  }

  static double calculateFareBike(DirectionDetailsInfo directionDetailsInfo) {
    final durationInSeconds = directionDetailsInfo.duration_value ?? 0;
    final distanceInMeters = directionDetailsInfo.distance_value ?? 0;

    const double baseFare = 4;
    const double costPerMinute = 0.21;
    const double costPerKm = 0.92;
    const double minimumFare = 15;

    final timeTraveledFare = (durationInSeconds / 60) * costPerMinute;
    final distanceTraveledFare = (distanceInMeters / 1000) * costPerKm;

    double totalFare = baseFare + timeTraveledFare + distanceTraveledFare;

    if (totalFare < minimumFare) {
      totalFare = minimumFare;
    }

    return double.parse(totalFare.toStringAsFixed(2));
  }
}

// ===================== DriverRequestFlow =====================

class DriverRequestFlow {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _respSub;
  Timer? _timeout;

  String? _activeRequestId;
  bool _cancelled = false;

  Future<String> _createRideRequest({
    required String userId,
    required LatLng pickup,
    required String pickupAddress,
    required LatLng dropoff,
    required String dropAddress,
  }) async {
    final ref = _db.child('rideRequests').push();
    final id = ref.key!;
    await ref.set({
      'userId': userId,
      'pickup': {
        'lat': pickup.latitude,
        'lng': pickup.longitude,
        'address': pickupAddress,
      },
      'dropoff': {
        'lat': dropoff.latitude,
        'lng': dropoff.longitude,
        'address': dropAddress,
      },
      'createdAt': ServerValue.timestamp,
      'status': 'searching',
      'driverId': null,
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> _getCandidateDrivers(LatLng center, {double maxKm = 8}) async {
    final snap = await _db.child('drivers').get();
    final out = <Map<String, dynamic>>[];

    for (final d in snap.children) {
      final m = (d.value as Map?) ?? {};
      final status = m['newRideStatus']?.toString() ?? 'idle';
      final loc = (m['location'] as Map?) ?? {};
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (status == 'busy') continue;

      final km = _approxKm(center.latitude, center.longitude, lat, lng);
      if (km <= maxKm) {
        out.add({'id': d.key!, 'lat': lat, 'lng': lng, 'km': km});
      }
    }
    out.sort((a, b) => (a['km'] as double).compareTo(b['km'] as double));
    return out;
  }

  double _approxKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    double dLat = (lat2 - lat1) * math.pi / 180.0;
    double dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  Future<void> start({
    required LatLng pickup,
    required String pickupAddress,
    required LatLng dropoff,
    required String dropAddress,
    required void Function(String status, {String? driverId}) onStatus,
  }) async {
    _cancelled = false;

    final uid = firebaseAuth.currentUser!.uid;
    final reqId = await _createRideRequest(
      userId: uid,
      pickup: pickup,
      pickupAddress: pickupAddress,
      dropoff: dropoff,
      dropAddress: dropAddress,
    );
    _activeRequestId = reqId;
    currentRideRequestId = reqId;
    onStatus('searching');

    final drivers = await _getCandidateDrivers(pickup);
    if (drivers.isEmpty) {
      await _db.child('rideRequests/$reqId/status').set('no_driver');
      onStatus('no_driver');
      return;
    }

    for (final d in drivers) {
      if (_cancelled || _activeRequestId == null) return;
      final driverId = d['id'] as String;

      await _db.child('drivers/$driverId').update({
        'newRideStatus': 'incoming',
        'currentRideId': reqId,
        'rideResponse': {
          'requestId': reqId,
          'status': null,
        },
      });

      _respSub?.cancel();
      _respSub = _db.child('drivers/$driverId/rideResponse').onValue.listen((ev) async {
        if (_cancelled || _activeRequestId == null) return;
        final data = (ev.snapshot.value as Map?) ?? {};
        if (data['requestId'] != reqId) return;
        final status = (data['status'] ?? '').toString();

        if (status == 'accepted') {
          _timeout?.cancel();
          await _db.child('rideRequests/$reqId').update({
            'status': 'accepted',
            'driverId': driverId,
          });
          await _db.child('drivers/$driverId').update({'newRideStatus': 'busy'});
          onStatus('accepted', driverId: driverId);
          _cleanup();
        } else if (status == 'rejected') {
          await _db.child('drivers/$driverId').update({
            'newRideStatus': 'idle',
            'currentRideId': null,
          });
        }
      });

      _timeout?.cancel();
      _timeout = Timer(const Duration(seconds: 25), () async {
        await _db.child('drivers/$driverId/rideResponse').set({
          'requestId': reqId,
          'status': 'timeout',
        });
        await _db.child('drivers/$driverId').update({
          'newRideStatus': 'idle',
          'currentRideId': null,
        });
      });
    }
  }

  Future<void> cancelByUser() async {
    _cancelled = true;
    if (_activeRequestId != null) {
      await _db.child('rideRequests/${_activeRequestId}/status').set('cancelled');
    }
    _cleanup();
  }

  void _cleanup() {
    _respSub?.cancel();
    _respSub = null;
    _timeout?.cancel();
    _timeout = null;
    _activeRequestId = null;
  }
}
