import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Paleta rosa
const kRosaMuitoClaro = Color(0xFFF2DFE0); // #F2DFE0
const kRosaClaro = Color(0xFFF2C4CD);      // #F2C4CD
const kRosaMedio = Color(0xFFD9B4BB);      // #D9B4BB
const kRosaSuave = Color(0xFFF2C4C4);      // #F2C4C4
const kCinzaClaro = Color(0xFFF2F2F2);     // #F2F2F2

class GuardianMapPage extends StatefulWidget {
  const GuardianMapPage({Key? key}) : super(key: key);

  @override
  State<GuardianMapPage> createState() => _GuardianMapPageState();
}

class _GuardianMapPageState extends State<GuardianMapPage> {
  GoogleMapController? _map;
  final Set<Marker> _markers = {};
  bool _loading = true;
  String _statusText = 'Carregando…';

  // Subscrições
  StreamSubscription<QuerySnapshot>? _vinculosSub;
  final List<StreamSubscription<QuerySnapshot>> _ocorrenciasSubs = [];
  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
      _ocorrenciasAbertas = {};

  // Cache de nomes (uid -> nome)
  final Map<String, String> _userNames = {};

  // IDs de ocorrências ocultadas localmente (com persistência)
  final Set<String> _hiddenMarkers = {};
  static const String kHiddenKey = 'guardian_hidden_markers'; // chave SharedPreferences

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // await _loadHiddenMarkers();     // NOVO: carrega ocultos do storage (se quiser reativar)
    await _checkLocationPermissions();
    _listenVinculosAceitos();
  }

  @override
  void dispose() {
    _vinculosSub?.cancel();
    for (final s in _ocorrenciasSubs) {
      s.cancel();
    }
    _ocorrenciasAbertas.clear(); // limpa cache ao sair
    _map?.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermissions() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissão de localização negada.')),
      );
    } else if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Permissão de localização negada permanentemente.')),
      );
    } else {
      // OK
    }
  }

  // ======== SharedPreferences: carregar/salvar (se quiser reativar) ========

  // Future<void> _loadHiddenMarkers() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final list = prefs.getStringList(kHiddenKey) ?? const [];
  //   _hiddenMarkers
  //     ..clear()
  //     ..addAll(list);
  // }

  // Future<void> _saveHiddenMarkers() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.setStringList(kHiddenKey, _hiddenMarkers.toList());
  // }

  void _listenVinculosAceitos() {
    final guardiaoUid = FirebaseAuth.instance.currentUser?.uid;
    if (guardiaoUid == null) {
      setState(() {
        _loading = false;
        _statusText = 'Não autenticado';
      });
      return;
    }

    final vinculosRef = FirebaseFirestore.instance
        .collection('guardiões')
        .where('id_guardiao', isEqualTo: guardiaoUid)
        .where('status', isEqualTo: 'aceito');

    _vinculosSub = vinculosRef.snapshots().listen((snap) {
      final victims = <String>[];
      for (final d in snap.docs) {
        final data = d.data() as Map<String, dynamic>;
        final idUsuario = data['id_usuario']?.toString();
        if (idUsuario != null && idUsuario.isNotEmpty) {
          victims.add(idUsuario);
        }
      }

      () async {
        try {
          await _preloadUserNames(victims);
        } catch (_) {}
        _subscribeToOcorrenciasAbertas(victims);
      }();
    }, onError: (_) {
      setState(() {
        _loading = false;
        _statusText = 'Falha ao carregar vínculos';
      });
    });
  }

  // Pré-carregar os nomes das vítimas em lotes de até 10 uids
  Future<void> _preloadUserNames(List<String> uids) async {
    _userNames.clear();
    if (uids.isEmpty) return;

    const chunkSize = 10;
    for (var i = 0; i < uids.length; i += chunkSize) {
      final bloco = uids.sublist(i, (i + chunkSize).clamp(0, uids.length));
      final snap = await FirebaseFirestore.instance
          .collection('usuario')
          .where(FieldPath.documentId, whereIn: bloco)
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final nome = (data['nome'] ??
                data['nomeCompleto'] ??
                data['displayName'] ??
                data['email'] ??
                doc.id)
            .toString();
        _userNames[doc.id] = nome;
      }

      for (final uid in bloco) {
        _userNames.putIfAbsent(uid, () => uid);
      }
    }
  }

  void _subscribeToOcorrenciasAbertas(List<String> victimIds) {
    for (final s in _ocorrenciasSubs) {
      s.cancel();
    }
    _ocorrenciasSubs.clear();
    _ocorrenciasAbertas.clear();

    if (victimIds.isEmpty) {
      setState(() {
        _markers.clear();
        _loading = false;
        _statusText = 'Sem ocorrência SOS no momento';
      });
      return;
    }

    const chunkSize = 10;
    for (var i = 0; i < victimIds.length; i += chunkSize) {
      final bloco =
          victimIds.sublist(i, (i + chunkSize).clamp(0, victimIds.length));

      final q = FirebaseFirestore.instance
          .collection('ocorrencias')
          .where('ownerUid', whereIn: bloco);

      final sub = q.snapshots().listen((snap) {
        for (final change in snap.docChanges) {
          final changeData =
              change.doc.data() as Map<String, dynamic>? ?? const {};
          final newStatus = (changeData['status'] ?? 'aberto').toString();
          final ownerUidSnack =
              changeData['ownerUid']?.toString() ?? 'desconhecido';

          if (change.type == DocumentChangeType.modified) {
            final prev =
                _ocorrenciasAbertas[change.doc.id]?.get('status')?.toString();
            if (prev != 'finalizado' && newStatus == 'finalizado') {
              final ownerNameSnack =
                  _userNames[ownerUidSnack] ?? ownerUidSnack;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'A vítima $ownerNameSnack finalizou a ocorrência.'),
                  ),
                );
              }
            }
          } else if (change.type == DocumentChangeType.removed) {
            _ocorrenciasAbertas.remove(change.doc.id);
          }
        }

        for (final doc in snap.docs) {
          _ocorrenciasAbertas[doc.id] = doc;
        }

        _rebuildMarkersFromCache();
      }, onError: (_) {});

      _ocorrenciasSubs.add(sub);
    }

    setState(() {
      _loading = false;
      _statusText = 'Carregando ocorrências…';
    });
  }

  // Ocultar um marcador da visualização (persiste se reativar o SharedPreferences)
  // void _hideMarker(String ocorrenciaId) async {
  //   setState(() {
  //     _hiddenMarkers.add(ocorrenciaId);
  //   });
  //   await _saveHiddenMarkers();
  //   _rebuildMarkersFromCache();
  // }

  void _openMarkerActions({
    required String ocorrenciaId,
    required String title,
    required String snippet,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color.fromARGB(255, 82, 60, 66),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  snippet,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color.fromARGB(255, 100, 80, 86),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.visibility_off,
                    color: kRosaMedio,
                  ),
                  title: const Text('Excluir da visualização'),
                  subtitle: const Text(
                    'Oculta este alfinete do mapa (não apaga do sistema)',
                    style: TextStyle(fontSize: 13),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    // _hideMarker(ocorrenciaId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ocorrência ocultada da visualização.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _rebuildMarkersFromCache() {
    final markers = <Marker>{};
    int countAbertos = 0;

    _hiddenMarkers.removeWhere((id) => !_ocorrenciasAbertas.containsKey(id));

    for (final doc in _ocorrenciasAbertas.values) {
      if (_hiddenMarkers.contains(doc.id)) continue;

      final data = doc.data() as Map<String, dynamic>;

      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      GeoPoint? gp;
      if (lat == null || lng == null) {
        final maybe = data['localizacao'];
        if (maybe is GeoPoint) gp = maybe;
      }

      final hasCoords = (lat != null && lng != null) || gp != null;
      if (!hasCoords) continue;

      final pos =
          gp != null ? LatLng(gp.latitude, gp.longitude) : LatLng(lat!, lng!);

      final ownerUid = data['ownerUid']?.toString() ?? 'desconhecido';
      final tipo = data['tipoOcorrencia']?.toString() ?? 'SOS';
      final gravidade = data['gravidade']?.toString() ?? '';
      final relato = data['relato']?.toString() ?? '';
      final status = data['status']?.toString() ?? 'aberto';

      if (!_userNames.containsKey(ownerUid)) {
        FirebaseFirestore.instance
            .collection('usuario')
            .doc(ownerUid)
            .get()
            .then((docUser) {
          if (docUser.exists) {
            final d = docUser.data()!;
            final nome = (d['nome'] ??
                    d['nomeCompleto'] ??
                    d['displayName'] ??
                    d['email'] ??
                    ownerUid)
                .toString();
            if (mounted) {
              setState(() {
                _userNames[ownerUid] = nome;
              });
            }
          } else {
            _userNames[ownerUid] = ownerUid;
          }
        }).catchError((_) {
          _userNames[ownerUid] = ownerUid;
        });
      }
      final ownerName = _userNames[ownerUid] ?? ownerUid;

      // Marcadores em tom "rosa" para SOS aberto e azul-claro para finalizado
      final hue = status == 'finalizado'
          ? BitmapDescriptor.hueAzure
          : BitmapDescriptor.hueRose;

      if (status != 'finalizado') countAbertos++;

      final title =
          '$tipo ${gravidade.isNotEmpty ? "($gravidade)" : ""}'.trim();
      final snippet = 'Vítima: $ownerName\n$relato\nStatus: $status';

      markers.add(
        Marker(
          markerId: MarkerId(doc.id),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          onTap: () {
            _openMarkerActions(
              ocorrenciaId: doc.id,
              title: title,
              snippet: snippet,
            );
          },
          infoWindow: InfoWindow(
            title: title,
            snippet: snippet,
            onTap: () {
              _openMarkerActions(
                ocorrenciaId: doc.id,
                title: title,
                snippet: snippet,
              );
            },
          ),
        ),
      );
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(markers);
      _statusText = countAbertos == 0
          ? 'Sem ocorrência SOS no momento'
          : 'SOS abertos: $countAbertos';
    });

    if (_map != null && markers.isNotEmpty) {
      _fitToMarkers(markers);
    }
  }

  Future<void> _fitToMarkers(Set<Marker> markers) async {
    if (_map == null) return;
    if (markers.length == 1) {
      final only = markers.first.position;
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(only, 16));
      return;
    }
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final m in markers) {
      final p = m.position;
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    await _map!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  void _onMapCreated(GoogleMapController controller) {
    _map = controller;
    if (_markers.isNotEmpty) {
      _fitToMarkers(_markers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = _markers.isNotEmpty
        ? _markers.first.position
        : const LatLng(-15.793889, -47.882778);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color.fromARGB(0, 0, 0, 0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Vítimas com SOS aberto',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kRosaClaro, kRosaMedio],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Banner de status
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _markers.isEmpty
                      ? [kCinzaClaro, kCinzaClaro]
                      : [kRosaMuitoClaro, kCinzaClaro],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _markers.isEmpty
                              ? Colors.grey.shade300
                              : kRosaClaro,
                        ),
                        child: Icon(
                          _markers.isEmpty
                              ? Icons.location_off
                              : Icons.warning_amber_rounded,
                          color: _markers.isEmpty
                              ? Colors.grey.shade700
                              : Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _loading ? 'Carregando…' : _statusText,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color.fromARGB(255, 82, 60, 66),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _markers.isEmpty
                                  ? 'Nenhum SOS ativo das vítimas que você acompanha.'
                                  : 'Visualize no mapa as vítimas com SOS aberto em tempo real.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_hiddenMarkers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kRosaMedio),
                          foregroundColor:
                              const Color.fromARGB(255, 120, 96, 102),
                          textStyle: const TextStyle(fontSize: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                        icon: const Icon(Icons.restore, size: 18),
                        label:
                            Text('Mostrar todos (${_hiddenMarkers.length})'),
                        onPressed: () async {
                          setState(() {
                            _hiddenMarkers.clear();
                          });
                          // await _saveHiddenMarkers();
                          _rebuildMarkersFromCache();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Mapa
          Expanded(
            child: Container(
              color: Colors.white,
              child: GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: initial, zoom: 12),
                onMapCreated: _onMapCreated,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                markers: _markers,
                zoomControlsEnabled: true,
                compassEnabled: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
