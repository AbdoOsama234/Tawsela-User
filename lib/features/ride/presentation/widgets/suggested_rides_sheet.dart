// lib/features/ride/presentation/widgets/suggested_rides_sheet.dart
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../../../core/constants/global.dart';
import '../../../../core/services/assistant_api/assistants_methods.dart';

class SuggestedRidesSheet extends StatelessWidget {
  const SuggestedRidesSheet({
    super.key,
    required this.darkTheme,
    required this.fromName,
    required this.toName,
    required this.selectedRide,
    required this.isRequesting,
    required this.onSelect,
    required this.onClose,
    required this.onConfirm,
    required this.onCancelSearch, // جديد
    this.listScrollController,
  });

  final bool darkTheme;
  final String? fromName;
  final String? toName;
  final String? selectedRide; // "car" | "bike"
  final bool isRequesting;

  final void Function(String id) onSelect;
  final VoidCallback onClose;
  final Future<void> Function(String vehicleType) onConfirm;
  final VoidCallback onCancelSearch; // جديد
  final ScrollController? listScrollController;

  @override
  Widget build(BuildContext context) {
    final confirmEnabled = !isRequesting && selectedRide != null;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: darkTheme
              ? const [Color(0xFF0E0F12), Color(0xFF12141A)]
              : const [Colors.white, Color(0xFFF7F8FA)],
        ),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 44, height: 5,
            decoration: BoxDecoration(
              color: darkTheme ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  isRequesting ? "جارٍ البحث عن سائق..." : "Suggested rides",
                  style: TextStyle(
                    color: darkTheme ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700, fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                if (isRequesting)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const Spacer(),
                IconButton(
                  splashRadius: 22,
                  icon: Icon(Icons.close_rounded, color: darkTheme ? Colors.white70 : Colors.black54),
                  onPressed: () {
                    if (isRequesting) {
                      // إلغاء البحث عن سائق
                      onCancelSearch();
                    } else {
                      // إغلاق الشيت فقط
                      onClose();
                    }
                  },
                ),
              ],
            ),
          ),

          // From / To chips
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
          Divider(height: 1, color: darkTheme ? Colors.white10 : const Color(0xFFEAECEF)),

          // List
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
                        ? "${AssistantsMehods.calculateFareAmountFormOriginToDestination(tripDirectionDetailsInfo!)}  SAR"
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
                        ? "${AssistantsMehods.calculateFareBike(tripDirectionDetailsInfo!)} SAR"
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

          // Confirm
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      ),
    );
  }
}

// ====== عناصر UI بسيطة داخلياً ======

class _AddressChip extends StatelessWidget {
  const _AddressChip({
    required this.color,
    required this.icon,
    required this.label,
    required this.darkTheme,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool darkTheme;

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
            width: 28, height: 28,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
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

  final String id;
  final String title;
  final String eta;
  final String price;
  final String assetPath;
  final bool selected;
  final bool darkTheme;
  final VoidCallback onTap;

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
                  child: Image.asset(assetPath, width: 64, height: 64, fit: BoxFit.contain),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: darkTheme ? Colors.white : Colors.black87,
                            fontSize: 16, fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle_rounded,
                              size: 18, color: darkTheme ? Colors.purple : const Color(0xFF1F6BFF)),
                        ]
                      ]),
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
                  style: TextStyle(color: Colors.green.shade600, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
