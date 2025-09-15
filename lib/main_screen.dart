import 'dart:async';
import 'dart:ui' as ui; // لإعادة تحجيم صورة الأيقونة
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as loc;
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';

import 'package:users/Assistants/assistants_methods.dart';
import 'package:users/global/global.dart';
import 'package:users/infoHandler/app_info.dart';
import 'package:users/pay_fare_amount_dialog.dart';
import 'package:users/screens/drawer_screen.dart';
import 'package:users/screens/precise_pickup_location.dart';
import 'package:users/screens/search_placed_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainTabPageStateFixedIcon();
}

LatLng? pickLocation;
loc.Location location = loc.Location();

class _MainTabPageStateFixedIcon extends State<MainScreen> with WidgetsBindingObserver {
  final Completer<GoogleMapController> _controllerGoogleMap = Completer<GoogleMapController>();
  GoogleMapController? newGoogleMapController;

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(30.0444, 31.2357),
    zoom: 14.4746,
  );

  Position? userCurrentPosition;
  LocationPermission? _locationPermission;

  // Map overlays
  final Set<Polyline> _polylineSet = {};
  final Set<Marker> _markersSet = {};
  final Set<Circle> _circlesSet = {};

  // Firebase reference + subscription
  final DatabaseReference driversRef = FirebaseDatabase.instance.ref().child("drivers");
  StreamSubscription<DatabaseEvent>? _driversSub;

  // الطلب النشط
  DatabaseReference? _activeRideRequestRef;
  String? _activeRideRequestId;
  StreamSubscription<DatabaseEvent>? _rideSub;

  // السائق المقبول
  String? _assignedDriverId;

  // أيقونة العربية (ثابت الحجم)
  static const int kCarIconSizePx = 100;
  BitmapDescriptor? _driverCarIcon;

  // UI state
  String? _selectedRide; // "car" | "bike"
  bool _isSuggestedSheetOpen = false;
  bool _isRequesting = false; // جاري البحث عن سائق
  double bottomPaddingOfMap = 0;

  // ================= Map Style =================
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

  // ----- صلاحيات وخدمة الموقع -----
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

  // ================== متابعة السواقين القريبين (قبل القبول) ==================
  void _startListeningNearbyDrivers() {
    if (userCurrentPosition == null) {
      Future.delayed(const Duration(milliseconds: 500), _startListeningNearbyDrivers);
      return;
    }

    _driversSub?.cancel();
    _driversSub = driversRef.onValue.listen((event) async {
      if (_assignedDriverId != null) return; // لو فيه سائق مقبول بلاش نرسم القريبين

      final data = event.snapshot.value;
      if (data is! Map) return;

      if (_driverCarIcon == null) {
        await _loadDriverIconFixed();
        if (_driverCarIcon == null) return;
      }

      final Map<String, Marker> latest = {};

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
        if (distanceInMeters > 10000) return;

        final double rotation = (driverData['heading'] as num?)?.toDouble() ?? 0.0;

        final marker = Marker(
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

        latest[driverId] = marker;
      });

      setState(() {
        _markersSet.removeWhere((m) => m.markerId.value.startsWith("driver_"));
        _markersSet.addAll(latest.values);
      });
    });
  }

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
    newGoogleMapController?.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _applyMapStyle();
    super.didChangePlatformBrightness();
  }

  // ================= رسم خط المستخدم من الأصل للوجهة (قبل القبول) =================
  Future<void> _drawPolylineFromOriginToDestination(bool darkTheme) async {
    final pickup = Provider.of<AppInfo>(context, listen: false).userPickupLocation;
    final dropoff = Provider.of<AppInfo>(context, listen: false).userDropOffLocation;

    if (pickup == null || dropoff == null) return;

    final directionDetails =
    await AssistantsMehods.obtainOriginToDestinationDirectionDetails(
      LatLng(pickup.locationLatitude!, pickup.locationLongitude!),
      LatLng(dropoff.locationLatitude!, dropoff.locationLongitude!),
    );

    if (directionDetails == null) return;

    if (!mounted) return;
    setState(() {
      tripDirectionDetailsInfo = directionDetails;
    });

    final polylinePoints = PolylinePoints.decodePolyline(directionDetails.e_points!);
    final List<LatLng> coordinates =
    polylinePoints.map((p) => LatLng(p.latitude, p.longitude)).toList();

    setState(() {
      // فقط خط تمهيدي للمستخدم
      _polylineSet.removeWhere((p) => p.polylineId.value == "route" || p.polylineId.value.startsWith("live_"));
      _polylineSet.add(Polyline(
        polylineId: const PolylineId("route"),
        color: darkTheme ? Colors.purpleAccent : Colors.blue,
        width: 5,
        points: coordinates,
      ));

      // ماركر البداية/النهاية
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

    // Fit bounds
    LatLngBounds bounds;
    if (pickup.locationLatitude! > dropoff.locationLatitude! &&
        pickup.locationLongitude! > dropoff.locationLongitude!) {
      bounds = LatLngBounds(
        southwest: LatLng(dropoff.locationLatitude!, dropoff.locationLongitude!),
        northeast: LatLng(pickup.locationLatitude!, pickup.locationLongitude!),
      );
    } else {
      bounds = LatLngBounds(
        southwest: LatLng(pickup.locationLatitude!, pickup.locationLongitude!),
        northeast: LatLng(dropoff.locationLatitude!, dropoff.locationLongitude!),
      );
    }

    newGoogleMapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  // ================= خط مباشر بين نقطتين (للسائق حسب الحالة) =================
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
      // امسح أي خطوط لا تتوافق مع الحالة الحالية
      _polylineSet.removeWhere((pl) =>
      pl.polylineId.value == "route" ||
          pl.polylineId.value.startsWith("live_"));
      _polylineSet.add(Polyline(
        polylineId: PolylineId(id),
        color: toDropoff ? Colors.orange : Colors.blue,
        width: 5,
        points: coords,
      ));

      // حدّث ماركر السائق والهدف فقط
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

    await _animateBetween(from, to);
  }

  Future<void> _animateBetween(LatLng a, LatLng b) async {
    final sw = LatLng(
      a.latitude < b.latitude ? a.latitude : b.latitude,
      a.longitude < b.longitude ? a.longitude : b.longitude,
    );
    final ne = LatLng(
      a.latitude > b.latitude ? a.latitude : b.latitude,
      a.longitude > b.longitude ? a.longitude : b.longitude,
    );
    await newGoogleMapController?.animateCamera(
      CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 70),
    );
  }

  // ========= حفظ الطلب + الاستماع للحالة =========
  Future<void> saveRideRequestInformation(String vehicleType) async {
    if (_isRequesting) return;

    final originLocation = Provider.of<AppInfo>(context, listen: false).userPickupLocation;
    final destinationLocation = Provider.of<AppInfo>(context, listen: false).userDropOffLocation;

    if (originLocation == null || destinationLocation == null) {
      Fluttertoast.showToast(msg: "الرجاء تحديد موقع الانطلاق والوجهة");
      return;
    }

    // اجلب تفاصيل المسار لحساب الأجرة
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

    final referenceRideRequest =
    FirebaseDatabase.instance.ref().child("rideRequests").push();

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

    // خزّن الطلب وفعّل حالة "جاري البحث"
    await referenceRideRequest.set(userInformationMap);
    setState(() {
      _activeRideRequestRef = referenceRideRequest;
      _activeRideRequestId = referenceRideRequest.key;
      _isRequesting = true;
      _assignedDriverId = null;
    });

    // (اختبار) إرسال requestId لسائق معيّن
    const driverId = "tltXTBhHu6ck1ljv3dsznk3ndA23";
    final driverRef = FirebaseDatabase.instance.ref().child("drivers").child(driverId);
    await driverRef.child("newRideRequestId").set(referenceRideRequest.key);

    // ابدأ الاستماع لحالة الطلب
    _rideSub?.cancel();
    _rideSub = referenceRideRequest.onValue.listen((eventSnap) async {
      if (eventSnap.snapshot.value == null) return;
      final rideData = Map<String, dynamic>.from(eventSnap.snapshot.value as Map);
      final status = (rideData["status"] ?? "").toString();

      // احفظ driverId عند القبول + نظّف ماركرات الـ idle
      if (status == "accepted" && rideData["driverId"] != null) {
        final did = rideData["driverId"].toString();
        if (mounted) {
          setState(() {
            _assignedDriverId = did;
            // شيل أي ماركرات لسائقين قريبين
            _markersSet.removeWhere((m) => m.markerId.value.startsWith("driver_"));
          });
        }
      }

      // تحديث ماركر السائق المقبول + رسم المسار حسب الحالة
      if (rideData["driverLocation"] != null) {
        final double driverLat =
            double.tryParse("${rideData["driverLocation"]["latitude"]}") ?? 0.0;
        final double driverLng =
            double.tryParse("${rideData["driverLocation"]["longitude"]}") ?? 0.0;
        final driverPos = LatLng(driverLat, driverLng);

        final pickup = Provider.of<AppInfo>(context, listen: false).userPickupLocation;
        final dropoff = Provider.of<AppInfo>(context, listen: false).userDropOffLocation;

        if (status == "accepted" && pickup != null) {
          await _drawLiveRoute(
            from: driverPos,
            to: LatLng(pickup.locationLatitude!, pickup.locationLongitude!),
            id: "live_to_pickup",
            toDropoff: false,
          );
          updateArrivalTimeToUserPickUpLocation(driverPos);
        } else if ((status == "ontrip" || status == "ongoing") && dropoff != null) {
          await _drawLiveRoute(
            from: driverPos,
            to: LatLng(dropoff.locationLatitude!, dropoff.locationLongitude!),
            id: "live_to_dropoff",
            toDropoff: true,
          );
          updateReachingTimeToUserDropOffLocation(driverPos);
        } else if (status == "arrived") {
          // ثبّت الماركر في مكان الوصول للمستخدم
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
            // امسح الخط لأن السائق وصل
            _polylineSet.removeWhere((pl) => pl.polylineId.value.startsWith("live_"));
          });
          Fluttertoast.showToast(msg: "🚖 السائق وصل لمكانك");
        }
      }

      // التعامل مع كل حالات الحالة (UI)
      switch (status) {
        case "searching":
          if (mounted && !_isSuggestedSheetOpen) setState(() => _isSuggestedSheetOpen = true);
          break;

        case "accepted":
          Fluttertoast.showToast(msg: "تم قبول رحلتك ✅");
          if (mounted) {
            setState(() {
              _isRequesting = false;
              _isSuggestedSheetOpen = false; // اخفي الشيت
            });
          }
          break;

        case "ontrip":
        case "ongoing":
        // تم التعامل معها بالأعلى (تحديث المسار والـ ETA)
          break;

        case "ended":
        case "completed":
          final f = rideData["fare"];
          final double paidFare = (f is num) ? f.toDouble() : double.tryParse("$f") ?? 0.0;
          final response = await showDialog(
            context: context,
            builder: (BuildContext context) => PayFareAmountDialog(fareAmount: paidFare),
          );
          // نظّف بعد الدفع (أو مباشرة حسب احتياجك)
          await _cleanupRideRequest(removeFromDb: true);
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

  Future<void> _cleanupRideRequest({bool removeFromDb = false}) async {
    try {
      await _rideSub?.cancel();
      _rideSub = null;
      if (removeFromDb && _activeRideRequestRef != null) {
        await _activeRideRequestRef!.remove();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _activeRideRequestRef = null;
        _activeRideRequestId = null;
        _isRequesting = false;
        _assignedDriverId = null;
        // نظافة الخريطة
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

  // =================== ETA updates ===================
  String driverRideStatus = "Driver is coming";
  bool requestPositionInfo = true;

  updateArrivalTimeToUserPickUpLocation(LatLng driverCurrentPositionLatLng) async {
    if (requestPositionInfo != true || userCurrentPosition == null) return;
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
    if (requestPositionInfo != true) return;
    requestPositionInfo = false;

    final dropOffLocation = Provider.of<AppInfo>(context, listen: false).userDropOffLocation;
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

          // (اختياري) شارة بسيطة لحالة السائق بالنسبة لك
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
                    _LocationRow(
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
                      child: _LocationRow(
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
                            onPressed: (hasFrom && hasTo)
                                ? () {
                              _openSuggestedRidesSheet();
                            }
                                : null,
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

          // ===== Suggested Rides Draggable Sheet =====
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
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: darkTheme
                                ? [const Color(0xFF0E0F12), const Color(0xFF12141A)]
                                : [Colors.white, const Color(0xFFF7F8FA)],
                          ),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -3)),
                          ],
                        ),
                        child: _SuggestedRidesContent(
                          darkTheme: darkTheme,
                          fromName: fromName,
                          toName: toName,
                          selectedRide: _selectedRide,
                          isRequesting: _isRequesting,
                          onSelect: (v) => setState(() => _selectedRide = v),
                          onClose: () async {
                            _closeSuggestedRidesSheet();
                            // ممكن هنا تعمل إلغاء للطلب لو حابب:
                            // await _cleanupRideRequest(removeFromDb: true);
                          },
                          listScrollController: scrollController,
                          onConfirm: saveRideRequestInformation,
                        ),
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

// ---------------- Widgets ----------------

class _LocationRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _LocationRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddressChip extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final bool darkTheme;

  const _AddressChip({
    required this.color,
    required this.icon,
    required this.label,
    required this.darkTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: darkTheme ? Colors.white.withOpacity(.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: darkTheme ? Colors.white10 : const Color(0xFFEAECEF)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: darkTheme ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RideTile extends StatelessWidget {
  final String id;
  final String title;
  final String eta;
  final String price;
  final String assetPath;
  final bool selected;
  final bool darkTheme;
  final VoidCallback onTap;

  const _RideTile({
    required this.id,
    required this.title,
    required this.eta,
    required this.price,
    required this.assetPath,
    required this.selected,
    required this.darkTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (darkTheme ? Colors.purple.withOpacity(.18) : const Color(0xFFE8F0FF))
        : (darkTheme ? Colors.white.withOpacity(.06) : Colors.white);

    final border = selected
        ? (darkTheme ? Colors.purple.withOpacity(.35) : const Color(0xFF1F6BFF).withOpacity(.35))
        : (darkTheme ? Colors.white10 : const Color(0xFFEAECEF));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: border, width: 1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    assetPath,
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: darkTheme ? Colors.white : Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: darkTheme ? Colors.purple : const Color(0xFF1F6BFF),
                            ),
                          ]
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        eta,
                        style: TextStyle(
                          color: darkTheme ? Colors.white70 : Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                Text(
                  price,
                  style: TextStyle(
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestedRidesContent extends StatelessWidget {
  final bool darkTheme;
  final String? fromName;
  final String? toName;
  final String? selectedRide;
  final bool isRequesting;
  final void Function(String id) onSelect;
  final VoidCallback onClose;
  final ScrollController? listScrollController;
  final Future<void> Function(String vehicleType) onConfirm;

  const _SuggestedRidesContent({
    required this.darkTheme,
    required this.fromName,
    required this.toName,
    required this.selectedRide,
    required this.isRequesting,
    required this.onSelect,
    required this.onClose,
    required this.onConfirm,
    this.listScrollController,
  });

  @override
  Widget build(BuildContext context) {
    final confirmEnabled = !isRequesting && selectedRide != null;

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: darkTheme ? Colors.white24 : Colors.black12,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 10),

        // header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                isRequesting ? "جارٍ البحث عن سائق..." : "Suggested rides",
                style: TextStyle(
                  color: darkTheme ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              if (isRequesting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                splashRadius: 22,
                icon: Icon(
                  Icons.close_rounded,
                  color: darkTheme ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),

        // chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _AddressChip(
                color: darkTheme ? Colors.purple : Colors.blue,
                icon: Icons.radio_button_checked,
                label: fromName ?? "لم يتم تحديد العنوان",
                darkTheme: darkTheme,
              ),
              const SizedBox(height: 10),
              _AddressChip(
                color: Colors.grey,
                icon: Icons.location_on_rounded,
                label: toName ?? "إلى أين؟",
                darkTheme: darkTheme,
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),
        Divider(
          height: 1,
          color: darkTheme ? Colors.white10 : const Color(0xFFEAECEF),
        ),

        // list
        Expanded(
          child: SingleChildScrollView(
            controller: listScrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              children: [
                _RideTile(
                  id: "car",
                  title: "سيارة",
                  eta: "6–9 min",
                  price: tripDirectionDetailsInfo != null
                      ? "${AssistantsMehods.calculateFareAmountFormOriginToDestination(tripDirectionDetailsInfo!)}  EGP"
                      : "—",
                  assetPath: "assets/carRide.png",
                  selected: selectedRide == "car",
                  darkTheme: darkTheme,
                  onTap: isRequesting ? () {} : () => onSelect("car"),
                ),
                _RideTile(
                  id: "bike",
                  title: "دراجة",
                  eta: "3–5 min",
                  price: tripDirectionDetailsInfo != null
                      ? "${AssistantsMehods.calculateFareBike(tripDirectionDetailsInfo!)} EGP"
                      : "—",
                  assetPath: "assets/bikeRide.png",
                  selected: selectedRide == "bike",
                  darkTheme: darkTheme,
                  onTap: isRequesting ? () {} : () => onSelect("bike"),
                ),
              ],
            ),
          ),
        ),

        // confirm
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: confirmEnabled
                  ? () async {
                final type = selectedRide!;
                await onConfirm(type);
                Fluttertoast.showToast(
                  msg: type == "bike" ? "تم تأكيد الدراجة" : "تم تأكيد السيارة",
                );
              }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: darkTheme ? Colors.purple : Colors.blue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                isRequesting
                    ? "جارٍ البحث عن سائق..."
                    : (selectedRide == null
                    ? "اختَر نوع المشوار"
                    : "تأكيد ${selectedRide == "car" ? "السيارة" : "الدراجة"}"),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
