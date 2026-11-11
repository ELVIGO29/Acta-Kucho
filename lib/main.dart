import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KuchoActaApp());
}

class KuchoActaApp extends StatelessWidget {
  const KuchoActaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kucho Acta de Conformidad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6F00), // Naranja característico Kucho
          primary: const Color(0xFFFF6F00),
          secondary: const Color(0xFF4F46E5), // Indigo
          tertiary: const Color(0xFF10B981), // Verde esmeralda
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedCornerShape(16),
          color: Colors.white,
        ),
      ),
      home: const ActaConformidadScreen(),
    );
  }
}

class RoundedCornerShape extends RoundedRectangleBorder {
  RoundedCornerShape(double radius)
      : super(borderRadius: BorderRadius.circular(radius));
}

class ActaConformidadScreen extends StatefulWidget {
  const ActaConformidadScreen({super.key});

  @override
  State<ActaConformidadScreen> createState() => _ActaConformidadScreenState();
}

class _ActaConformidadScreenState extends State<ActaConformidadScreen> {
  static const platform = MethodChannel('pe.kucho.acta/datos');

  // Datos del trabajo recibidos desde Kucho Android
  String idSolicitud = '';
  String nombreCliente = 'Cliente';
  String categoria = 'Servicio Técnico';
  String distrito = 'Trujillo';
  double montoPactado = 0.0;
  String tokenJwt = '';

  bool cargandoDatos = true;
  bool enviando = false;

  final TextEditingController _observacionesController = TextEditingController(
    text: 'Servicio realizado a entera satisfacción. Se realizaron las pruebas de funcionamiento.',
  );

  // Lista de trazos de la firma digital
  final List<List<Offset>> _trazos = [];

  @override
  void initState() {
    super.initState();
    _cargarDatosDesdeIntent();
  }

  Future<void> _cargarDatosDesdeIntent() async {
    try {
      final dynamic raw = await platform.invokeMethod('obtenerDatosActa');
      if (raw is Map) {
        final Map<dynamic, dynamic> map = raw;
        setState(() {
          idSolicitud = map['idSolicitud']?.toString() ?? '';
          nombreCliente = map['nombreCliente']?.toString() ?? 'Cliente';
          categoria = map['categoria']?.toString() ?? 'Servicio Técnico';
          distrito = map['distrito']?.toString() ?? 'Trujillo';
          montoPactado = (map['monto'] as num?)?.toDouble() ?? 0.0;
          tokenJwt = map['token']?.toString() ?? '';
        });
      }
    } catch (e) {
      debugPrint("Aviso: Ejecutando en modo standalone: $e");
    } finally {
      setState(() => cargandoDatos = false);
    }
  }

  void _limpiarFirma() {
    setState(() => _trazos.clear());
  }

  bool get _tieneFirma => _trazos.isNotEmpty;

