import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:users/Assistants/request_assistants.dart';
import 'package:users/infoHandler/app_info.dart';
import 'package:users/widgets/progress_dialog.dart';

import '../global/global.dart';
import '../models/directions.dart';
import '../models/perdicted_places.dart';

class PlacePredictionTile extends StatefulWidget {
  final PerdictedPlaces perdictedPlaces;

  const PlacePredictionTile({super.key, required this.perdictedPlaces});

  @override
  State<PlacePredictionTile> createState() => _PlacePredictionTileState();
}

class _PlacePredictionTileState extends State<PlacePredictionTile> {
  Future<void> getPlaceDirectionDetails(String? placeId, BuildContext context) async {
    if (placeId == null || placeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Place id is missing')),
      );
      return;
    }

    // افتح الدايالوج
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
       ProgressDialog(message: "Setting up Drop-off, please wait..."),
    );

    try {
      final url =
          "https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0";

      final responseApi = await RequestAssistants.receiveRequest(url);

      // لو حصل فشل من الهلبِر
      if (responseApi == "Error Occured. Failed. No Response") {
        if (mounted) Navigator.of(context).pop(); // اغلق الدايالوج
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to fetch place details')),
        );
        return;
      }

      // تأكد من الحالة
      if (responseApi is Map &&
          responseApi["status"] == "OK" &&
          responseApi["result"] != null) {
        final result = responseApi["result"];
        final geometry = result["geometry"];
        final loc = geometry?["location"];

        // تأكد من وجود خطوط العرض/الطول
        final double? lat = (loc?["lat"] as num?)?.toDouble();
        final double? lng = (loc?["lng"] as num?)?.toDouble();

        if (lat == null || lng == null) {
          if (mounted) Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Missing coordinates in response')),
          );
          return;
        }

        final directions = Directions()
          ..locationName = (result["name"] as String?) ?? "Unknown"
          ..locationId = placeId
          ..locationLatitude = lat
          ..locationLongitude = lng;

        // ملاحظة: لو عندك updateDropOffLocationAddress استخدمها بدل PickUp
        Provider.of<AppInfo>(context, listen: false)
            .updateDropOffLocationAddress(directions);

        // حدّث المتغير الجلوبال بحذر
        userDropOffAddress = directions.locationName ?? "";

        if (!mounted) return;
        Navigator.of(context).pop(); // اقفل الدايالوج
        Navigator.of(context).pop("obtainedDropoff"); // ارجع للشاشة اللي قبلها
      } else {
        if (mounted) Navigator.of(context).pop(); // اغلق الدايالوج
        final status = (responseApi is Map) ? responseApi["status"] : "UNKNOWN";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Places API failed: $status')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // تأكيد اغلاق الدايالوج
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    return InkWell(
      onTap: () => getPlaceDirectionDetails(widget.perdictedPlaces.place_id, context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        child: Row(
          children: [
            Icon(
              Icons.add_location,
              color: darkTheme ? Colors.purple : Colors.blue,
            ),
            const SizedBox(width: 10.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // main_text ممكن تبقى null من الـ API
                  Text(
                    widget.perdictedPlaces.main_text ?? "Unknown place",
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: darkTheme ? Colors.purple : Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.perdictedPlaces.secondary_text ?? "",
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: darkTheme ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
