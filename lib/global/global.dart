import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:users/models/direction_details_info.dart';
import '../models/user_model.dart';

final FirebaseAuth firebaseAuth = FirebaseAuth.instance;

User? currentUser;

UserModel? userModelCurrentInfo;

/// هنا بيتخزن تفاصيل الرحلة (distance/duration)
DirectionDetailsInfo? tripDirectionDetailsInfo;

String userDropOffAddress = "";
String driverCarDetails = "";
String driverName = "";
String driverPhone = "";

double countRatingStars = 0.0;
String titleStarsRating = "";

// ====== إضافات طلب السائق ======
String? currentRideRequestId;
final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
