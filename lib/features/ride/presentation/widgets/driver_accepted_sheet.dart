import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:users/features/ride/domain/entities/driver_profile.dart';

class DriverAcceptedSheet extends StatelessWidget {
  final DriverProfile driver;
  final VoidCallback? onClose;
  final VoidCallback? onCancelRide; // ⬅️ جديد: callback للإلغاء

  const DriverAcceptedSheet({
    super.key,
    required this.driver,
    this.onClose,
    this.onCancelRide, // ⬅️ جديد
  });

  Future<void> _callDriver(BuildContext context, String phone) async {
    final p = phone.replaceAll(RegExp(r'\s+'), '').trim();
    if (p.isEmpty) return;

    final uri = Uri(scheme: 'tel', path: p);

    if (await canLaunchUrl(uri)) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذّر فتح تطبيق الاتصال'),
            action: SnackBarAction(
              label: 'نسخ الرقم',
              onPressed: () => Clipboard.setData(ClipboardData(text: p)),
            ),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('لا يوجد تطبيق اتصال متاح على هذا الجهاز'),
          action: SnackBarAction(
            label: 'نسخ',
            onPressed: () => Clipboard.setData(ClipboardData(text: p)),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = driver.name.trim();
    final avatarLetter = (name.isNotEmpty ? name[0] : '?').toUpperCase();

    final vehicleLine = [
      if (driver.vehicleType.isNotEmpty) driver.vehicleType,
      if (driver.carModel.isNotEmpty) driver.carModel,
    ].join(' • ');

    final phone = driver.phone.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -3))
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    child: Text(avatarLetter),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name.isNotEmpty ? name : 'السائق',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _infoRow(Icons.phone_rounded, phone.isNotEmpty ? phone : '—'),
              if (vehicleLine.isNotEmpty) _infoRow(Icons.directions_car_rounded, vehicleLine),
              if (driver.carColor.isNotEmpty)
                _infoRow(Icons.color_lens_rounded, 'اللون: ${driver.carColor}'),
              if (driver.carNumber.isNotEmpty)
                _infoRow(Icons.confirmation_number_rounded, 'الرقم: ${driver.carNumber}'),
              const SizedBox(height: 16),

              /// زر الاتصال
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: phone.isEmpty ? null : () => _callDriver(context, phone),
                      icon: const Icon(Icons.call_rounded),
                      label: Text(
                        phone.isEmpty ? 'اتصال' : 'اتصال بـ $phone',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              /// زر إلغاء الرحلة
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(); // ⬅️ يقفل الـ BottomSheet
                        if (onCancelRide != null) {
                          onCancelRide!(); // ⬅️ ينفذ منطق الإلغاء
                        }
                      },
                      icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                      label: const Text(
                        'إلغاء الرحلة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red, width: 1.5),
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
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
