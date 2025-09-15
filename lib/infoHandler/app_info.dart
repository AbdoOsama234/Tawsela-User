import 'package:flutter/cupertino.dart';
import 'package:users/models/directions.dart';

class AppInfo extends ChangeNotifier{
  Directions? userPickupLocation,userDropOffLocation;
  //List<String>historyTripsKeysList=[];
  //List<TripsHistoryModel>allTripHistoryInformationList=[];



 void updatePickUpLocationAddress(Directions userPickUpAddress){
   userPickupLocation=userPickUpAddress;
   notifyListeners();
 }

 void updateDropOffLocationAddress(Directions dropOffAddress){

   userDropOffLocation=dropOffAddress;
   notifyListeners();


 }
}