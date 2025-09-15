import 'package:firebase_database/firebase_database.dart';

class UserModel {
  String? phone;
  String? name;
  String? id;
  String? email;
  String? address;

  UserModel({
    this.name,
    this.phone,
    this.id,
    this.email,
    this.address,
  });

  UserModel.formSnapshot(DataSnapshot snap) {
    if (snap.value != null) {
      final data = Map<String, dynamic>.from(snap.value as Map);

      phone = data['phone'];
      name = data['name'];
      id = snap.key; // أو data['id'] لو أنت مخزنه في الداتا
      email = data['email'];
      address = data['address'];
    }
  }
}
