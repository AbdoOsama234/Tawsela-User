import 'package:email_validator/email_validator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gap/gap.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:users/core/constants/global.dart';

import '../../../ride/presentation/screens/main_screen.dart';
import 'forget_password_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameTextEditingController=TextEditingController();
  final emailTextEditingController=TextEditingController();
  final phoneTextEditingController=TextEditingController();
  final addressTextEditingController=TextEditingController();
  final passwordTextEditingController=TextEditingController();
  final confirmTextEditingController=TextEditingController();

  bool _passworsVisible=false;

  //declare a GlobalKey
  final _formKey=GlobalKey<FormState>();
  void _submit()async{
    //validate all the formfield
    if(_formKey.currentState!.validate()){
      await firebaseAuth.createUserWithEmailAndPassword(
          email: emailTextEditingController.text.trim(),
          password: passwordTextEditingController.text.trim(),
      ).then((auth)async{
        currentUser=auth.user;

        if(currentUser!=null){
          Map userMap={
            "id":currentUser!.uid,
            "name":nameTextEditingController.text.trim(),
            "email":emailTextEditingController.text.trim(),
            "address":addressTextEditingController.text.trim(),
            "phone":phoneTextEditingController.text.trim(),
          };
          DatabaseReference userRef=FirebaseDatabase.instance.ref().child("users");
          userRef.child(currentUser!.uid).set(userMap);
        }
        await Fluttertoast.showToast(msg: "Successfully Registered");
        Navigator.push(context, MaterialPageRoute(builder: (c)=>MainScreen()));

      }).catchError((errorMessage){
        Fluttertoast.showToast(msg: "Error accured:\n $errorMessage" );
      });
    }
    else{
      Fluttertoast.showToast(msg: "Not All field are valid");
    }
  }


  @override
  Widget build(BuildContext context) {

    bool darkTheme=MediaQuery.of(context).platformBrightness==Brightness.dark;
    return GestureDetector(
      onTap: (){
        FocusScope.of(context).unfocus();
      },
      child:Scaffold(
        body: ListView(
          padding: EdgeInsets.all(0),
          children: [
            Column(
              children: [
                Image.asset(darkTheme ? "assets/city/city_dark.jpg":"assets/city/city_light.png"),
                SizedBox(height: 20,),
                Text(
                  "Register",
                  style: TextStyle(
                      color: darkTheme ? Colors.purple:Colors.blue,
                      fontSize: 30,
                      fontWeight: FontWeight.bold
                  ),

                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(15,20,15,50),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Form(
                        key: _formKey,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              //Name
                              TextFormField(
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(50)
                                ],
                                decoration: InputDecoration(
                                  hintText: "Name",
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                  ),
                                  filled: true,
                                  fillColor: darkTheme ?Colors.black45:Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(40),
                                    borderSide: BorderSide(
                                      width: 0,
                                      style: BorderStyle.none
                                    )
                                  ),
                                  prefixIcon:Icon(Icons.person,color: darkTheme?Colors.purple:Colors.grey,),

                                ),
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                validator: (text){
                                  if(text==null || text.isEmpty){
                                    return 'Name can\'t be empty';
                                  }
                                  if(text.length<2){
                                    return 'Please enter a valide name';
                                  }
                                  if(text.length > 49){
                                    return 'Name can\'t be more than 50';
                                  }
                                },
                                onChanged: (text)=>setState(() {
                                  nameTextEditingController.text=text;
                                }),

                              ),
                              SizedBox(height: 10,),
                              //Email
                              TextFormField(
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(50)
                                ],
                                decoration: InputDecoration(
                                  hintText: "Email",
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                  ),
                                  filled: true,
                                  fillColor: darkTheme ?Colors.black45:Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(40),
                                      borderSide: BorderSide(
                                          width: 0,
                                          style: BorderStyle.none
                                      )
                                  ),
                                  prefixIcon:Icon(Icons.email,color: darkTheme?Colors.purple:Colors.grey,),

                                ),
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                validator: (text){
                                  if(text==null || text.isEmpty){
                                    return 'Email can\'t be empty';
                                  }
                                  if (!EmailValidator.validate(text)) {
                                    return 'Invalid email';
                                  }
                                  if(text.length<2){
                                    return 'Please enter a valide Email';
                                  }
                                  if(text.length > 99){
                                    return 'Email can\'t be more than 100';
                                  }
                                },
                                onChanged: (text)=>setState(() {
                                 emailTextEditingController.text=text;
                                }),

                              ),
                              SizedBox(height: 10,),
                              //phone
                              IntlPhoneField(
                                initialCountryCode: 'SA',

                                showCountryFlag: true,
                                dropdownIcon: Icon(
                                    Icons.arrow_drop_down,
                                  color: darkTheme? Colors.purple:Colors.grey,
                                ),
                                decoration: InputDecoration(
                                  hintText: "Phone",
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                  ),
                                  filled: true,
                                  fillColor: darkTheme ?Colors.black45:Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(40),
                                      borderSide: BorderSide(
                                          width: 0,
                                          style: BorderStyle.none
                                      )
                                  ),

                                ),
                                onChanged: (text)=>setState(() {
                                  phoneTextEditingController.text=text.completeNumber;
                                }),
                              ),
                              SizedBox(height: 10,),
                              //Address
                              TextFormField(
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(100)
                                ],
                                decoration: InputDecoration(
                                  hintText: "Address",
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                  ),
                                  filled: true,
                                  fillColor: darkTheme ?Colors.black45:Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(40),
                                      borderSide: BorderSide(
                                          width: 0,
                                          style: BorderStyle.none
                                      )
                                  ),
                                  prefixIcon:Icon(Icons.person,color: darkTheme?Colors.purple:Colors.grey,),

                                ),
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                validator: (text){
                                  if(text==null || text.isEmpty){
                                    return 'Address can\'t be empty';
                                  }

                                  if(text.length<2){
                                    return 'Please enter a valide Address';
                                  }

                                },
                                onChanged: (text)=>setState(() {
                                  addressTextEditingController.text=text;
                                }),

                              ),
                              SizedBox(height: 20,),
                              //Password
                              TextFormField(
                                obscureText: !_passworsVisible,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(50)
                                ],
                                decoration: InputDecoration(
                                  hintText: "Password",
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                  ),
                                  filled: true,
                                  fillColor: darkTheme ?Colors.black45:Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(40),
                                      borderSide: BorderSide(
                                          width: 0,
                                          style: BorderStyle.none
                                      )
                                  ),
                                  prefixIcon:Icon(Icons.lock,color: darkTheme?Colors.purple:Colors.grey,),
                                  suffixIcon: IconButton(
                                      onPressed: (){
                                        setState(() {
                                          _passworsVisible=!_passworsVisible;
                                        });
                                      },
                                      icon:Icon(
                                        _passworsVisible ?Icons.visibility:Icons.visibility_off,
                                        color: darkTheme ? Colors.purple :Colors.grey,
                                      )
                                  )

                                ),
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                validator: (text){
                                  if(text==null || text.isEmpty){
                                    return 'Password can\'t be empty';
                                  }

                                  if(text.length<6){
                                    return 'Please enter a valide Password';
                                  }
                                  if(text.length>49){
                                    return "Password can\'t be mor than 50";
                                  }
                                  return null;

                                },
                                onChanged: (text)=>setState(() {
                                  passwordTextEditingController.text=text;
                                }),

                              ),
                              SizedBox(height: 20,),
                              //ConfirmPassword
                              TextFormField(
                                obscureText: !_passworsVisible,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(50)
                                ],
                                decoration: InputDecoration(
                                    hintText: "Confirm Password",
                                    hintStyle: TextStyle(
                                      color: Colors.grey,
                                    ),
                                    filled: true,
                                    fillColor: darkTheme ?Colors.black45:Colors.grey.shade200,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(40),
                                        borderSide: BorderSide(
                                            width: 0,
                                            style: BorderStyle.none
                                        )
                                    ),
                                    prefixIcon:Icon(Icons.lock,color: darkTheme?Colors.purple:Colors.grey,),
                                    suffixIcon: IconButton(
                                        onPressed: (){
                                          setState(() {
                                            _passworsVisible=!_passworsVisible;
                                          });
                                        },
                                        icon:Icon(
                                          _passworsVisible ?Icons.visibility:Icons.visibility_off,
                                          color: darkTheme ? Colors.purple :Colors.grey,
                                        )
                                    )

                                ),
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                validator: (text){
                                  if(text==null || text.isEmpty){
                                    return 'Confirm Password can\'t be empty';
                                  }
                                  if(text!=confirmTextEditingController.text){
                                    return "Password is not match";

                                  }

                                  if(text.length<6){
                                    return 'Please enter a valide Password';
                                  }
                                  if(text.length>49){
                                    return "Password can\'t be mor than 50";
                                  }
                                  return null;

                                },
                                onChanged: (text)=>setState(() {
                                  confirmTextEditingController.text=text;
                                }),

                              ),
                              SizedBox(height: 10,),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:darkTheme ? Colors.purple :Colors.blue,
                                  foregroundColor:darkTheme ? Colors.white :Colors.white ,
                                  elevation: 0, // كل ما الرقم زاد، الظل زاد
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(32)
                                  ),
                                  minimumSize: Size(double.infinity, 50)
                                ),
                                  onPressed: (){
                                  _submit();
                                  },

                                  child: Text(
                                      "Registar",
                                    style: TextStyle(
                                      fontSize: 20,
                                    ),

                                  )),
                              SizedBox(height: 10,),
                              Align(
                                alignment: Alignment.centerRight,
                                child: GestureDetector(
                                  onTap: (){
                                    Navigator.push(context, MaterialPageRoute(builder: (c)=>ForgetPasswordScreen()));

                                  },

                                  child: Text("Forget Password?",
                                    style:TextStyle(
                                      color: darkTheme?Colors.purple :Colors.blue,
                                      fontSize: 14
                                    ),

                                  ),
                                ),
                              ),
                              SizedBox(height: 10,),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                      "Have an account?",
                                    style: TextStyle(
                                      fontSize: 15,
                                      color:Colors.grey
                                    ),


                                  ),
                                  Gap(5),
                                  GestureDetector(
                                    onTap: (){
                                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c)=>LoginScreen()));

                                    },

                                    child: Text("Sign In",
                                      style:TextStyle(
                                          color: darkTheme?Colors.purple :Colors.blue,
                                          fontSize: 14
                                      ),

                                    ),
                                  ),

                                ],
                              )








                            ],
                          ))
                    ],

                  ),
                )


              ],
            )
          ],
        ),
      ) ,
    );
  }
}
