import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geocoder2/geocoder2.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/assistant_api/assistants_methods.dart';
import '../../../../shared/state/app_info.dart';
import '../../domain/entities/directions.dart';

class PrecisePickupLocation extends StatefulWidget {
  const PrecisePickupLocation({super.key});

  @override
  State<PrecisePickupLocation> createState() => _PrecisePickupLocationState();
}

class _PrecisePickupLocationState extends State<PrecisePickupLocation> {
  final Completer<GoogleMapController> _controllerGoogleMap = Completer<GoogleMapController>();
  GoogleMapController? newGoogleMapController;

  Position? userCurrentPosition;
  double bottomPaddingOfMap = 0;

  // متغيّر محلي بدل الجلوبال
  LatLng? _pinLatLng;

  // ديبونس لوقف السبام على Geocoder2
  Timer? _idleDebounce;

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(30.0444, 31.2357),
    zoom: 14.4746,
  );

  // ========= Map Style =========
  Future<void> _applyMapStyle() async {
    if (newGoogleMapController == null) return;
    final isDark = SchedulerBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final stylePath = isDark ? 'assets/map_style/dark_map.json' : 'assets/map_style/light_map.json';
    try {
      final style = await rootBundle.loadString(stylePath);
      await newGoogleMapController!.setMapStyle(style);
    } catch (e) {
      debugPrint('Map style load error: $e');
    }
  }
  // ============================

  Future<void> _goToUserPosition() async {
    // تأكد من الصلاحيات
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }

    final cPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    userCurrentPosition = cPosition;

    final latLng = LatLng(cPosition.latitude, cPosition.longitude);
    final cam = CameraPosition(target: latLng, zoom: 15);
    await newGoogleMapController?.animateCamera(CameraUpdate.newCameraPosition(cam));

    // حدّث عنوان الـ From (هيظهر في الواجهة الرئيسية)
    await AssistantsMehods.searchAddressForGeographCoOrdinates(cPosition, context);

    // خلي المؤشر الافتراضي نفس مكان المستخدم
    _pinLatLng = latLng;
    // اعمل ريفيرس جيكود أول مرة
    _reverseGeocodePin();
  }

  Future<void> _reverseGeocodePin() async {
    try {
      if (_pinLatLng == null) return;
      final data = await Geocoder2.getDataFromCoordinates(
        latitude: _pinLatLng!.latitude,
        longitude: _pinLatLng!.longitude,
        googleMapApiKey: "YOUR_GOOGLE_KEY_HERE",
        language: 'ar',
      );

      final pick = Directions()
        ..locationLatitude = _pinLatLng!.latitude
        ..locationLongitude = _pinLatLng!.longitude
        ..locationName = data.address;

      if (!mounted) return;
      context.read<AppInfo>().updatePickUpLocationAddress(pick);
      setState(() {}); // لو حابب تحدّث الـ UI بالعنوان فورًا
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    newGoogleMapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = MediaQuery.of(context).platformBrightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            padding: const EdgeInsets.only(top: 30, right: 0, bottom: 80, left: 10),
            mapType: MapType.normal,
            initialCameraPosition: _kGooglePlex,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            zoomGesturesEnabled: true,
            onMapCreated: (GoogleMapController controller) async {
              if (!_controllerGoogleMap.isCompleted) _controllerGoogleMap.complete(controller);
              newGoogleMapController = controller;
              setState(() => bottomPaddingOfMap = 200);
              await _applyMapStyle();
              await _goToUserPosition();
            },
            onCameraMove: (CameraPosition position) {
              _pinLatLng = position.target;

              _idleDebounce?.cancel();
              _idleDebounce = Timer(const Duration(milliseconds: 450), _reverseGeocodePin);
            },
          ),

          // دبوس ثابت في منتصف الخريطة
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 35.0),
              child: Image.asset("assets/location/initial.png", height: 45, width: 45),
            ),
          ),

          // البوكس السفلي
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 3)],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLocationRow(
                      icon: Icons.location_on,
                      label: "From",
                      value: context.watch<AppInfo>().userPickupLocation?.locationName
                          ?? "Not Getting Address",
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (_pinLatLng == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("حرّك الخريطة وحدّد مكانك أولاً")),
                            );
                            return;
                          }

                          final currentName =
                              context.read<AppInfo>().userPickupLocation?.locationName;

                          final info = Directions()
                            ..locationLatitude = _pinLatLng!.latitude
                            ..locationLongitude = _pinLatLng!.longitude
                            ..locationName = currentName ?? "Selected location";

                          context.read<AppInfo>().updatePickUpLocationAddress(info);
                          Navigator.pop(context, "pickupUpdated");
                        },
                        icon: const Icon(Icons.edit_location_alt, size: 18),
                        label: const Text("Set Current Location"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: darkTheme ? Colors.purple : Colors.blue,
                          foregroundColor: darkTheme ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ويدجت صغيرة لعرض Label + Address بسطر واحد مع ellipsis
Widget _buildLocationRow({
  required IconData icon,
  required String label,
  required String value,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Icon(icon, color: Colors.blue),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false),
          ],
        ),
      ),
    ],
  );
}
