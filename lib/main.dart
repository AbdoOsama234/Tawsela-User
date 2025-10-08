import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:users/features/auth/presentation/screens/login_screen.dart';
import 'package:users/shared/state/app_info.dart';
import 'package:users/core/theme/theme_provider.dart';

import 'core/config/firebase_options.dart';
import 'features/ride/presentation/screens/main_screen.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized(); // 👈 السطر المهم

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
        create: (context)=>AppInfo(),
      child: MaterialApp(
        title: 'Flutter Demo',
        themeMode: ThemeMode.system,
        theme: MyThemes.lightTheme,
        darkTheme: MyThemes.darkTheme,

        debugShowCheckedModeBanner: false ,
        home: MainScreen( ),
      ),
    );
  }
}


