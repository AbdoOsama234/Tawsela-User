import 'package:flutter/material.dart';

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
                  // شريط السحب
                  Container(
                    width: 44, height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // العنوان
                  Row(
                    children: [
                      const Icon(Icons.emoji_transportation_rounded),
                      const SizedBox(width: 8),
                      Text(
                        'كيف كانت رحلتك؟',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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

                  // ملاحظات (اختياري)
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

                  // زر الإرسال
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
      // بدون بقشيش — نمرر 0.0
      await widget.onSubmit(_rating, 0.0, note);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
