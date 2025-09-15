// lib/Assistants/driver_request_flow.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:users/global/global.dart';

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
    required double fare,
    String currency = "SAR",
    String vehicleType = "car",
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
      'fare': fare,
      'currency': currency,
      'vehicleType': vehicleType,
      'createdAt': ServerValue.timestamp,
      'status': 'searching',
      'driverId': 'waiting',
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> _getCandidateDrivers(
      LatLng center, {double maxKm = 8}) async {
    final snap = await _db.child('drivers').get();
    final out = <Map<String, dynamic>>[];

    for (final d in snap.children) {
      final m = (d.value as Map?) ?? {};
      final status = (m['newRideStatus'] ?? 'idle').toString();
      if (status == 'busy' || status == 'offline') continue;

      final loc = (m['location'] as Map?) ?? {};
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

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
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
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
    required double fare,
    String currency = "SAR",
    String vehicleType = "car",
    required void Function(String status, {String? driverId, String? requestId}) onStatus,
  }) async {
    _cancelled = false;

    final uid = firebaseAuth.currentUser!.uid;
    final reqId = await _createRideRequest(
      userId: uid,
      pickup: pickup,
      pickupAddress: pickupAddress,
      dropoff: dropoff,
      dropAddress: dropAddress,
      fare: fare,
      currency: currency,
      vehicleType: vehicleType,
    );

    _activeRequestId = reqId;
    currentRideRequestId = reqId;
    onStatus('searching', requestId: reqId);

    final drivers = await _getCandidateDrivers(pickup);
    if (drivers.isEmpty) {
      await _db.child('rideRequests/$reqId/status').set('no_driver');
      onStatus('no_driver', requestId: reqId);
      return;
    }

    // جرّب السواقين بالترتيب (الأقرب فالأبعد)
    for (final d in drivers) {
      if (_cancelled || _activeRequestId == null) return;
      final driverId = d['id'] as String;

      // اكتب requestId عند السائق (متوافق مع كود السائق الحالي)
      await _db.child('drivers/$driverId/newRideRequestId').set(reqId);

      // وعلّم إن فيه طلب داخل + مكان للرد
      await _db.child('drivers/$driverId').update({
        'newRideStatus': 'incoming',
        'currentRideId': reqId,
        'rideResponse': {
          'requestId': reqId,
          'status': null, // ينتظر accept/reject/timeout
        },
      });

      // اسمع رد السائق ده فقط
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
          onStatus('accepted', driverId: driverId, requestId: reqId);
          _cleanup();
        } else if (status == 'rejected') {
          await _db.child('drivers/$driverId').update({
            'newRideStatus': 'idle',
            'currentRideId': null,
          });
          // نكمّل نجرب السواق اللي بعده (ما نقفلش)
        }
      });

      // تايم أوت للرد
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
