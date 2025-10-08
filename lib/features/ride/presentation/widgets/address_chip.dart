// lib/features/ride/presentation/widgets/address_chip.dart
import 'package:flutter/material.dart';

class AddressChip extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final bool darkTheme;

  const AddressChip({
    super.key,
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
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
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
