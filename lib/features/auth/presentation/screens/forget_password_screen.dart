import 'package:email_validator/email_validator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gap/gap.dart';
import 'package:users/core/constants/global.dart';

import 'login_screen.dart';

class ForgetPasswordScreen extends StatefulWidget {
  const ForgetPasswordScreen({super.key});

  @override
  State<ForgetPasswordScreen> createState() => _ForgetPasswordScreenState();
}

class _ForgetPasswordScreenState extends State<ForgetPasswordScreen> {
  final emailTextEditingController=TextEditingController();

  //declear a GlobalKey
  final _formKey=GlobalKey<FormState>();

  void _submit(){
    firebaseAuth.sendPasswordResetEmail(
        email:emailTextEditingController.text.trim()
    ).then((value){
      Fluttertoast.showToast(msg: "We have send you  an email to resover passowrd, please check email");
    }).catchError((errorMessage){
      Fluttertoast.showToast(msg: "Error Occured:\n $errorMessage" );
    });
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
                  "Forget Password",
                  style: TextStyle(
                      color: darkTheme ? Colors.purple:Colors.blue,
                      fontSize: 25,
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
                              SizedBox(height: 20,),

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
                                    "Send Reset Password",
                                    style: TextStyle(
                                      fontSize: 20,
                                    ),

                                  )),
                              SizedBox(height: 10,),
                              SizedBox(height: 10,),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Already have an account?",
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

                                    child: Text("Login",
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
