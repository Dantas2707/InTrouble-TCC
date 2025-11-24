import 'package:crud/Pages/home_page.dart';
import 'package:crud/Pages/tela_login.dart';
import 'package:crud/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// 👇 IMPORTANTE: watcher global que observa login + SOS
import 'package:crud/services/sos_app_watcher.dart';

// ====== PALETA GLOBAL ======
const kRosaClaro = Color(0xFFF2C4CD);      // #F2C4CD
const kRosaMuitoClaro = Color(0xFFF2DFE0); // #F2DFE0
const kCinzaClaro = Color(0xFFF2F2F2);     // #F2F2F2

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Só loga no console pra debug
    // ignore: avoid_print
    print("Erro ao inicializar o Firebase: $e");
  }

  // Inicia o coordenador global que observa login e SOS "aberto"
  SosAppWatcher.instance.start();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InTrouble',
      debugShowCheckedModeBanner: false,

      // ====== TEMA GLOBAL (rosa) ======
      theme: ThemeData(
        useMaterial3: false,
        primaryColor: kRosaClaro,

        colorScheme: ColorScheme.fromSeed(
          seedColor: kRosaClaro,
          brightness: Brightness.light,
        ),

        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: kRosaClaro,
          selectionColor: Color(0x33F2C4CD),
          selectionHandleColor: kRosaClaro,
        ),

        inputDecorationTheme: InputDecorationTheme(
  filled: true,
  fillColor: kCinzaClaro,
  // tiramos o borderRadius daqui 👇
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide.none,
  ),
  focusedBorder: const OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(18)),
    borderSide: BorderSide(
      color: kRosaClaro,
      width: 1.5,
    ),
  ),
  labelStyle: const TextStyle(
    color: Color.fromARGB(255, 120, 96, 102),
  ),
),


        appBarTheme: const AppBarTheme(
          backgroundColor: kRosaClaro,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),

      // ====== LOCALIZAÇÃO (pt-BR) ======
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: const AuthGate(),
    );
  }
}

/// Decide qual tela mostrar:
/// - logado  -> HomePage
/// - deslogado -> TelaLogin
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const HomePage();
        }
        return const TelaLogin();
      },
    );
  }
}
