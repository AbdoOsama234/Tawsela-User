// lib/features/ride/data/drivers_repository.dart

import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:users/features/ride/domain/entities/driver_profile.dart';

class DriversRepository {
  DriversRepository({DatabaseReference? db})
      : _db = db ?? FirebaseDatabase.instance.ref();

  final DatabaseReference _db;

  // ===================== Public API =====================

  /// يحاول يرجّع بروفايل السائق بالترتيب:
  /// (1) rideRequests/<rideId>/driverSnapshot (مع sanitize للـ vehicleType)
  /// (2) تجميع من drivers/<driverId> (+ car_details) مع vehicleType من الطلب كـ fallback
  Future<DriverProfile?> getDriverProfileFromRequestOrDrivers(
      String rideId,
      String driverId,
      ) async {
    // (1) Snapshot داخل الطلب
    final snapInReq =
    await _db.child('rideRequests/$rideId/driverSnapshot').get();

    if (snapInReq.value is Map) {
      final raw = Map<String, dynamic>.from(snapInReq.value as Map);

      // نظّف الـ vehicleType لو داخلة Map أو أي نوع تاني
      raw['vehicleType'] = _sanitizeVehicleType(raw['vehicleType']);

      final p = DriverProfile.fromMapFlexible(driverId, raw);
      if (_hasBasicInfo(p)) {
        if (kDebugMode) {
          debugPrint(
              "[DriversRepo] USING request snapshot for $driverId on $rideId => name=${p.name}, phone=${p.phone}, vType=${p.vehicleType}");
        }
        return p;
      }
    }

    // (2) من /drivers + fallback vehicleType من الطلب
    final vtSnap = await _db.child('rideRequests/$rideId/vehicleType').get();
    final vtClean = _sanitizeVehicleType(vtSnap.value);

    final p = await _assembleFromDrivers(
      driverId,
      fallbackVehicleType: vtClean,
    );

    if (kDebugMode) {
      if (p == null) {
        debugPrint(
            "!!! [DriversRepo] _assembleFromDrivers returned NULL for driverId=$driverId");
      } else {
        debugPrint(
            "[DriversRepo] BUILT from drivers/$driverId => name=${p.name}, phone=${p.phone}, vType=${p.vehicleType}, carModel=${p.carModel}, carColor=${p.carColor}, carNumber=${p.carNumber}");
      }
    }

    return p;
  }

  /// يكتب driverSnapshot. استخدم overwrite=true لو عايز تفرض الكتابة.
  Future<void> writeDriverSnapshot(
      String rideId,
      DriverProfile profile, {
        bool overwrite = false,
      }) async {
    final ref = _db.child('rideRequests/$rideId/driverSnapshot');
    if (!overwrite) {
      final exists = (await ref.get()).exists;
      if (exists) return;
    }
    // اضمن إن vehicleType نص نظيف
    final clean = profile.copyWith(
      vehicleType: _sanitizeVehicleType(profile.vehicleType),
    );
    await ref.set(clean.toJson());
  }

  /// يكتب driverSnapshot لو مش موجود فقط.
  Future<void> writeDriverSnapshotIfMissing(
      String rideId,
      DriverProfile profile,
      ) async {
    await writeDriverSnapshot(rideId, profile, overwrite: false);
  }

  /// ستريم كل السائقين (للخريطة)
  Stream<Map<String, dynamic>?> watchDrivers() {
    return _db.child('drivers').onValue.map((e) {
      final v = e.snapshot.value;
      return (v is Map) ? Map<String, dynamic>.from(v as Map) : null;
    });
  }

  /// حفظ ملخص الرحلة في سجل المستخدم
  /// path: users/<userId>/history/<rideId>
  Future<void> writeRideHistory({
    required String userId,
    required String rideId,
    required Map<String, dynamic> payload,
  }) async {
    final ref = _db.child('users/$userId/history/$rideId');
    await ref.set(payload);
    if (kDebugMode) {
      debugPrint('[DriversRepo] writeRideHistory -> users/$userId/history/$rideId');
    }
  }

  /// حفظ تقييم/بقشيش للسائق
  /// path: drivers/<driverId>/ratings/<rideId>
  Future<void> submitDriverRating({
    required String driverId,
    required String rideId,
    required double rating,
    required double tipAmount,
    String? note,
  }) async {
    final ref = _db.child('drivers/$driverId/ratings/$rideId');
    await ref.set({
      'rating': rating,
      'tip': tipAmount,
      'note': note ?? '',
      'createdAt': DateTime.now().toIso8601String(),
    });
    if (kDebugMode) {
      debugPrint('[DriversRepo] submitDriverRating -> drivers/$driverId/ratings/$rideId rating=$rating tip=$tipAmount');
    }
    // (اختياري): ممكن تضيف هنا تحديث متوسط التقييم عبر Cloud Function أو قراءة/حساب محلي.
  }