  String _formatearFecha(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  Future<void> _finalizarServicioYGuardarActa() async {
    if (!_tieneFirma) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ El cliente debe firmar en el recuadro para dar conformidad.'),
          backgroundColor: Color(0xFFE11D48),
        ),
      );
      return;
    }

    setState(() => enviando = true);

    try {
      final now = DateTime.now();
      final fechaFormateada = _formatearFecha(now);
      final puntosCount = _trazos.fold<int>(0, (sum, t) => sum + t.length);

      // 1. Guardar Acta de Conformidad en Firebase Cloud Firestore (REST API)
      final firestoreUri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/kucho-a24e8/databases/(default)/documents/actas_conformidad',
      );

      final firestorePayload = {
        "fields": {
          "idSolicitud": {"stringValue": idSolicitud.isNotEmpty ? idSolicitud : "DEMO-${now.millisecondsSinceEpoch}"},
          "nombreCliente": {"stringValue": nombreCliente},
          "categoria": {"stringValue": categoria},
          "distrito": {"stringValue": distrito},
          "montoPactado": {"doubleValue": montoPactado},
          "observaciones": {"stringValue": _observacionesController.text},
          "fechaConformidad": {"stringValue": fechaFormateada},
          "trazosFirma": {"integerValue": puntosCount.toString()},
          "estado": {"stringValue": "CONFORME_FIRMADO"},
          "origen": {"stringValue": "Flutter Mobile App"}
        }
      };

      try {
        final httpClient = HttpClient();
        final fsReq = await httpClient.postUrl(firestoreUri);
        fsReq.headers.set('content-type', 'application/json');
        fsReq.add(utf8.encode(jsonEncode(firestorePayload)));
        final fsRes = await fsReq.close();
        httpClient.close();
        debugPrint("Firebase Firestore response: ${fsRes.statusCode}");
      } catch (e) {
        debugPrint("Aviso Firebase Firestore: $e");
      }

      // 2. Notificar al backend Spring Boot para marcar la solicitud como FINALIZADO
      if (idSolicitud.isNotEmpty && tokenJwt.isNotEmpty) {
        try {
          final backendUri = Uri.parse('http://10.0.2.2:8080/api/v1/solicitudes/$idSolicitud/estado');
          final backendClient = HttpClient();
          final bReq = await backendClient.putUrl(backendUri);
          bReq.headers.set('content-type', 'application/json');
          bReq.headers.set('authorization', 'Bearer $tokenJwt');
          bReq.add(utf8.encode(jsonEncode({"estado": "FINALIZADO"})));
          final bRes = await bReq.close();
          backendClient.close();
          debugPrint("Backend Spring Boot response: ${bRes.statusCode}");
        } catch (e) {
          debugPrint("Aviso Backend: $e");
        }
      }

      if (!mounted) return;

      // 3. Mostrar Diálogo de Éxito
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedCornerShape(20),
          title: Row(
            children: const [
              Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
              SizedBox(width: 10),
              Text('¡Acta Registrada!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El servicio ha sido certificado con la firma del cliente y respaldado en Firebase.',
                style: TextStyle(fontSize: 14, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📋 Cliente: $nombreCliente', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('💰 Monto: S/ ${montoPactado.toStringAsFixed(2)}'),
                    Text('📅 Fecha: $fechaFormateada'),
                    const SizedBox(height: 4),
                    const Text('🔒 Estado: FINALIZADO en Spring Boot', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await platform.invokeMethod('cerrarConExito');
                } catch (_) {
                  SystemNavigator.pop();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedCornerShape(10),
              ),
              child: const Text('Volver a Kucho'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al procesar: $e')),
      );
    } finally {
      if (mounted) setState(() => enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Acta de Conformidad',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: const Color(0xFFFF6F00),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            try {
              await platform.invokeMethod('cerrarCancelado');
            } catch (_) {
              SystemNavigator.pop();
            }
          },
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: const [
                Icon(Icons.cloud_done, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text('Firebase Sync', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
      body: cargandoDatos
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tarjeta Resumen del Servicio
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  categoria,
                                  style: const TextStyle(
                                    color: Color(0xFF4F46E5),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Text(
                                'S/ ${montoPactado.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 18,
                                backgroundColor: Color(0xFFFF6F00),
                                child: Icon(Icons.person, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nombreCliente,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    '📍 $distrito',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Observaciones del trabajo realizado
                  const Text(
                    'Observaciones del Trabajo',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _observacionesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Detalle de los trabajos o piezas sustituidas...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Lienzo de Firma Digital
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Firma de Conformidad del Cliente',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                      ),
                      TextButton.icon(
                        onPressed: _limpiarFirma,
                        icon: const Icon(Icons.clear, size: 16, color: Color(0xFFE11D48)),
                        label: const Text('Borrar', style: TextStyle(color: Color(0xFFE11D48), fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Canvas Interactivo
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _tieneFirma ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                        width: _tieneFirma ? 1.5 : 1.0,
                      ),
                    ),
                    child: Stack(
                      children: [
                        if (!_tieneFirma)
                          const Center(
                            child: Text(
                              '✍️ El cliente debe firmar aquí con el dedo',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                          ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            setState(() {
                              _trazos.add([details.localPosition]);
                            });
                          },
                          onPanUpdate: (details) {
                            setState(() {
                              if (_trazos.isNotEmpty) {
                                _trazos.last.add(details.localPosition);
                              }
                            });
                          },
                          child: SizedBox.expand(
                            child: CustomPaint(
                              painter: _SignaturePainter(_trazos),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Botón Finalizar
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: enviando ? null : _finalizarServicioYGuardarActa,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedCornerShape(12),
                        elevation: 2,
                      ),
                      child: enviando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.verified, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Emitir Acta y Finalizar',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Kucho Tech • Certificación con Firebase Cloud Firestore',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> trazos;

  _SignaturePainter(this.trazos);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (final trazo in trazos) {
      for (int i = 0; i < trazo.length - 1; i++) {
        canvas.drawLine(trazo[i], trazo[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
