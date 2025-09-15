import 'package:flutter/material.dart';

class PayFareAmountDialog extends StatelessWidget {
  final double fareAmount;

  const PayFareAmountDialog({
    super.key,
    required this.fareAmount,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      title: const Text(
        "تفاصيل الرحلة",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Text(
        "المبلغ المطلوب دفعه: $fareAmount EGP",
        style: const TextStyle(fontSize: 16),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, "Cash Paid"),
          child: const Text(
            "تم الدفع كاش",
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, "Cancel"),
          child: const Text(
            "إلغاء",
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }
}