  // ===================== Internals =====================

  Future<DriverProfile?> _assembleFromDrivers(
      String driverId, {
        String? fallbackVehicleType,
      }) async {
    // 0) اقرأ السائق
    final snap = await _db.child('drivers/$driverId').get();
    if (!snap.exists || snap.value == null) {
      if (kDebugMode) {
        debugPrint("[DriversRepo] drivers/$driverId => NOT FOUND");
      }
      return null;
    }

    Map<String, dynamic> rootRaw;
    try {
      rootRaw = Map<String, dynamic>.from(snap.value as Map);
    } catch (_) {
      if (kDebugMode) {
        debugPrint("[DriversRepo] drivers/$driverId => value is not a Map");
      }
      return null;
    }

    // 1) فكّ التغليف لو فيه { "<id>": { ... } }
    Map<String, dynamic> root = rootRaw;
    final sub = root[driverId];
    if (sub is Map) {
      // فكّ واشتغل على بيانات السواق المطلوبة فقط
      root = Map<String, dynamic>.from(sub);
    } else if (root.length == 1 &&
        root.keys.first == driverId &&
        root.values.first is Map) {
      // الحالة القديمة اللي كنا بنغطيها
      root = Map<String, dynamic>.from(root.values.first as Map);
    }

    if (kDebugMode) {
      debugPrint(
          "[DriversRepo] READ drivers/$driverId => exists=${snap.exists} keys=${root.keys.toList()}");
    }

    // Helpers
    String _s(dynamic v) {
      if (v == null) return '';
      if (v is String) return v.trim();
      if (v is num || v is bool) return v.toString();
      return '';
    }

    double _d(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    // 2) vehicleType: من الجذر فقط، ولو فاضي استخدم fallback من الطلب
    String vehicleType = _s(root['vehicleType'] ?? root['carType']);
    if (vehicleType.isEmpty) vehicleType = _s(fallbackVehicleType);

    // 3) name/phone من الجذر فقط (بدون أي fallback من location)
    final name = _s(
        root['name'] ?? root['fullName'] ?? root['driverName'] ?? root['driver_name']);
    final phone = _s(root['phone'] ?? root['phoneNumber'] ?? root['mobile']);

    // 4) car_details من الجذر
    Map<String, dynamic> carDetails = {};
    final cd = root['car_details'];
    if (cd is Map) {
      carDetails = Map<String, dynamic>.from(cd);
    } else if (cd is String && cd.trim().isNotEmpty) {
      try {
        final dec = json.decode(cd);
        if (dec is Map) carDetails = Map<String, dynamic>.from(dec);
      } catch (_) {}
    }

    final carModel =
    _s(carDetails['carModel'] ?? carDetails['model'] ?? carDetails['car_model']);
    final carColor =
    _s(carDetails['carColor'] ?? carDetails['color'] ?? carDetails['car_color']);
    final carNumber = _s(carDetails['carNumber'] ??
        carDetails['plate'] ??
        carDetails['carPlate'] ??
        carDetails['car_number'] ??
        carDetails['number']);

    // 5) صورة/تقييم من الجذر
    final photoUrl = _s(root['photoUrl'] ??
        root['avatar'] ??
        root['avatarUrl'] ??
        root['image'] ??
        root['imageUrl']);
    final rating = _d(root['rating'] ?? root['rate'] ?? root['stars']);

    if (kDebugMode) {
      debugPrint("[DriversRepo] BUILT from drivers/$driverId => "
          "name=$name, phone=$phone, vType=$vehicleType, carModel=$carModel, carColor=$carColor, carNumber=$carNumber");
    }

    return DriverProfile(
      id: driverId,
      name: name,
      phone: phone,
      vehicleType: vehicleType,
      carModel: carModel,
      carColor: carColor,
      carNumber: carNumber,
      photoUrl: photoUrl,
      rating: rating,
    );
  }

  // ---------- Helpers ----------

  bool _hasBasicInfo(DriverProfile p) => p.name.isNotEmpty || p.phone.isNotEmpty;

  /// تحويل أي قيمة vehicleType لنص سليم:
  /// - لو String => trimmed
  /// - لو Map وفيها أحد المفاتيح ['vehicleType','type','name'] => نختار أول String
  /// - غير كده => ''
  String _sanitizeVehicleType(dynamic vt) {
    if (vt is String) return vt.trim();
    if (vt is Map) {
      for (final key in const ['vehicleType', 'type', 'name']) {
        final v = vt[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  String _asCleanString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is num || v is bool) return v.toString();
    // تجاهل الـ Map/List عشان ما تتحولش لنص بالغلط
    return '';
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}

extension _DriverProfileCopy on DriverProfile {
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
}
