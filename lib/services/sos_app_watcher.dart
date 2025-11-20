import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crud/services/sos_location_tracker.dart';

class SosAppWatcher {
  SosAppWatcher._();
  static final SosAppWatcher instance = SosAppWatcher._();

  final _tracker = SosLocationTracker(); // Seu tracker de localização
  StreamSubscription<QuerySnapshot>? _sosSub;

  // Inicia a escuta em segundo plano para o status do SOS
  void start() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _sosSub = FirebaseFirestore.instance
        .collection('ocorrencias')
        .where('ownerUid', isEqualTo: uid)
        .where('status', isEqualTo: 'aberto')
        .limit(1)
        .snapshots()
        .listen((snap) async {
      final ativo = snap.docs.isNotEmpty;

      try {
        if (ativo) {
          // Se o SOS estiver aberto, ativa o rastreamento
          final ok = await _garantirPermissaoLocalizacao();
          if (ok) {
            await _tracker.start();
          }
        } else {
          // Se o SOS for fechado, desliga o rastreamento
          await _tracker.stop();
        }
      } catch (e) {
        print("Erro ao monitorar SOS: $e");
      }
    });
  }

  // Verifica e solicita permissões de localização
  Future<bool> _garantirPermissaoLocalizacao() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("GPS não ativado!");
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      print("Permissão de localização negada!");
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      print("Permissão negada permanentemente!");
      return false;
    }

    return true;
  }

  // Encerra a escuta e o rastreamento
  void stop() {
    _sosSub?.cancel();
    _tracker.stop();
  }
}
