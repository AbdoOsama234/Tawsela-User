// lib/features/ride/domain/usecases/driver_request_flow.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:users/core/constants/global.dart';
import 'package:users/features/ride/domain/entities/driver_profile.dart';

/// UseCase لمطابقة مستخدم مع سائق قريب.
/// onStatus:
///   - 'searching'  => بدأنا الطلب/نجرّب سائق
///   - 'accepted'   => تم القبول (يرجع driver: DriverProfile)
///   - 'no_driver'  => لم يُعثر على سائق
///   - 'cancelled'  => المستخدم ألغى
///   - 'completed'  => انتهى
class DriverRequestFlow {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  String? _activeRequestId;
  bool _cancelled = false;

  // ---------- Helpers ----------
  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
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

  Future<List<Map<String, dynamic>>> _getCandidateDrivers(
      LatLng center, {
        double maxKm = 8,
      }) async {
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

      final km = _haversineKm(center.latitude, center.longitude, lat, lng);
      if (km <= maxKm) {
        out.add({'id': d.key!, 'lat': lat, 'lng': lng, 'km': km});
      }
    }
    out.sort((a, b) => (a['km'] as double).compareTo(b['km'] as double));
    return out;
  }

  Future<String> _createRideRequest({
    required String userId,
    required LatLng origin,
    required String originAddress,
    required LatLng destination,
    required String destinationAddress,
    required double fare,
    String currency = "SAR",
    String vehicleType = "car",
  }) async {
    final ref = _db.child('rideRequests').push();
    final id = ref.key!;
    await ref.set({
      'userId': userId,
      'originAddress': originAddress,
      'destinationAddress': destinationAddress,
      'origin': {
        'latitude': origin.latitude,
        'longitude': origin.longitude,
      },
      'destination': {
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
      'fare': fare,
      'currency': currency,
      'vehicleType': vehicleType, // نص صريح
      'createdAt': ServerValue.timestamp,
      'status': 'searching',
      'driverId': 'waiting',
    });
    return id;
  }

  Future<void> _offerDriver(String driverId, String reqId) async {
    await _db.child('drivers/$driverId/newRideRequestId').set(reqId);
    await _db.child('drivers/$driverId').update({
      'newRideStatus': 'incoming',
      'currentRideId': reqId,
    });
    await _db.child('rideRequests/$reqId').update({
      'targetDriverId': driverId,
      'status': 'searching',
    });
  }

  Future<void> _clearDriverOffer(String driverId, String reqId) async {
    // لما بنعمل skip لسواق، نفضي العرض منه ومن الطلب
    await _db.child('drivers/$driverId/newRideRequestId').remove();
    await _db.child('drivers/$driverId').update({
      'currentRideId': null,
      'newRideStatus': 'idle',
    });
    // يفضّل كمان نفضي التارجت على الطلب لو لسه نفس req
    final tSnap = await _db.child('rideRequests/$reqId/targetDriverId').get();
    if (tSnap.exists && tSnap.value?.toString() == driverId) {
      await _db.child('rideRequests/$reqId/targetDriverId').remove();
    }
  }

  // --------- Sanitizers / Readers ---------

  String _asCleanString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is num || v is bool) return v.toString();
    return ''; // تجاهل أي Map/List
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  /// يأخذ أي قيمة vehicleType (مهما كانت) ويطلع String سليم
  /// - لو Map فيها 'vehicleType' => خدها
  /// - لو String => رجّعها
  /// - غير كده => ''
  String _sanitizeVehicleType(dynamic vt) {
    if (vt is String) return vt.trim();
    if (vt is Map && vt['vehicleType'] is String) {
      return (vt['vehicleType'] as String).trim();
    }
    return '';
  }

  /// تكوين DriverProfile من drivers/<id> فقط (زائد car_details)
  Future<DriverProfile?> _fetchDriverProfileFromDriversOnly(
      String driverId, {
        String? fallbackVehicleType,
      }) async {
    final snap = await _db.child('drivers/$driverId').get();
    if (!snap.exists || snap.value == null) return null;
    final rootRaw = (snap.value as Map?) ?? {};
    final root = Map<String, dynamic>.from(rootRaw);

    // car_details
    Map<String, dynamic> carDetails = {};
    final rawCd = root['car_details'];
    if (rawCd is Map) {
      carDetails = Map<String, dynamic>.from(rawCd);
    } else if (rawCd is String && rawCd.trim().isNotEmpty) {
      try {
        final decoded = json.decode(rawCd);
        if (decoded is Map) carDetails = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    final name = _asCleanString(root['name'] ?? root['fullName'] ?? root['driverName'] ?? root['driver_name']);
    final phone = _asCleanString(root['phone'] ?? root['phoneNumber'] ?? root['mobile']);

    // vType: من السائق، وإلا fallback
    String vehicleType = _asCleanString(root['vehicleType'] ?? root['carType']);
    if (vehicleType.isEmpty && fallbackVehicleType != null) {
      vehicleType = fallbackVehicleType;
    }

    final carModel  = _asCleanString(carDetails['carModel'] ?? carDetails['model'] ?? carDetails['car_model']);
    final carColor  = _asCleanString(carDetails['carColor'] ?? carDetails['color'] ?? carDetails['car_color']);
    final carNumber = _asCleanString(
      carDetails['carNumber'] ??
          carDetails['plate'] ??
          carDetails['carPlate'] ??
          carDetails['car_number'] ??
          carDetails['number'],
    );

    final photoUrl = _asCleanString(root['photoUrl'] ?? root['avatar'] ?? root['avatarUrl'] ?? root['image'] ?? root['imageUrl']);
    final rating   = _asDouble(root['rating'] ?? root['rate'] ?? root['stars']);

    return DriverProfile(
      id: driverId,
      name: name,
      phone: phone,
      vehicleType: vehicleType,
      carModel: carModel,
      carColor: carColor,
      carNumber: carNumber,
      photoUrl: photoUrl,
      rating: rating,
    );
  }

  /// (1) لو فيه snapshot داخل الطلب نستخدمه
  /// (2) وإلا نجمع من drivers/<id> + vehicleType من الطلب كـ fallback
  Future<DriverProfile?> _fetchDriverProfileFromRequestOrDrivers(
      String rideId,
      String driverId,
      ) async {
    // اقرأ snapshot من الطلب
    final snapInReq = await _db.child('rideRequests/$rideId/driverSnapshot').get();
    if (snapInReq.value is Map) {
      final raw = Map<String, dynamic>.from(snapInReq.value as Map);

      // نظّف vehicleType
      raw['vehicleType'] = _sanitizeVehicleType(raw['vehicleType']);

      final p = DriverProfile.fromMapFlexible(driverId, raw);
      if (p.name.isNotEmpty || p.phone.isNotEmpty) {
        return p;
      }
    }

    // خُد vehicleType من الطلب كـ fallback
    final vtSnap = await _db.child('rideRequests/$rideId/vehicleType').get();
    final vtClean = _sanitizeVehicleType(vtSnap.value);

    // ارجع بروفايل من drivers/<id> فقط
    return _fetchDriverProfileFromDriversOnly(driverId, fallbackVehicleType: vtClean);
  }

  Future<void> _writeDriverSnapshotIfMissing(String rideId, DriverProfile profile) async {
    final path = _db.child('rideRequests/$rideId/driverSnapshot');
    final snap = await path.get();
    if (!snap.exists) {
      await path.set(profile.toJson());
    }
  }

  // ينتظر نتيجة تجربة سائق واحد: accepted/skip/terminal
  Future<_DriverTryResult> _waitDriverOutcome({
    required String reqId,
    required String driverId,
    required Duration perDriverTimeout,
  }) async {
    final completer = Completer<_DriverTryResult>();
    late StreamSubscription<DatabaseEvent> sub;
    Timer? timer;

    void finish(_DriverTryResult r) {
      if (!completer.isCompleted) completer.complete(r);
    }

    sub = _db.child('rideRequests/$reqId').onValue.listen((ev) async {
      final v = (ev.snapshot.value as Map?) ?? {};
      final status = (v['status'] ?? '').toString();
      final acceptedDriverId = (v['driverId'] ?? '').toString();

      switch (status) {
        case 'accepted':
          if (acceptedDriverId == driverId) {
            finish(const _DriverTryResult.accepted());
          }
          break;

        case 'rejected':
        case 'timeout':
        case 'cancelled_by_driver':
        // رجّع الحالة لـ searching عشان السواق اللي بعده يقدر يشوف الطلب
          await _db.child('rideRequests/$reqId/status').set('searching');
          finish(const _DriverTryResult.skip());
          break;

        case 'cancelled':
        case 'no_driver':
        case 'completed':
          finish(_DriverTryResult.terminal(status));
          break;
      }
    });

    timer = Timer(perDriverTimeout, () {
      finish(const _DriverTryResult.skip());
    });

    final result = await completer.future;
    await sub.cancel();
    timer.cancel();
    return result;
  }

  void _resetLocal() {
    _activeRequestId = null;
  }

  // ---------- Public API ----------
  Future<void> start({
    required LatLng pickup,
    required String pickupAddress,
    required LatLng dropoff,
    required String dropAddress,
    required double fare,
    String currency = "SAR",
    String vehicleType = "car",
    /// onStatus(status, driverId:, requestId:, driver:)
    required void Function(
        String status, {
        String? driverId,
        String? requestId,
        DriverProfile? driver,
        }) onStatus,
    Duration perDriverTimeout = const Duration(seconds: 25),
  }) async {
    _cancelled = false;

    final uid = firebaseAuth.currentUser!.uid;

    final reqId = await _createRideRequest(
      userId: uid,
      origin: pickup,
      originAddress: pickupAddress,
      destination: dropoff,
      destinationAddress: dropAddress,
      fare: fare,
      currency: currency,
      vehicleType: vehicleType,
    );

    _activeRequestId = reqId;
    currentRideRequestId = reqId;
    onStatus('searching', requestId: reqId);

    final drivers = await _getCandidateDrivers(pickup);
    if (_cancelled) return;

    if (drivers.isEmpty) {
      await _db.child('rideRequests/$reqId/status').set('no_driver');
      onStatus('no_driver', requestId: reqId);
      _resetLocal();
      return;
    }

    for (final d in drivers) {
      if (_cancelled || _activeRequestId == null) return;

      final driverId = d['id'] as String;

      // اعرض الطلب لهذا السائق فقط
      await _offerDriver(driverId, reqId);

      // انتظر نتيجة تجربة السائق ده
      final outcome = await _waitDriverOutcome(
        reqId: reqId,
        driverId: driverId,
        perDriverTimeout: perDriverTimeout,
      );

      if (_cancelled || _activeRequestId == null) return;

      if (outcome.type == _DriverTryType.accepted) {
        // جهّز بروفايل نظيف
        final profile = await _fetchDriverProfileFromRequestOrDrivers(reqId, driverId);

        // لو الـ vehicleType اللي راجع فيه أقواس { } يبقى دي كانت ماب قديمة متحوّلة لـ String
        // في الحالة دي نقرأ المؤكد من الطلب نفسه:
        final vtSnap = await _db.child('rideRequests/$reqId/vehicleType').get();
        final vtClean = _sanitizeVehicleType(vtSnap.value);

        DriverProfile? cleanProfile = profile;
        if (profile != null) {
          cleanProfile = DriverProfile(
            id: profile.id,
            name: profile.name,
            phone: profile.phone,
            vehicleType: vtClean.isNotEmpty
                ? vtClean
                : (profile.vehicleType.contains('{') ? '' : profile.vehicleType),
            carModel: profile.carModel,
            carColor: profile.carColor,
            carNumber: profile.carNumber,
            photoUrl: profile.photoUrl,
            rating: profile.rating,
          );

          // اكتب snapshot نظيف (overwrite = true) لتنضيف أي بيانات قديمة غلط
          await _db.child('rideRequests/$reqId/driverSnapshot').set(cleanProfile.toJson());
        }

        onStatus('accepted', driverId: driverId, requestId: reqId, driver: cleanProfile);
        _resetLocal();
        return;
      }

      if (outcome.type == _DriverTryType.terminal) {
        onStatus(outcome.terminalStatus ?? 'cancelled', requestId: reqId);
        _resetLocal();
        return;
      }

      // skip => نظّف السائق الحالي وجرب اللي بعده
      await _clearDriverOffer(driverId, reqId);
    }

    // لم يتم القبول من أي سائق
    if (_activeRequestId != null && !_cancelled) {
      await _db.child('rideRequests/$reqId/status').set('no_driver');
      onStatus('no_driver', requestId: reqId);
      _resetLocal();
    }
  }

  Future<void> cancelByUser() async {
    _cancelled = true;
    final reqId = _activeRequestId;

    try {
      if (reqId != null) {
        await _db.child('rideRequests/$reqId/status').set('cancelled');
      }
    } finally {
      _resetLocal();
    }
  }
}

// ======= Types لمخرجات تجربة سائق =======
enum _DriverTryType { accepted, skip, terminal }

class _DriverTryResult {
  final _DriverTryType type;
  final String? terminalStatus;

  const _DriverTryResult.accepted()
      : type = _DriverTryType.accepted,
        terminalStatus = null;

  const _DriverTryResult.skip()
      : type = _DriverTryType.skip,
        terminalStatus = null;

  const _DriverTryResult.terminal(this.terminalStatus)
      : type = _DriverTryType.terminal;
}
