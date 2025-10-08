import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/assistant_api/request_assistants.dart';
import '../widgets/place_prediction_tile.dart';
import '../../domain/entities/perdicted_places.dart';

class SearchPlaced extends StatefulWidget {
  const SearchPlaced({super.key});

  @override
  State<SearchPlaced> createState() => _SearchPlacedState();
}

class _SearchPlacedState extends State<SearchPlaced> {
  final TextEditingController _controller = TextEditingController();

  // نحتفظ بتوكن واحد للجلسة (ينصح به Google)
  final String _placesSessionToken = const Uuid().v4();

  // Debounce عشان ما نبعتش طلب لكل حرف
  Timer? _debounce;
  static const _debounceDuration = Duration(milliseconds: 400);

  bool _loading = false;
  List<PerdictedPlaces> _predictions = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String input) {
    // امسح النتائج لو الكتابة قليلة
    if (input.trim().length < 2) {
      setState(() {
        _predictions = [];
        _loading = false;
      });
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () => _fetchAutocomplete(input.trim()));
  }

  Future<void> _fetchAutocomplete(String query) async {
    setState(() => _loading = true);

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'key': 'AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0', // ← حط مفتاح Places
        'language': 'ar',             // يرجّع عربي لو متاح
        'components': 'country:EG',   // قيّد لمصر (غيّرها لو عايز)
        'sessiontoken': _placesSessionToken,
        // 'types': 'geocode',        // فعّلها لو عايز عناوين فقط
      },
    );

    try {
      final res = await RequestAssistants.receiveRequest(uri.toString());
      if (!mounted) return;

      // receiveRequest لازم ترجع Map<String, dynamic>? أو null
      if (res == null) {
        setState(() {
          _predictions = [];
          _loading = false;
        });
        return;
      }

      final status = (res['status'] as String?) ?? '';
      if (status == 'OK' && res['predictions'] is List) {
        final list = (res['predictions'] as List)
            .map((e) => PerdictedPlaces.fromjson(e))
            .toList()
            .cast<PerdictedPlaces>();
        setState(() {
          _predictions = list;
          _loading = false;
        });
      } else {
        // حالات ZERO_RESULTS / REQUEST_DENIED / OVER_QUERY_LIMIT...
        setState(() {
          _predictions = [];
          _loading = false;
        });
        // debugPrint('Places status: $status | res: $res');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _predictions = [];
        _loading = false;
      });
      // debugPrint('Autocomplete error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = MediaQuery.of(context).platformBrightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: darkTheme ? Colors.black : Colors.white,
        appBar: AppBar(
          backgroundColor: darkTheme ? Colors.purple : Colors.blue,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: darkTheme ? Colors.black : Colors.white),
          ),
          title: Text(
            "Search & Set dropoff location",
            style: TextStyle(color: darkTheme ? Colors.black : Colors.white),
          ),
          elevation: 0.0,
        ),
        body: Column(
          children: [
            // شريط البحث
            Container(
              decoration: BoxDecoration(
                color: darkTheme ? Colors.purple : Colors.blue,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    spreadRadius: 0.5,
                    offset: Offset(0.7, 0.7),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Row(
                  children: [
                    Icon(Icons.adjust_sharp, color: darkTheme ? Colors.black : Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _controller,
                        onChanged: _onQueryChanged,
                        textInputAction: TextInputAction.search,
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText: "Search location here...",
                          hintStyle: TextStyle(
                            color: darkTheme ? Colors.black54 : Colors.black54,
                          ),
                          fillColor: darkTheme ? Colors.white : Colors.white,
                          filled: true,
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          suffixIcon: _loading
                              ? const Padding(
                            padding: EdgeInsets.all(10.0),
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                              : (_controller.text.isNotEmpty
                              ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                              _onQueryChanged('');
                            },
                          )
                              : null),
                        ),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // النتائج
            Expanded(
              child: _predictions.isNotEmpty
                  ? ListView.separated(
                itemCount: _predictions.length,
                physics: const ClampingScrollPhysics(),
                itemBuilder: (context, index) {
                  return PlacePredictionTile(
                    perdictedPlaces: _predictions[index],
                  );
                },
                separatorBuilder: (_, __) => Divider(
                  height: 0,
                  color: darkTheme ? Colors.purple : Colors.blue,
                  thickness: 0,
                ),
              )
                  : Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _controller.text.trim().isEmpty
                        ? 'اكتب اسم المكان للبحث'
                        : (_loading ? '' : 'لا توجد نتائج'),
                    style: TextStyle(
                      color: darkTheme ? Colors.white70 : Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
