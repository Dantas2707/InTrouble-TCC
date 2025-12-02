import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crud/theme/app_colors.dart';

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
  String? _guardiaoUid;

  // Subscrições
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _vinculosSub;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _ocorrenciasSubs = [];
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

  void _listenVinculosAceitos() {
    final guardiaoUid = FirebaseAuth.instance.currentUser?.uid;
    if (guardiaoUid == null) {
      setState(() {
        _loading = false;
        _statusText = 'Não autenticado';
      });
      return;
    }

    _guardiaoUid = guardiaoUid;

    final vinculosRef = FirebaseFirestore.instance
        .collection('guardiões')
        .where('id_guardiao', isEqualTo: guardiaoUid)
        .where('status', whereIn: ['aceito', 'ativo']);

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
        _subscribeToOcorrenciasAbertas(
          victims,
          guardiaoUid,
        );
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

  void _subscribeToOcorrenciasAbertas(
    List<String> victimIds,
    String guardiaoUid,
  ) {
    _ocorrenciasSubs.clear();
    _ocorrenciasAbertas.clear();

    if (victimIds.isEmpty) {
      setState(() {
        _markers.clear();
        _loading = false;
        _statusText = 'Sem ocorrências abertas no momento';
      });
      return;
    }

    const chunkSize = 10;
    for (var i = 0; i < victimIds.length; i += chunkSize) {
      final bloco =
          victimIds.sublist(i, (i + chunkSize).clamp(0, victimIds.length));

      void attachQuery(Query<Map<String, dynamic>> query) {
        final sub = query.snapshots().listen((snap) {
          for (final change in snap.docChanges) {
            final changeData =
                change.doc.data() as Map<String, dynamic>? ?? const {};
            final newStatus = (changeData['status'] ?? 'aberto').toString();
            final ownerUidSnack =
                changeData['ownerUid']?.toString() ?? 'desconhecido';

            if (change.type == DocumentChangeType.modified) {
              final prev = _ocorrenciasAbertas[change.doc.id]
                  ?.get('status')
                  ?.toString();
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

      // Ocorrência normal: guardiões em guardioesNotificados
      attachQuery(FirebaseFirestore.instance
          .collection('ocorrencias')
          .where('ownerUid', whereIn: bloco)
          .where('gravidade', isNotEqualTo: 'Gravíssima')
          .where('guardioesNotificados', arrayContains: guardiaoUid)
          .orderBy('gravidade'));

      // SOS: somente id_guardiao deve estar preenchido
      attachQuery(FirebaseFirestore.instance
          .collection('ocorrencias')
          .where('ownerUid', whereIn: bloco)
          .where('gravidade', isEqualTo: 'Gravíssima')
          .where('id_guardiao', arrayContains: guardiaoUid));
    }

    setState(() {
      _loading = false;
      _statusText = 'Carregando ocorrências…';
    });
  }

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
                const Text(
                  'Nenhuma ação disponível.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color.fromARGB(255, 120, 96, 102),
                  ),
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
    int countAbertosNaoSos = 0;

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

     // Cor diferenciada para ocorrências não-SOS
      final statusLower = status.toLowerCase();
      final isNonSos = tipo.toLowerCase() != 'sos';
      final hue = statusLower == 'finalizado'
          ? BitmapDescriptor.hueGreen
          : (isNonSos
              ? BitmapDescriptor.hueYellow
              : BitmapDescriptor.hueRed);

      if (statusLower != 'finalizado' && isNonSos) {
        countAbertosNaoSos++;
      }

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
      _statusText = countAbertosNaoSos == 0
          ? 'Sem ocorrências abertas no momento'
          : 'Ocorrências abertas: $countAbertosNaoSos';
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
        iconTheme: const IconThemeData(color: Color.fromARGB(255, 44, 44, 44)),
        title: const Text(
          'Vítimas com SOS ou ocorrências abertas',
          style: TextStyle(
            color: Color.fromARGB(255, 255, 0, 0),
            fontWeight: FontWeight.w600,
          ),
        ),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryMedium],
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
                      ? [AppColors.grayLight, AppColors.grayLight]
                      : [AppColors.primaryLight, AppColors.grayLight],
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
                              : AppColors.primary,
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
                                  : 'Visualize no mapa as vítimas com SOS ou ocorrências abertas em tempo real.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Em caso de preocupação com seu(s) protegido(s), acione as autoridades competentes. NÃO VÁ AO LOCAL, NEM TOME MEDIDAS POR CONTA PRÓPRIA PARA SUA SEGURANÇA!',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color.fromARGB(255, 120, 40, 40),
                                fontWeight: FontWeight.w600,
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
                          side: const BorderSide(color: AppColors.primaryMedium),
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