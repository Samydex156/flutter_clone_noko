import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:lan_scanner/lan_scanner.dart';

void main() {
  runApp(const NokoPrintClone());
}

class NokoPrintClone extends StatelessWidget {
  const NokoPrintClone({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NokoPrint Clone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.light,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Printer> _printers = [];
  bool _isScanning = false;
  String? _wifiName;
  String? _localIp;
  final NetworkInfo _networkInfo = NetworkInfo();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _getWifiInfo();
  }

  Future<void> _getWifiInfo() async {
    try {
      final wifiName = await _networkInfo.getWifiName();
      final localIp = await _networkInfo.getWifiIP();
      setState(() {
        _wifiName = wifiName ?? "WiFi Red Local";
        _localIp = localIp;
      });
    } catch (e) {
      debugPrint("Error obteniendo WiFi: $e");
    }
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();
  }

  // Escaneo estándar (Android Print Framework)
  Future<void> _scanPrinters() async {
    setState(() => _isScanning = true);
    try {
      final printers = await Printing.listPrinters();
      setState(() {
        _printers = printers;
        _isScanning = false;
      });
    } catch (e) {
      setState(() => _isScanning = false);
      _showError('Error: $e');
    }
  }

  // Escaneo Profundo por IP (Estilo NokoPrint)
  Future<void> _deepScanIP() async {
    if (_localIp == null) {
      _showError('No se detecta IP local. Verifica tu conexión WiFi.');
      return;
    }

    setState(() {
      _isScanning = true;
      _printers.clear(); // Limpiamos para el nuevo escaneo
    });

    final scanner = LanScanner();

    // Obtenemos la subred (ej: 192.168.1)
    final String subnet = _localIp!.substring(0, _localIp!.lastIndexOf('.'));

    debugPrint('Iniciando escaneo profundo en subred: $subnet');

    // En la versión 4.0.0 de lan_scanner, el resultado del stream es un HostModel
    // Pero si da error "Undefined class", usaremos var para que Dart lo infiera.
    final stream = scanner.icmpScan(subnet, scanThreads: 20);

    stream.listen(
      (host) async {
        // En lan_scanner 4.x el objeto Host tiene internetAddress
        final String hostIp = host.internetAddress.address;

        try {
          // Probamos el puerto 9100 (estándar de impresoras)
          final socket = await Socket.connect(
            hostIp,
            9100,
            timeout: const Duration(milliseconds: 500),
          );
          socket.destroy();

          // Si conectó, es probablemente una impresora
          final manualPrinter = Printer(
            name: 'Impresora Detectada ($hostIp)',
            url: 'ipp://$hostIp:9100',
            isAvailable: true,
          );

          setState(() {
            // Eliminamos p.url != null porque parece que en esta versión es no-nulo
            if (!_printers.any((p) => p.url.contains(hostIp))) {
              _printers.add(manualPrinter);
            }
          });
        } catch (_) {
          // No es una impresora en ese puerto
        }
      },
      onDone: () {
        if (mounted) {
          setState(() => _isScanning = false);
          if (_printers.isEmpty) {
            _showError('No se hallaron impresoras con puerto 9100 abierto.');
          }
        }
      },
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickAndPrint() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        final pdfBytes = await file.readAsBytes();
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
          name: result.files.single.name,
        );
      }
    } catch (e) {
      _showError('Error al abrir archivo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'NokoPrint Clone',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E88E5),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _getWifiInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1E88E5),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Red: $_wifiName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'IP: ${_localIp ?? "Detectando..."}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Icon(Icons.router, color: Colors.white70),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? null : _scanPrinters,
                        icon: const Icon(Icons.search),
                        label: const Text('Búsqueda Rápida'),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? null : _deepScanIP,
                        icon: const Icon(Icons.radar),
                        label: const Text('Escaneo IP'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isScanning) const LinearProgressIndicator(),
          Expanded(
            child: _printers.isEmpty
                ? Center(
                    child: Opacity(
                      opacity: 0.5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.print_outlined, size: 100),
                          const SizedBox(height: 10),
                          const Text(
                            'Usa "Escaneo IP" si tu impresora no aparece',
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(15),
                    itemCount: _printers.length,
                    itemBuilder: (context, index) {
                      final printer = _printers[index];
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.print, color: Colors.blue),
                          title: Text(printer.name),
                          subtitle: Text(printer.url),
                          onTap: () {
                            _showError(
                              'Impresora seleccionada: ${printer.name}',
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _pickAndPrint,
                icon: const Icon(Icons.file_upload),
                label: const Text(
                  'SELECCIONAR PDF E IMPRIMIR',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
