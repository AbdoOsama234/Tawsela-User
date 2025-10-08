// lib/features/ride/data/ride_request_repository.dart
import 'package:firebase_database/firebase_database.dart';

class RideRequestRepository {
  final DatabaseReference _db;
  RideRequestRepository({DatabaseReference? db})
      : _db = db ?? FirebaseDatabase.instance.ref();

  DatabaseReference createRideRequestRef() =>
      _db.child('rideRequests').push();

  Future<void> setRideRequest(DatabaseReference ref, Map<String, dynamic> data) =>
      ref.set(data);

  Future<void> updateRideRequest(DatabaseReference ref, Map<String, dynamic> data) =>
      ref.update(data);

  Stream<Map<String, dynamic>?> watchRideRequest(DatabaseReference ref) =>
      ref.onValue.map((e) {
        final v = e.snapshot.value;
        return (v is Map) ? Map<String, dynamic>.from(v) : null;
      });

  Future<void> removeRideRequest(DatabaseReference ref) => ref.remove();
}
