// lib/features/ride/presentation/widgets/ride_tile.dart
import 'package:flutter/material.dart';

class RideTile extends StatelessWidget {
  final String id;
  final String title;
  final String eta;
  final String price;
  final String assetPath;
  final bool selected;
  final bool darkTheme;
  final VoidCallback onTap;

  const RideTile({
    super.key,
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
                  child: Image.asset(assetPath, width: 64, height: 64, fit: BoxFit.contain),
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
