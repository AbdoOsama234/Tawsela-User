// lib/features/ride/presentation/controllers/ride_controller.dart
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart'; // لحساب المسافة بين الراكب والسائق
import 'package:users/features/ride/data/drivers_repository.dart';
import 'package:users/features/ride/data/ride_request_repository.dart';
import 'package:users/features/ride/domain/entities/driver_profile.dart';

class RideController extends ChangeNotifier {
  final DriversRepository driversRepo;
  final RideRequestRepository rideRepo;

  RideController({required this.driversRepo, required this.rideRepo});

  // ---------- UI State ----------
  String? selectedRide; // car | bike
  bool isSuggestedOpen = false;
  bool isRequesting = false;
  String currentStatus = 'searching';

  // Ride Request
  String? activeRideRequestId;
  DatabaseReference? _activeRideRef;

  // ---------- Map State ----------
  final Set<Polyline> polylines = {};
  final Set<Marker> markers = {};

  // ---------- Driver ----------
  String? assignedDriverId;
  bool driverSheetShown = false;

  // ---------- Streams ----------
  StreamSubscription<Map<String, dynamic>?>? _rideSub;
  StreamSubscription<Map<String, dynamic>?>? _driverLocSub;   // (احتياطي) لو هتسمع لايف موقع السائق
  StreamSubscription<Map<String, dynamic>?>? _driversNearbySub;

  // ---------- Nearby drivers cache ----------
  final Map<String, _IdleDriver> nearbyIdleDrivers = {};

  // ---------- Lifecycle ----------
  @override
  void dispose() {
    disposeAll();
    super.dispose();
  }

  void disposeAll() {
    _rideSub?.cancel();
    _rideSub = null;
    _driverLocSub?.cancel();
    _driverLocSub = null;
    _driversNearbySub?.cancel();
    _driversNearbySub = null;
  }

  // ---------- Public actions ----------
  void openSuggested() {
    isSuggestedOpen = true;
    notifyListeners();
  }

  void closeSuggested() {
    isSuggestedOpen = false;
    notifyListeners();
  }

  void selectRide(String id) {
    selectedRide = id;
    notifyListeners();
  }

