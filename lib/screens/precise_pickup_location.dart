import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geocoder2/geocoder2.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../Assistants/assistants_methods.dart';
import '../infoHandler/app_info.dart';
import '../models/directions.dart';
import '../main_screen.dart' show pickLocation; // بنستخدم المتغير الجلوبال الموجود في MainScreen

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

  // لعمل ديبونس لاستدعاء الـ Geocoding بعد توقف التحريك
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
    final style = await rootBundle.loadString(stylePath);
    await newGoogleMapController!.setMapStyle(style);
  }
  // ============================

  Future<void> locationUserPosition() async {
    final cPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    userCurrentPosition = cPosition;

    final latLngPosition = LatLng(userCurrentPosition!.latitude, userCurrentPosition!.longitude);
    final cameraPosition = CameraPosition(target: latLngPosition, zoom: 15);

    if (newGoogleMapController != null) {
      await newGoogleMapController!.animateCamera(CameraUpdate.newCameraPosition(cameraPosition));
    }

    // حدّث عنوان الـ From في AppInfo (هيتعرَض في الواجهة)
    await AssistantsMehods.searchAddressForGeographCoOrdinates(cPosition, context);

    // خليه برضه هو pickLocation الافتراضي
    pickLocation = latLngPosition;
  }

  Future<void> _reverseGeocodePickLocation() async {
    try {
      if (pickLocation == null) return;

      final data = await Geocoder2.getDataFromCoordinates(
        latitude: pickLocation!.latitude,
        longitude: pickLocation!.longitude,
        googleMapApiKey: "AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0",
        language: 'ar',
      );

      final userPickUpAddress = Directions()
        ..locationLatitude = pickLocation!.latitude
        ..locationLongitude = pickLocation!.longitude
        ..locationName = data.address;

      if (!mounted) return;
      context.read<AppInfo>().updatePickUpLocationAddress(userPickUpAddress);
      setState(() {}); // لو عايز تعكس الاسم فوراً في الـ UI
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
            padding: const EdgeInsets.only(top: 30, right: 0, bottom: 80, left: 10), // رفع زر my-location
            mapType: MapType.normal,
            initialCameraPosition: _kGooglePlex,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            zoomGesturesEnabled: true,
            onMapCreated: (GoogleMapController controller) async {
              _controllerGoogleMap.complete(controller);
              newGoogleMapController = controller;
              setState(() => bottomPaddingOfMap = 200);
              await _applyMapStyle();
              await locationUserPosition();
            },
            onCameraMove: (CameraPosition position) {
              // خزّن نقطة المؤشر
              pickLocation = position.target;

              // ديبونس: كل ما يتحرك نلغي القديم ونستنى 450ms بعد آخر حركة
              _idleDebounce?.cancel();
              _idleDebounce = Timer(const Duration(milliseconds: 450), _reverseGeocodePickLocation);
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
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 3),
                ],
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
                          if (pickLocation == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("حرّك الخريطة وحدّد مكانك أولاً")),
                            );
                            return;
                          }

                          // ضَمّن آخر عنوان تم حفظه
                          final currentName =
                              context.read<AppInfo>().userPickupLocation?.locationName;

                          final info = Directions()
                            ..locationLatitude = pickLocation!.latitude
                            ..locationLongitude = pickLocation!.longitude
                            ..locationName = currentName ?? "Selected location";

                          context.read<AppInfo>().updatePickUpLocationAddress(info);

                          // ارجع للشاشة السابقة بقيمة مفهومة
                          Navigator.pop(context, "pickupUpdated");
                        },
                        icon: const Icon(Icons.edit_location_alt, size: 18),
                        label: const Text("Set Current Location"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: darkTheme ? Colors.purple : Colors.blue,
                          foregroundColor: darkTheme ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
            Text(
              label,
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
            ),
          ],
        ),
      ),
    ],
  );
}
