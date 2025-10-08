// lib/features/ride/presentation/screens/main_screen.dart

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';

// Core / Shared
import '../../../../core/constants/global.dart';
import '../../../../core/services/assistant_api/assistants_methods.dart';
import '../../../../shared/state/app_info.dart';

// Entities
import '../../domain/entities/driver_profile.dart';

// Data (Repository)
import '../../data/drivers_repository.dart';

// Screens
import '../../../navigation/presentation/screens/drawer_screen.dart';
import 'precise_pickup_location.dart';
import 'search_placed_screen.dart';

// Widgets
import '../widgets/driver_accepted_sheet.dart';
import '../widgets/pay_fare_amount_dialog.dart';
import '../widgets/location_row.dart';
import '../widgets/suggested_rides_sheet.dart';

typedef DriverAcceptedCallback = void Function(DriverProfile driver, String rideRequestId);

// نخليها global علشان PrecisePickupLocation يقدر يعمل import show pickLocation
LatLng? pickLocation;
loc.Location location = loc.Location();

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.onDriverAccepted});

  final DriverAcceptedCallback? onDriverAccepted;

  @override
  State<MainScreen> createState() => _MainTabPageStateFixedIcon();
}

class _MainTabPageStateFixedIcon extends State<MainScreen> with WidgetsBindingObserver {
  // Google Map
  final Completer<GoogleMapController> _controllerGoogleMap = Completer<GoogleMapController>();
  GoogleMapController? newGoogleMapController;
  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(30.0444, 31.2357),
    zoom: 14.4746,
  );

  // User location/permissions
  Position? userCurrentPosition;
  LocationPermission? _locationPermission;

  // Map overlays
  final Set<Polyline> _polylineSet = {};
  final Set<Marker> _markersSet = {};
  final Set<Circle> _circlesSet = {};

  // Firebase refs/subs
  final DatabaseReference driversRef = FirebaseDatabase.instance.ref().child("drivers");
  StreamSubscription<DatabaseEvent>? _driversSub;

  DatabaseReference? _activeRideRequestRef;
  String? _activeRideRequestId;
  StreamSubscription<DatabaseEvent>? _rideSub;

  // Driver acceptance + live location
  String? _assignedDriverId;
  StreamSubscription<DatabaseEvent>? _assignedDriverLocSub;

  // Nearby idle drivers cache
  final Map<String, _IdleDriver> _nearbyIdleDrivers = {};

  // Car marker icon
  static const int kCarIconSizePx = 100;
  BitmapDescriptor? _driverCarIcon;

  // UI state
  String? _selectedRide; // "car" | "bike"
  bool _isSuggestedSheetOpen = false;
  bool _isRequesting = false;
  double bottomPaddingOfMap = 0;

  // Ride status
  String _currentRideStatus = "searching";
  bool _driverSheetShown = false;

  // ===== Ride flow guards (تمنع التكرار) =====
  String? _lastRideId;                 // آخر rideId شغال
  String? _lastHandledStatus;          // آخر status اتعالج
  bool _acceptedHandled = false;       // علشان ما نعيدش تنفيذ بلوك accepted
  bool _snapshotWrittenOnce = false;   // نمنع تكرار كتابة snapshot
  bool _completionHandled = false;     // منع تكرار اكتمال الرحلة

  // Repository
  late final DriversRepository _driversRepo = DriversRepository();

  // ========= Map Style =========
  Future<void> _applyMapStyle() async {
    if (newGoogleMapController == null) return;
    final isDark = SchedulerBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final stylePath = isDark ? 'assets/map_style/dark_map.json' : 'assets/map_style/light_map.json';
    try {
      final style = await rootBundle.loadString(stylePath);
      await newGoogleMapController!.setMapStyle(style);
    } catch (_) {}
  }

  Future<BitmapDescriptor> _makeCarIcon(String assetPath, int targetWidth) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  Future<void> _loadDriverIconFixed() async {
    try {
      _driverCarIcon ??= await _makeCarIcon('assets/location/car.png', kCarIconSizePx);
      if (mounted) setState(() {});
    } catch (_) {
      _driverCarIcon = null;
    }
  }

  // ====== Location ======
  Future<bool> _ensureLocationReady() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      await Geolocator.openLocationSettings();
      return false;
    }
    _locationPermission = await Geolocator.checkPermission();
    if (_locationPermission == LocationPermission.denied) {
      _locationPermission = await Geolocator.requestPermission();
    }
    if (_locationPermission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }
    return _locationPermission == LocationPermission.always ||
        _locationPermission == LocationPermission.whileInUse;
  }

  Future<void> _goToUserPosition() async {
    if (!await _ensureLocationReady()) return;
    final cPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    userCurrentPosition = cPosition;

    final latLng = LatLng(cPosition.latitude, cPosition.longitude);
    final cam = CameraPosition(target: latLng, zoom: 15);
    if (newGoogleMapController != null) {
      await newGoogleMapController!.animateCamera(CameraUpdate.newCameraPosition(cam));
    }

    await AssistantsMehods.searchAddressForGeographCoOrdinates(cPosition, context);
  }

  // ====== Nearby drivers (idle) ======
  void _startListeningNearbyDrivers() {
    if (userCurrentPosition == null) {
      Future.delayed(const Duration(milliseconds: 500), _startListeningNearbyDrivers);
      return;
    }

    _driversSub?.cancel();
    _driversSub = driversRef.onValue.listen((event) async {
      if (_assignedDriverId != null) return; // لو في سائق مقبول، بلاش نرسم الباقي

      final data = event.snapshot.value;
      if (data is! Map) return;

      if (_driverCarIcon == null) {
        await _loadDriverIconFixed();
        if (_driverCarIcon == null) return;
      }

      final Map<String, Marker> latestMarkers = {};
      _nearbyIdleDrivers.clear();

      data.forEach((driverId, driverData) {
        if (driverData is! Map) return;
        if (driverData["newRideStatus"] != "idle") return;

        final location = driverData["location"];
        if (location is! Map) return;

        final double? driverLat = (location["lat"] as num?)?.toDouble();
        final double? driverLng = (location["lng"] as num?)?.toDouble();
        if (driverLat == null || driverLng == null || userCurrentPosition == null) return;

        final distanceInMeters = Geolocator.distanceBetween(
          userCurrentPosition!.latitude,
          userCurrentPosition!.longitude,
          driverLat,
          driverLng,
        );
        if (distanceInMeters > 10000) return; // 10 كم

        final double rotation = (driverData['heading'] as num?)?.toDouble() ?? 0.0;

        _nearbyIdleDrivers[driverId] = _IdleDriver(
          pos: LatLng(driverLat, driverLng),
          distanceMeters: distanceInMeters,
          rotation: rotation,
        );

        latestMarkers[driverId] = Marker(
          markerId: MarkerId("driver_$driverId"),
          position: LatLng(driverLat, driverLng),
          icon: _driverCarIcon!,
          rotation: rotation,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: InfoWindow(
            title: "سائق متاح 🚖",
            snippet: "يبعد ${(distanceInMeters / 1000).toStringAsFixed(1)} كم",
          ),
          zIndex: 1,
        );
      });

      setState(() {
        _markersSet.removeWhere((m) => m.markerId.value.startsWith("driver_"));
        _markersSet.addAll(latestMarkers.values);
      });
    });
  }

  // ====== Lifecycle ======
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _applyMapStyle();
      await _loadDriverIconFixed();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _driversSub?.cancel();
    _rideSub?.cancel();
    _assignedDriverLocSub?.cancel();
    newGoogleMapController?.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _applyMapStyle();
    super.didChangePlatformBrightness();
  }

  // ====== Drawing ======

  LatLngBounds _safeBounds(LatLng a, LatLng b) {
    final sw = LatLng(
      a.latitude < b.latitude ? a.latitude : b.latitude,
      a.longitude < b.longitude ? a.longitude : b.longitude,
    );
    final ne = LatLng(
      a.latitude > b.latitude ? a.latitude : b.latitude,
      a.longitude > b.longitude ? a.longitude : b.longitude,
    );
    return LatLngBounds(southwest: sw, northeast: ne);
  }

  Future<void> _drawPolylineFromOriginToDestination(bool darkTheme) async {
    final pickup = context.read<AppInfo>().userPickupLocation;
    final dropoff = context.read<AppInfo>().userDropOffLocation;
    if (pickup == null || dropoff == null) return;

    final directionDetails = await AssistantsMehods.obtainOriginToDestinationDirectionDetails(
      LatLng(pickup.locationLatitude!, pickup.locationLongitude!),
      LatLng(dropoff.locationLatitude!, dropoff.locationLongitude!),
    );
    if (directionDetails == null) return;

    if (!mounted) return;
    setState(() => tripDirectionDetailsInfo = directionDetails);

    final decoded = PolylinePoints.decodePolyline(directionDetails.e_points!);
    final coordinates = decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();

    setState(() {
      _polylineSet.removeWhere((p) => p.polylineId.value == "route" || p.polylineId.value.startsWith("live_"));
      _polylineSet.add(Polyline(
        polylineId: const PolylineId("route"),
        color: darkTheme ? Colors.purpleAccent : Colors.blue,
        width: 5,
        points: coordinates,
      ));

      _markersSet.removeWhere((m) => m.markerId.value == "pickup" || m.markerId.value == "dropoff");
      _markersSet.add(Marker(
        markerId: const MarkerId("pickup"),
        position: LatLng(pickup.locationLatitude!, pickup.locationLongitude!),
        infoWindow: const InfoWindow(title: "نقطة البداية"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
      _markersSet.add(Marker(
        markerId: const MarkerId("dropoff"),
        position: LatLng(dropoff.locationLatitude!, dropoff.locationLongitude!),
        infoWindow: const InfoWindow(title: "نقطة الوصول"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    });

    final bounds = _safeBounds(
      LatLng(pickup.locationLatitude!, pickup.locationLongitude!),
      LatLng(dropoff.locationLatitude!, dropoff.locationLongitude!),
    );
    newGoogleMapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  Future<void> _drawLiveRoute({
    required LatLng from,
    required LatLng to,
    required String id, // "live_to_pickup" | "live_to_dropoff"
    required bool toDropoff,
  }) async {
    final details = await AssistantsMehods.obtainOriginToDestinationDirectionDetails(from, to);
    if (details == null) return;

    final points = PolylinePoints.decodePolyline(details.e_points!);
    final coords = points.map((p) => LatLng(p.latitude, p.longitude)).toList();

    setState(() {
      _polylineSet.removeWhere((pl) => pl.polylineId.value == "route" || pl.polylineId.value.startsWith("live_"));
      _polylineSet.add(Polyline(
        polylineId: PolylineId(id),
        color: toDropoff ? Colors.orange : Colors.blue,
        width: 5,
        points: coords,
      ));

      _markersSet.removeWhere((m) =>
      m.markerId.value == "driver_active" ||
          m.markerId.value == "target" ||
          m.markerId.value == "pickup" ||
          m.markerId.value == "dropoff");

      _markersSet.add(Marker(
        markerId: const MarkerId("driver_active"),
        position: from,
        icon: _driverCarIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        zIndex: 2,
      ));

      _markersSet.add(Marker(
        markerId: const MarkerId("target"),
        position: to,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          toDropoff ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen,
        ),
        zIndex: 1,
      ));
    });

    final bounds = _safeBounds(from, to);
    await newGoogleMapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 70),
    );
  }

  Future<void> _drawInitialDriverRoute({
    required String driverId,
    required bool toDropoff,
  }) async {
    final locSnap = await FirebaseDatabase.instance.ref("drivers/$driverId/location").get();
    if (locSnap.value is! Map) return;

    final m = Map<String, dynamic>.from(locSnap.value as Map);
    final double? lat = (m["lat"] as num?)?.toDouble();
    final double? lng = (m["lng"] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final driverPos = LatLng(lat, lng);

    if (toDropoff) {
      final drop = context.read<AppInfo>().userDropOffLocation;
      if (drop == null) return;
      await _drawLiveRoute(
        from: driverPos,
        to: LatLng(drop.locationLatitude!, drop.locationLongitude!),
        id: "live_to_dropoff",
        toDropoff: true,
      );
      updateReachingTimeToUserDropOffLocation(driverPos);
    } else {
      final pick = context.read<AppInfo>().userPickupLocation;
      if (pick == null) return;
      await _drawLiveRoute(
        from: driverPos,
        to: LatLng(pick.locationLatitude!, pick.locationLongitude!),
        id: "live_to_pickup",
        toDropoff: false,
      );
      updateArrivalTimeToUserPickUpLocation(driverPos);
    }
  }

  // ====== Request flow ======
  Future<void> saveRideRequestInformation(String vehicleType) async {
    if (_isRequesting) return;

    final originLocation = context.read<AppInfo>().userPickupLocation;
    final destinationLocation = context.read<AppInfo>().userDropOffLocation;
    if (originLocation == null || destinationLocation == null) {
      Fluttertoast.showToast(msg: "الرجاء تحديد موقع الانطلاق والوجهة");
      return;
    }

    final dir = tripDirectionDetailsInfo ??
        await AssistantsMehods.obtainOriginToDestinationDirectionDetails(
          LatLng(originLocation.locationLatitude!, originLocation.locationLongitude!),
          LatLng(destinationLocation.locationLatitude!, destinationLocation.locationLongitude!),
        );
    if (dir == null) {
      Fluttertoast.showToast(msg: "تعذر حساب المسافة/الوقت للأجرة.");
      return;
    }

    final double fare = (vehicleType == "bike")
        ? AssistantsMehods.calculateFareBike(dir)
        : AssistantsMehods.calculateFareAmountFormOriginToDestination(dir);

    final Map originLocationMap = {
      "latitude": originLocation.locationLatitude.toString(),
      "longitude": originLocation.locationLongitude.toString(),
    };
    final Map destinationLocationMap = {
      "latitude": destinationLocation.locationLatitude.toString(),
      "longitude": destinationLocation.locationLongitude.toString(),
    };

    final referenceRideRequest = FirebaseDatabase.instance.ref().child("rideRequests").push();

    final Map userInformationMap = {
      "origin": originLocationMap,
      "destination": destinationLocationMap,
      "time": DateTime.now().toIso8601String(),
      "userName": userModelCurrentInfo?.name ?? "",
      "userPhone": userModelCurrentInfo?.phone ?? "",
      "originAddress": originLocation.locationName,
      "destinationAddress": destinationLocation.locationName,
      "driverId": "waiting",
      "status": "searching",
      "vehicleType": vehicleType,
      "fare": fare,
      "currency": "SAR",
      "fareAmount": fare,
      "distance_m": dir.distance_value,
      "duration_text": dir.duration_text,
      "userId": firebaseAuth.currentUser?.uid ?? "",
    };

    await referenceRideRequest.set(userInformationMap);

    setState(() {
      _activeRideRequestRef = referenceRideRequest;
      _activeRideRequestId = referenceRideRequest.key;
      _lastRideId = referenceRideRequest.key;
      _isRequesting = true;
      _assignedDriverId = null;
      _driverSheetShown = false;
      _currentRideStatus = "searching";
      _lastHandledStatus = null;
      _acceptedHandled = false;
      _snapshotWrittenOnce = false;
      _completionHandled = false;
    });

    // اختر أقرب سائق idle
    final nearestEntry = _pickNearestIdleDriver();
    if (nearestEntry == null) {
      Fluttertoast.showToast(msg: "لا يوجد سائق متاح حاليًا قريب منك");
      await referenceRideRequest.update({"status": "timeout"});
      setState(() => _isRequesting = false);
      return;
    }

    final chosenDriverId = nearestEntry.key;
    await referenceRideRequest.update({"targetDriverId": chosenDriverId});
    await FirebaseDatabase.instance
        .ref("drivers/$chosenDriverId/newRideRequestId")
        .set(referenceRideRequest.key);

    // استمع للتحديثات – معالجة “مدروسة”
    _rideSub?.cancel();
    _rideSub = referenceRideRequest.onValue.listen((ev) async {
      if (ev.snapshot.value == null) return;
      final rideData = Map<String, dynamic>.from(ev.snapshot.value as Map);
      final status = (rideData["status"] ?? "").toString();

      // امنع تكرار نفس الـstatus
      if (_lastHandledStatus == status) return;
      _lastHandledStatus = status;

      _currentRideStatus = status;

      switch (status) {
        case "searching":
          if (mounted && !_isSuggestedSheetOpen) {
            setState(() => _isSuggestedSheetOpen = true);
          }
          break;

        case "accepted": {
          if (_acceptedHandled) break;
          _acceptedHandled = true;

          final didRaw = rideData["driverId"];
          if (didRaw == null || didRaw.toString().isEmpty) {
            debugPrint("!!! accepted بدون driverId");
            break;
          }
          final did = didRaw.toString();
          final rid = _activeRideRequestId; // خليه لوكال

          if (kDebugMode) {
            debugPrint("=== [RIDE ACCEPTED] ===");
            debugPrint("rideId: ${rid ?? '-'}");
            debugPrint("driverId: $did");
          }

          if (mounted) {
            setState(() {
              _assignedDriverId = did;
              _markersSet.removeWhere((m) => m.markerId.value.startsWith("driver_"));
            });
          }

          DriverProfile? profile;

          try {
            if (rid != null) {
              // 1) اقرأ بروفايل من الريبو
              profile = await _driversRepo.getDriverProfileFromRequestOrDrivers(rid, did);

              // 2) نظّف الـ vehicleType واكتب snapshot نظيف مرّة (overwrite=true)
              if (profile != null) {
                final vtFromRide = (rideData['vehicleType'] ?? '').toString().trim();
                final vtClean = vtFromRide.isNotEmpty
                    ? vtFromRide
                    : (profile.vehicleType.contains('{') ? '' : profile.vehicleType);

                final cleanProfile = profile.copyWith(vehicleType: vtClean);
                await _driversRepo.writeDriverSnapshot(rid, cleanProfile, overwrite: true);
                profile = cleanProfile; // اعتمد النسخة النظيفة للعرض
              }
            }
          } catch (e, st) {
            debugPrint("!!! [DRIVER PROFILE] error while building/writing snapshot: $e");
            debugPrint("$st");
          }

          // 3) ارسم المسار + ستريم الموقع
          await _drawInitialDriverRoute(driverId: did, toDropoff: false);
          _attachDriverLocationStream(did);
          Fluttertoast.showToast(msg: "تم قبول رحلتك ✅");

          if (mounted) {
            setState(() {
              _isRequesting = false;
              _isSuggestedSheetOpen = false;
            });
          }

          // 4) اعرض الشيت
          if (!_driverSheetShown && rid != null && profile != null) {
            if (kDebugMode) {
              debugPrint(profile.toPrettyString());
            }
            if (context.mounted) {
              setState(() => _driverSheetShown = true);
              widget.onDriverAccepted?.call(profile, rid);
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                barrierColor: Colors.black54,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                builder: (_) => DriverAcceptedSheet(driver: profile!),
              );
            }
          } else if (profile == null) {
            debugPrint("!!! [DRIVER PROFILE] لا توجد بيانات للسائق $did");
          }

          break;
        }

        case "ontrip":
        case "ongoing":
          if (_assignedDriverId != null) {
            await _drawInitialDriverRoute(driverId: _assignedDriverId!, toDropoff: true);
          }
          break;

        case "arrived":
          Fluttertoast.showToast(msg: "🚖 السائق وصل لمكانك");
          break;

        case "ended":
        case "completed":
          await _handleRideCompleted(rideData);
          break;

        case "rejected":
        case "timeout":
        case "cancelled":
        case "cancelled_by_driver":
          Fluttertoast.showToast(
            msg: status == "rejected"
                ? "تم رفض الطلب"
                : status == "timeout"
                ? "انتهى وقت الطلب"
                : "تم إلغاء الطلب",
          );
          await _cleanupRideRequest(removeFromDb: true);
          if (mounted) setState(() => _isSuggestedSheetOpen = true);
          break;
      }
    });
  }

  MapEntry<String, _IdleDriver>? _pickNearestIdleDriver() {
    _IdleDriver? best;
    String? bestId;

    _nearbyIdleDrivers.forEach((id, driver) {
      if (best == null || driver.distanceMeters < best!.distanceMeters) {
        best = driver;
        bestId = id;
      }
    });

    if (best == null || bestId == null) return null;
    return MapEntry(bestId!, best!);
  }

  void _attachDriverLocationStream(String driverId) {
    _assignedDriverLocSub?.cancel();
    final ref = FirebaseDatabase.instance.ref("drivers/$driverId/location");

    _assignedDriverLocSub = ref.onValue.listen((ev) async {
      final val = ev.snapshot.value;
      if (val is! Map) return;

      final double? lat = (val["lat"] as num?)?.toDouble();
      final double? lng = (val["lng"] as num?)?.toDouble();
      if (lat == null || lng == null) return;

      final driverPos = LatLng(lat, lng);
      final pickup = context.read<AppInfo>().userPickupLocation;
      final dropoff = context.read<AppInfo>().userDropOffLocation;

      if (_currentRideStatus == "accepted" && pickup != null) {
        await _drawLiveRoute(
          from: driverPos,
          to: LatLng(pickup.locationLatitude!, pickup.locationLongitude!),
          id: "live_to_pickup",
          toDropoff: false,
        );
        updateArrivalTimeToUserPickUpLocation(driverPos);
      } else if ((_currentRideStatus == "ontrip" || _currentRideStatus == "ongoing") && dropoff != null) {
        await _drawLiveRoute(
          from: driverPos,
          to: LatLng(dropoff.locationLatitude!, dropoff.locationLongitude!),
          id: "live_to_dropoff",
          toDropoff: true,
        );
        updateReachingTimeToUserDropOffLocation(driverPos);
      } else if (_currentRideStatus == "arrived") {
        setState(() {
          _markersSet.removeWhere((m) => m.markerId.value == "driver_active");
          _markersSet.add(Marker(
            markerId: const MarkerId("driver_active"),
            position: driverPos,
            icon: _driverCarIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            anchor: const Offset(0.5, 0.5),
            flat: true,
            zIndex: 2,
          ));
          _polylineSet.removeWhere((pl) => pl.polylineId.value.startsWith("live_"));
        });
      }
    });
  }

  Future<void> _cleanupRideRequest({bool removeFromDb = false}) async {
    try {
      await _rideSub?.cancel();
      _rideSub = null;
      await _assignedDriverLocSub?.cancel();
      _assignedDriverLocSub = null;
      if (removeFromDb && _activeRideRequestRef != null) {
        await _activeRideRequestRef!.remove();
      }
    } catch (_) {}

    // صفّر فلاجز الحراسة (مهم جداً للرحلة اللي بعدها)
    _snapshotWrittenOnce = false;
    _acceptedHandled = false;
    _lastHandledStatus = null;
    _lastRideId = null;
    _completionHandled = false;

    if (mounted) {
      setState(() {
        _activeRideRequestRef = null;
        _activeRideRequestId = null;
        _isRequesting = false;
        _assignedDriverId = null;
        _driverSheetShown = false;
        _currentRideStatus = "searching";
        _polylineSet.clear();
        _markersSet.removeWhere((m) =>
        m.markerId.value.startsWith("driver_") ||
            m.markerId.value == "driver_active" ||
            m.markerId.value == "target" ||
            m.markerId.value == "pickup" ||
            m.markerId.value == "dropoff");
      });
    }
  }

  // ===== اكتمال الرحلة =====
  Future<void> _handleRideCompleted(Map<String, dynamic> rideData) async {
    if (_completionHandled) return;
    _completionHandled = true;

    final rid = _activeRideRequestId;
    final did = (rideData['driverId'] ?? '').toString();
    final fareRaw = rideData['fare'];
    final double fare = (fareRaw is num) ? fareRaw.toDouble() : double.tryParse('$fareRaw') ?? 0.0;

    final originAddress = (rideData['originAddress'] ?? '').toString();
    final destinationAddress = (rideData['destinationAddress'] ?? '').toString();
    final distanceM = (rideData['distance_m'] is num) ? (rideData['distance_m'] as num).toDouble() : 0.0;
    final durationText = (rideData['duration_text'] ?? '').toString();
    final currency = (rideData['currency'] ?? 'SAR').toString();
    final userId = firebaseAuth.currentUser?.uid ?? '';

    try {
      // 1) حفظ تاريخ الرحلة تحت المستخدم
      if (rid != null && userId.isNotEmpty) {
        final payload = {
          'rideId': rid,
          'driverId': did,
          'fare': fare,
          'currency': currency,
          'originAddress': originAddress,
          'destinationAddress': destinationAddress,
          'distance_m': distanceM,
          'duration_text': durationText,
          'endedAt': DateTime.now().toIso8601String(),
        };
        await FirebaseDatabase.instance.ref('users/$userId/history/$rid').set(payload);
      }

      // 2) نافذة الدفع
      await showDialog(
        context: context,
        builder: (_) => PayFareAmountDialog(fareAmount: fare),
      );

      // 3) شيت التقييم
      if (context.mounted && rid != null && did.isNotEmpty) {
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black54,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          builder: (_) => RatingAndTipSheet(
            fare: fare,
            onSubmit: (rating, tipAmount, note) async {
              try {
                await FirebaseDatabase.instance.ref('drivers/$did/ratings/$rid').set({
                  'rating': rating,
                  'tip': tipAmount, // هيكون 0.0 من الويجت
                  'note': note ?? '',
                  'createdAt': DateTime.now().toIso8601String(),
                });
                Fluttertoast.showToast(msg: "شكراً لتقييمك 🌟");
              } catch (e) {
                Fluttertoast.showToast(msg: "تعذر حفظ التقييم");
              }
            },
          ),
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[_handleRideCompleted] $e');
        debugPrint('$st');
      }
    } finally {
      await _cleanupRideRequest(removeFromDb: true);
    }
  }

  // ===== ETA badge =====
  String driverRideStatus = "Driver is coming";
  bool requestPositionInfo = true;

  updateArrivalTimeToUserPickUpLocation(LatLng driverCurrentPositionLatLng) async {
    if (!requestPositionInfo || userCurrentPosition == null) return;
    requestPositionInfo = false;

    final userPickUpPosition = LatLng(userCurrentPosition!.latitude, userCurrentPosition!.longitude);

    final directionDetailsInfo =
    await AssistantsMehods.obtainOriginToDestinationDirectionDetails(
      driverCurrentPositionLatLng,
      userPickUpPosition,
    );
    if (directionDetailsInfo == null) {
      requestPositionInfo = true;
      return;
    }
    setState(() {
      driverRideStatus = "السائق قادم ${directionDetailsInfo.duration_text}";
    });

    requestPositionInfo = true;
  }

  updateReachingTimeToUserDropOffLocation(LatLng driverCurrentPositionLatLng) async {
    if (!requestPositionInfo) return;
    requestPositionInfo = false;

    final dropOffLocation = context.read<AppInfo>().userDropOffLocation;
    if (dropOffLocation == null) {
      requestPositionInfo = true;
      return;
    }

    final userDirectionPosition =
    LatLng(dropOffLocation.locationLatitude!, dropOffLocation.locationLongitude!);

    final directionDetailsInfo =
    await AssistantsMehods.obtainOriginToDestinationDirectionDetails(
      driverCurrentPositionLatLng,
      userDirectionPosition,
    );

    if (directionDetailsInfo == null) {
      requestPositionInfo = true;
      return;
    }
    setState(() {
      driverRideStatus = "متجه للوجهة ${directionDetailsInfo.duration_text}";
    });

    requestPositionInfo = true;
  }

  // ===== UI =====
  void _openSuggestedRidesSheet() {
    setState(() {
      _isSuggestedSheetOpen = true;
      bottomPaddingOfMap = 260;
    });
  }

  void _closeSuggestedRidesSheet() {
    setState(() {
      _isSuggestedSheetOpen = false;
      bottomPaddingOfMap = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = MediaQuery.of(context).platformBrightness == Brightness.dark;

    final hasFrom = context.select<AppInfo, bool>((a) => a.userPickupLocation != null);
    final hasTo = context.select<AppInfo, bool>((a) => a.userDropOffLocation != null);

    final fromName = context.select<AppInfo, String?>((a) => a.userPickupLocation?.locationName);
    final toName = context.select<AppInfo, String?>((a) => a.userDropOffLocation?.locationName);

    return Scaffold(
      drawer: const DrawerScreen(),
      body: Stack(
        children: [
          GoogleMap(
            padding: EdgeInsets.fromLTRB(10, 30, 10, bottomPaddingOfMap),
            mapType: MapType.normal,
            initialCameraPosition: _kGooglePlex,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            zoomGesturesEnabled: true,
            polylines: _polylineSet,
            markers: _markersSet,
            circles: _circlesSet,
            onMapCreated: (GoogleMapController controller) async {
              if (!_controllerGoogleMap.isCompleted) _controllerGoogleMap.complete(controller);
              newGoogleMapController = controller;

              await _applyMapStyle();
              await _loadDriverIconFixed();

              await _goToUserPosition();
              _startListeningNearbyDrivers();

              if (mounted) setState(() {});
            },
          ),

          // زر القائمة
          Positioned(
            top: 50,
            left: 20,
            child: Builder(
              builder: (ctx) => GestureDetector(
                onTap: () => Scaffold.of(ctx).openDrawer(),
                child: CircleAvatar(
                  backgroundColor: darkTheme ? Colors.purple : Colors.white,
                  child: Icon(
                    Icons.menu,
                    color: darkTheme ? Colors.white : Colors.lightBlue,
                  ),
                ),
              ),
            ),
          ),

          // شارة حالة السائق
          if (_activeRideRequestId != null)
            Positioned(
              top: 50,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: darkTheme ? Colors.black.withOpacity(.6) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: Text(
                  driverRideStatus,
                  style: TextStyle(
                    color: darkTheme ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // البوكس السفلي
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 3)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LocationRow(
                      icon: Icons.my_location,
                      label: 'من',
                      value: fromName ?? 'لم يتم تحديد العنوان',
                    ),
                    const Divider(color: Colors.grey, thickness: 1, height: 20),
                    GestureDetector(
                      onTap: () async {
                        final res = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SearchPlaced()),
                        );
                        if (!mounted) return;

                        if (res == "obtainedDropoff") {
                          await _drawPolylineFromOriginToDestination(darkTheme);
                        }
                      },
                      child: LocationRow(
                        icon: Icons.location_on,
                        label: 'إلى',
                        value: toName ?? 'إلى أين؟',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final res = await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const PrecisePickupLocation()),
                              );
                              if (!mounted) return;

                              if (res == "pickupUpdated" && hasTo) {
                                await _drawPolylineFromOriginToDestination(darkTheme);
                              }
                            },
                            icon: const Icon(Icons.edit_location_alt, size: 18),
                            label: const Text('تغيير نقطة الانطلاق'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: darkTheme ? Colors.purple : Colors.blue,
                              foregroundColor: darkTheme ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (hasFrom && hasTo) ? _openSuggestedRidesSheet : null,
                            icon: const Icon(Icons.local_taxi, size: 18),
                            label: const Text('اطلب مشوار'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: darkTheme ? Colors.purple : Colors.blue,
                              foregroundColor: darkTheme ? Colors.black : Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              disabledForegroundColor: Colors.grey.shade600,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // الشيت المقترح
          if (_isSuggestedSheetOpen)
            Positioned.fill(
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.5,
                minChildSize: 0.25,
                maxChildSize: 0.9,
                builder: (context, scrollController) {
                  return SafeArea(
                    top: false,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                      ),
                      child: SuggestedRidesSheet(
                        darkTheme: darkTheme,
                        fromName: fromName,
                        toName: toName,
                        selectedRide: _selectedRide,
                        isRequesting: _isRequesting,
                        listScrollController: scrollController,
                        onSelect: (v) => setState(() => _selectedRide = v),
                        onClose: _closeSuggestedRidesSheet,
                        onConfirm: saveRideRequestInformation,
                        onCancelSearch: () async {
                          // هنا تلغي الطلب اللي شغال
                          try {
                            if (_activeRideRequestRef != null) {
                              await _activeRideRequestRef!.update({"status": "cancelled"});
                            }
                          } catch (_) {}
                          await _cleanupRideRequest(removeFromDb: true);
                          Fluttertoast.showToast(msg: "تم إلغاء البحث عن سائق");
                        },
                      ),


                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ===== Helpers =====

class _IdleDriver {
  final LatLng pos;
  final double distanceMeters;
  final double rotation;
  _IdleDriver({required this.pos, required this.distanceMeters, required this.rotation});
}

// ====== Rating Sheet (بدون بقشيش، نجوم صفراء) ======
class RatingAndTipSheet extends StatefulWidget {
  final double fare;
  final Future<void> Function(double rating, double tipAmount, String? note) onSubmit;
  const RatingAndTipSheet({super.key, required this.fare, required this.onSubmit});

  @override
  State<RatingAndTipSheet> createState() => _RatingAndTipSheetState();
}

class _RatingAndTipSheetState extends State<RatingAndTipSheet> {
  double _rating = 5.0;
  final _noteCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: Material(
          color: isDark ? const Color(0xFF121212) : Colors.white,
          child: Padding(
            padding: MediaQuery.of(context).viewInsets,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44, height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.emoji_transportation_rounded),
                      const SizedBox(width: 8),
                      Text(
                        'كيف كانت رحلتك؟',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'إغلاق',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // نجوم صفراء
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final idx = i + 1;
                      final filled = _rating >= idx;
                      return IconButton(
                        onPressed: () => setState(() => _rating = idx.toDouble()),
                        iconSize: 32,
                        splashRadius: 22,
                        icon: Icon(
                          filled ? Icons.star_rounded : Icons.star_border_rounded,
                          color: filled ? Colors.amber : (isDark ? Colors.white24 : Colors.black26),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'ملاحظاتك (اختياري)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'اكتب ملاحظاتك عن الرحلة…',
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(.06) : Colors.black.withOpacity(.03),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _loading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('إرسال التقييم'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _loading = true);
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    try {
      await widget.onSubmit(_rating, 0.0, note); // tipAmount = 0.0
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