  /// يبدأ متابعة السائقين القريبين (idle) ويرسم ماركراتهم على الخريطة
  Future<void> startWatchingNearbyDrivers(
      LatLng userPos,
      BitmapDescriptor driverIcon,
      ) async {
    _driversNearbySub?.cancel();
    _driversNearbySub = driversRepo.watchDrivers().listen((data) {
      // لو اتعيّن سائق خلاص، بلاش نعرض الـ idle
      if (data == null || assignedDriverId != null) return;

      final latest = <Marker>[];
      nearbyIdleDrivers.clear();

      data.forEach((driverId, raw) {
        if (raw is! Map) return;
        if (raw['newRideStatus'] != 'idle') return;

        final loc = raw['location'];
        if (loc is! Map) return;

        final lat = (loc['lat'] as num?)?.toDouble();
        final lng = (loc['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) return;

        final rot = (raw['heading'] as num?)?.toDouble() ?? 0.0;

        nearbyIdleDrivers[driverId] = _IdleDriver(
          pos: LatLng(lat, lng),
          rotation: rot,
        );

        latest.add(
          Marker(
            markerId: MarkerId('driver_$driverId'),
            position: LatLng(lat, lng),
            icon: driverIcon,
            rotation: rot,
            anchor: const Offset(0.5, 0.5),
            flat: true,
            zIndex: 1,
          ),
        );
      });

      // امسح أي ماركرات idle قديمة واضف الجديدة
      markers.removeWhere((m) => m.markerId.value.startsWith('driver_'));
      markers.addAll(latest);
      notifyListeners();
    });
  }

  /// اختيار أقرب سائق فعليًا باستخدام مسافة جيو
  MapEntry<String, _IdleDriver>? pickNearestDriver(LatLng userPos) {
    String? bestId;
    _IdleDriver? best;
    double bestDist = double.infinity;

    nearbyIdleDrivers.forEach((id, d) {
      final dist = Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        d.pos.latitude,
        d.pos.longitude,
      );
      if (dist < bestDist) {
        bestDist = dist;
        best = d;
        bestId = id;
      }
    });

    if (best == null || bestId == null) return null;
    return MapEntry(bestId!, best!);
  }

  /// يكتب طلب، يوجّه لسائق مستهدف، يسمع حالة الطلب ويجِهّز بروفايل السائق عند القبول
  Future<void> createAndListenRide({
    required Map<String, dynamic> payload,
    required LatLng userPos,
    required Future<void> Function(
        String driverId,
        String rideId,
        DriverProfile? profile,
        )
    onAccepted,
    required Future<void> Function() onNoDriver,
  }) async {
    if (isRequesting) return;

    isRequesting = true;
    driverSheetShown = false;
    currentStatus = 'searching';
    notifyListeners();

    // 1) أنشئ مرجع الطلب واكتب البيانات
    final ref = rideRepo.createRideRequestRef();
    await rideRepo.setRideRequest(ref, payload);

    _activeRideRef = ref;
    activeRideRequestId = ref.key;

    // 2) اختَر أقرب سائق idle
    final chosen = pickNearestDriver(userPos);
    if (chosen == null) {
      await ref.update({'status': 'timeout'});
      isRequesting = false;
      notifyListeners();
      await onNoDriver();
      return;
    }

    final chosenDriverId = chosen.key;

    await ref.update({'targetDriverId': chosenDriverId});
    await FirebaseDatabase.instance
        .ref('drivers/$chosenDriverId/newRideRequestId')
        .set(ref.key);

    // 3) استمع لحالة الطلب
    _rideSub?.cancel();
    _rideSub = rideRepo.watchRideRequest(ref).listen((data) async {
      if (data == null) return;

      final status = (data['status'] ?? '').toString();
      currentStatus = status;

      // ======== حالة: قبول السائق ========
      final rawId = data['driverId']?.toString();
      final acceptedWithDriver = status == 'accepted' && rawId != null && rawId.isNotEmpty;

      if (acceptedWithDriver) {
        // احمِ من التكرار لو الاستريم بعت أكتر من مرّة
        if (driverSheetShown) return;

        assignedDriverId = rawId;

        // أوقف ستريم السائقين القريبين نهائيًا
        await _driversNearbySub?.cancel();
        _driversNearbySub = null;

        // DEBUG: اطبع شكل الداتا لتتبع مشكلة الـ null
        final db = FirebaseDatabase.instance.ref();
        try {
          final rid = activeRideRequestId;
          debugPrint('[RIDECONTROLLER] accepted -> driverId=$assignedDriverId rideId=$rid');

          final driverNode =
              (await db.child('drivers/$assignedDriverId').get()).value;
          final driverProfileNode =
              (await db.child('drivers/$assignedDriverId/profile').get()).value;
          final reqSnapshot = rid == null
              ? null
              : (await db.child('rideRequests/$rid/driverSnapshot').get()).value;

          debugPrint('[RIDECONTROLLER] RAW driver node: $driverNode');
          debugPrint('[RIDECONTROLLER] RAW driver profile node: $driverProfileNode');
          debugPrint('[RIDECONTROLLER] RAW request snapshot: $reqSnapshot');
        } catch (e) {
          debugPrint('[RIDECONTROLLER] DEBUG fetch error: $e');
        }

        // نظافة ماركرات idle وإخفاء الشيت المقترح
        markers.removeWhere((m) => m.markerId.value.startsWith('driver_'));
        isRequesting = false;
        isSuggestedOpen = false;

        // حاول تجيب بروفايل السائق
        final profile = await driversRepo.getDriverProfileFromRequestOrDrivers(
          activeRideRequestId!,
          assignedDriverId!,
        );

        if (profile == null) {
          debugPrint('[RIDECONTROLLER] profile == null (after fetch). Check keys/mapping.');
        } else {
          debugPrint('[RIDECONTROLLER] profile OK: ${profile.name} | ${profile.phone}');
        }

        // اكتب Snapshot داخل الطلب لو مش موجود
        if (profile != null) {
          await driversRepo.writeDriverSnapshotIfMissing(activeRideRequestId!, profile);
        }

        // منع تكرار عرض الشيت/الواجهة
        driverSheetShown = true;

        notifyListeners();
        await onAccepted(assignedDriverId!, activeRideRequestId!, profile);
        return;
      }

      // ======== اكتمال/نهاية الرحلة ========
      if (status == 'completed' || status == 'ended') {
        await cleanup(removeFromDb: true);
      }

      // ======== حالات الرفض/الوقت/الإلغاء ========
      if (status == 'rejected' ||
          status == 'timeout' ||
          status == 'cancelled' ||
          status == 'cancelled_by_driver') {
        await cleanup(removeFromDb: true);
        isSuggestedOpen = true;
        notifyListeners();
      }
    });
  }

  /// تنظيف كل ما يخص الرحلة الحالية
  Future<void> cleanup({bool removeFromDb = false}) async {
    try {
      await _rideSub?.cancel();
      _rideSub = null;
      await _driverLocSub?.cancel();
      _driverLocSub = null;

      if (removeFromDb && _activeRideRef != null) {
        await rideRepo.removeRideRequest(_activeRideRef!);
      }
    } finally {
      _activeRideRef = null;
      activeRideRequestId = null;

      isRequesting = false;
      assignedDriverId = null;
      driverSheetShown = false;
      currentStatus = 'searching';

      // نظافة الخريطة
      markers.removeWhere((m) =>
      m.markerId.value.startsWith('driver_') ||
          m.markerId.value == 'driver_active' ||
          m.markerId.value == 'target' ||
          m.markerId.value == 'pickup' ||
          m.markerId.value == 'dropoff');
      polylines.clear();

      notifyListeners();
    }
  }
}

// موديل داخلي بسيط لتمثيل السائق الـ idle
class _IdleDriver {
  final LatLng pos;
  final double rotation;
  _IdleDriver({required this.pos, required this.rotation});
}
