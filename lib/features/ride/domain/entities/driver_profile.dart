// lib/features/ride/domain/entities/driver_profile.dart
class DriverProfile {
  final String id;
  final String name;
  final String phone;

  // vehicle
  final String vehicleType;
  final String carModel;
  final String carColor;

  /// رقم العربية (Plate / Number)
  final String carNumber;

  /// صورة السائق (avatar/photo/image)
  final String photoUrl;

  /// تقييم (اختياري)
  final double rating;

  DriverProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.vehicleType,
    required this.carModel,
    required this.carColor,
    required this.carNumber,
    required this.photoUrl,
    required this.rating,
  });

  DriverProfile copyWith({
    String? id,
    String? name,
    String? phone,
    String? vehicleType,
    String? carModel,
    String? carColor,
    String? carNumber,
    String? photoUrl,
    double? rating,
  }) {
    return DriverProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      vehicleType: vehicleType ?? this.vehicleType,
      carModel: carModel ?? this.carModel,
      carColor: carColor ?? this.carColor,
      carNumber: carNumber ?? this.carNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      rating: rating ?? this.rating,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'vehicleType': vehicleType,
    'carModel': carModel,
    'carColor': carColor,
    'carNumber': carNumber,
    'photoUrl': photoUrl,
    'rating': rating,
  };

  /// قارئ مرن لأي شكل محتمل للداتا
  factory DriverProfile.fromMapFlexible(String id, Map<String, dynamic> map) {
    // nested
    final profile = _asMap(map['profile']) ?? map;

    final vehicle = _asMap(profile['vehicle']) ??
        _asMap(profile['car']) ??
        _asMap(profile['car_details']) ??
        _asMap(map['vehicle']) ??              // NEW: من الـ Top-Level لو موجود
        _asMap(map['car']) ??                  // NEW
        _asMap(map['car_details']) ??          // NEW
        const <String, dynamic>{};

    final loc = _asMap(map['location']) ?? const <String, dynamic>{};

    String s(dynamic v, [String def = '']) => v == null ? def : v.toString();
    double d(dynamic v, [double def = 0.0]) {
      if (v == null) return def;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? def;
      return def;
    }

    // helpers to read with 3-level fallback: profile -> vehicle -> top-level
    String pick3(String k1, String k2, String k3, {String def = ''}) {
      final v1 = profile[k1];
      if (v1 != null && v1.toString().trim().isNotEmpty) return v1.toString().trim();
      final v2 = vehicle[k2];
      if (v2 != null && v2.toString().trim().isNotEmpty) return v2.toString().trim();
      final v3 = map[k3];
      if (v3 != null && v3.toString().trim().isNotEmpty) return v3.toString().trim();
      return def;
    }

    return DriverProfile(
      id: id,
      // name/phone: profile أولاً ثم location كـ fallback ثم Top-Level
      name : s(profile['name'] ?? profile['fullName'] ?? profile['driverName'] ?? profile['driver_name'] ?? loc['name'] ?? map['name']),
      phone: s(profile['phone'] ?? profile['phoneNumber'] ?? profile['mobile'] ?? loc['phone'] ?? map['phone']),

      // vehicleType: profile -> vehicle.type|carType -> Top-Level
      vehicleType: pick3('vehicleType', 'type', 'vehicleType', def: s(profile['carType'])),

      // car fields: profile|vehicle|Top-Level
      carModel : pick3('carModel',  'model',      'carModel'),
      carColor : pick3('carColor',  'color',      'carColor'),
      carNumber: s(
        profile['carNumber'] ??
            profile['plate'] ??
            profile['carPlate'] ??
            vehicle['number'] ??
            vehicle['plate'] ??
            vehicle['car_number'] ??
            map['carNumber'] ?? map['plate'] ?? map['carPlate'] ?? map['car_number'] ?? '',
      ),

      // photoUrl: profile -> Top-Level
      photoUrl: s(profile['photoUrl'] ?? profile['avatar'] ?? profile['avatarUrl'] ?? profile['image'] ?? profile['imageUrl'] ??
          map['photoUrl']     ?? map['avatar']     ?? map['avatarUrl']     ?? map['image']     ?? map['imageUrl']),
      rating: d(profile['rating'] ?? profile['rate'] ?? profile['stars'] ?? map['rating']),
    );
  }

  /// لو الخام مش Map أو Map<dynamic,dynamic>
  factory DriverProfile.fromDynamic(String id, dynamic raw) {
    final map = _asMap(raw) ?? <String, dynamic>{};
    return DriverProfile.fromMapFlexible(id, map);
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) {
      try {
        return Map<String, dynamic>.from(v as Map);
      } catch (_) {
        final m = <String, dynamic>{};
        (v as Map).forEach((k, val) => m[k.toString()] = val);
        return m;
      }
    }
    return null;
  }

  /// طباعة منظمة للكونسول (تساعدك في الديبج)
  String toPrettyString() {
    return '''
=== DRIVER PROFILE ===
id: $id
name: $name
phone: $phone
vehicleType: $vehicleType
carModel: $carModel
carColor: $carColor
carNumber: $carNumber
photoUrl: $photoUrl
rating: $rating
=====================
''';
  }
}
