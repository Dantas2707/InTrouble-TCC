import 'package:crud/Pages/home_page.dart';
import 'package:crud/Pages/tela_login.dart';
import 'package:crud/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:crud/services/sos_app_watcher.dart';
import 'package:crud/theme/app_colors.dart';

/// Plugin global para exibir notificações locais.
final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Evita reinicializações repetidas do plugin/canal, inclusive em isolates
/// de background.
bool _areLocalNotificationsInitialized = false;

const String _sosChannelId = 'sos_channel';
const String _sosChannelName = 'Alertas de Emergência';
const String _sosChannelDescription = 'Canal para alertas SOS de vítimas';

/// Canal específico para alertas de SOS.
const AndroidNotificationChannel _sosChannel = AndroidNotificationChannel(
  _sosChannelId, // id
  _sosChannelName, // name
  description: _sosChannelDescription,
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('sos_alarm'),
);

/// Handler chamado quando uma mensagem push chega com o app em background ou
/// terminado. É obrigatório estar em nível superior e anotado como entry-point.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Necessário para que o Firebase funcione no isolate de background.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Garante que o canal de notificação existe antes de tocar o alarme.
  await _initLocalNotifications();

  if (message.data['tipo'] == 'SOS') {
    await _mostrarAlertaSOS(message);
  }
}

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

  // Registra o handler global para receber mensagens em background/terminado.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Cria o canal de notificação para SOS (Android) antes do runApp.
  // O arquivo de som customizado deve estar em
  // android/app/src/main/res/raw/sos_alarm.mp3
  await _initLocalNotifications();

  // Configura os listeners do Firebase Cloud Messaging.
  await setupFirebaseMessaging();

  // Inicia o coordenador global que observa login e SOS "aberto"
  SosAppWatcher.instance.start();

  runApp(const MyApp());
}

/// Inicializa o plugin de notificações locais e cria o canal "sos_channel".
Future<void> _initLocalNotifications() async {
  if (_areLocalNotificationsInitialized) return;

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(
    android: androidSettings,
  );

  await _flutterLocalNotificationsPlugin.initialize(initSettings);

  final androidPlugin = _flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(_sosChannel);

  _areLocalNotificationsInitialized = true;
}

/// Configura os listeners do Firebase Messaging para receber push.
Future<void> setupFirebaseMessaging() async {
  // (Opcional) solicita permissões para receber notificações.
  await FirebaseMessaging.instance.requestPermission();

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final tipo = message.data['tipo'];

    // Se for um alerta SOS, mostra notificação com alarme forte.
    if (tipo == 'SOS') {
      _mostrarAlertaSOS(message);
    }
    // Outros tipos podem ser tratados aqui futuramente (ex.: notificações comuns).
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    final idOcorrencia = message.data['id_ocorrencia'];
    // TODO: Navegar para a tela de detalhes da ocorrência usando o ID acima.
  });
}

/// Exibe a notificação local de SOS com som de alarme e prioridade máxima.
Future<void> _mostrarAlertaSOS(RemoteMessage message) async {
  const androidDetails = AndroidNotificationDetails(
    _sosChannelId,
    _sosChannelName,
    channelDescription: _sosChannelDescription,
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('sos_alarm'),
    fullScreenIntent: true,
  );

  const notificationDetails = NotificationDetails(android: androidDetails);

  await _flutterLocalNotificationsPlugin.show(
    // Utiliza um ID fixo ou gere um aleatório se preferir.
    0,
    '⚠️ SOS - Pedido de ajuda',
    'Atenção! A vítima acionou o SOS, verifique imediatamente.',
    notificationDetails,
    payload: message.data['id_ocorrencia'],
  );
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
        primaryColor: AppColors.primary,

        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),

        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.primary,
          selectionColor: AppColors.primary.withOpacity(0.2),
          selectionHandleColor: AppColors.primary,
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.grayLight,
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
              color: AppColors.primary,
              width: 1.5,
            ),
          ),
          labelStyle: const TextStyle(
            color: Color.fromARGB(255, 120, 96, 102),
          ),
        ),


        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
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
