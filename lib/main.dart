import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:lan_scanner/lan_scanner.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(
    const MaterialApp(
      home: SimplePrintApp(),
      debugShowCheckedModeBanner: false,
    ),
  );
}

class SimplePrintApp extends StatefulWidget {
  const SimplePrintApp({super.key});

  @override
  State<SimplePrintApp> createState() => _SimplePrintAppState();
}

class _SimplePrintAppState extends State<SimplePrintApp> {
  String? _printerName;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _loadPrinter();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Solo pedimos localización para el escaneo de red WiFi
    await [Permission.location].request();
  }

  Future<void> _loadPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _printerName = prefs.getString('printer_name');
    });
  }

  Future<void> _pickAndPrint(bool isPhoto, {required bool isCarnet}) async {
    if (_printerName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Toca la barra naranja para buscar la impresora"),
        ),
      );
      return;
    }

    // --- SELECCIÓN DE ORIGEN ---
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ADJUNTAR FOTO"),
        content: const Text("¿De dónde quieres obtener la imagen?"),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            icon: const Icon(Icons.camera_alt),
            label: const Text("CÁMARA"),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text("GALERÍA"),
          ),
        ],
      ),
    );
    if (source == null && isPhoto) return; // Si cancela
    if (!mounted) return; // Verificación de seguridad tras el diálogo

    try {
      Uint8List finalData;

      if (isPhoto) {
        final pdf = pw.Document();
        final List<Uint8List> imagesBytes = [];
        final ImagePicker picker = ImagePicker();

        if (isCarnet) {
          // LÓGICA DE CARNET PASO A PASO
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Tome foto del FRENTE")));
          final XFile? front = await picker.pickImage(
            source: source!,
            imageQuality: 80,
          );
          if (front == null) return;
          imagesBytes.add(await front.readAsBytes());

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Ahora tome foto del DORSO")),
          );
          final XFile? back = await picker.pickImage(
            source: source,
            imageQuality: 80,
          );
          if (back == null) return;
          imagesBytes.add(await back.readAsBytes());
        } else {
          // FOTO NORMAL O MÚLTIPLE
          if (source == ImageSource.gallery) {
            final List<XFile> picked = await picker.pickMultiImage(
              imageQuality: 80,
            );
            for (var f in picked.take(4)) {
              imagesBytes.add(await f.readAsBytes());
            }
          } else {
            final XFile? taken = await picker.pickImage(
              source: source!,
              imageQuality: 80,
            );
            if (taken != null) imagesBytes.add(await taken.readAsBytes());
          }
        }

        if (imagesBytes.isEmpty) return;

        // --- SELECCIÓN DE TAMAÑO (Solo si es 1 foto normal) ---
        String? sizeChoice;
        if (!isCarnet && imagesBytes.length == 1) {
          if (!mounted) return;
          sizeChoice = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("TAMAÑO DE LA FOTO"),
              content: const Text("¿Cómo quieres que se vea en la hoja?"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, "std"),
                  child: const Text("ESTÁNDAR (Centrado)"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, "full"),
                  child: const Text("HOJA COMPLETA"),
                ),
              ],
            ),
          );
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.letter,
            margin: !isCarnet && sizeChoice == "full"
                ? pw.EdgeInsets.zero
                : const pw.EdgeInsets.all(20),
            build: (pw.Context context) {
              if (isCarnet && imagesBytes.length >= 2) {
                // DISEÑO ESPECIAL CARNET (Vertical)
                return pw.Center(
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.SizedBox(
                        height: 230,
                        child: pw.Image(
                          pw.MemoryImage(imagesBytes[0]),
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                      pw.SizedBox(height: 60),
                      pw.SizedBox(
                        height: 230,
                        child: pw.Image(
                          pw.MemoryImage(imagesBytes[1]),
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // CASO 1 FOTO A HOJA COMPLETA
              if (!isCarnet &&
                  imagesBytes.length == 1 &&
                  sizeChoice == "full") {
                return pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Center(
                    child: pw.Image(
                      pw.MemoryImage(imagesBytes[0]),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                );
              }

              // DISEÑO NORMAL (Grid o 1 foto estándar)
              return pw.GridView(
                crossAxisCount: imagesBytes.length > 1 ? 2 : 1,
                childAspectRatio: 1,
                children: imagesBytes.map((bytes) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.all(10),
                    child: pw.Center(
                      child: pw.Image(
                        pw.MemoryImage(bytes),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        );
        finalData = await pdf.save();
      } else {
        // PDF NORMAL (Siempre de archivos)
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (result == null) return;
        finalData = await File(result.files.single.path!).readAsBytes();
      }

      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (format) async => finalData,
        name: isCarnet ? "Carnet" : "Doc",
        format: PdfPageFormat.letter,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/OptalvitoSistemav2.jpg',
                height: 35,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "IMPRESORA OPTALVIS",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Column(
        children: [
          GestureDetector(
            onTap: _showScanner,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: _printerName == null
                  ? Colors.orange.shade800
                  : Colors.green.shade700,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _printerName == null ? Icons.warning : Icons.check_circle,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _printerName ?? "TOCA PARA CONFIGURAR",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                children: [
                  _BigButton(
                    label: "IMPRIMIR DOCUMENTO",
                    sublabel: "(PDFs)",
                    icon: Icons.picture_as_pdf,
                    color: const Color(0xFF1565C0),
                    onTap: () => _pickAndPrint(false, isCarnet: false),
                  ),
                  const SizedBox(height: 20),
                  _BigButton(
                    label: "IMPRIMIR CARNET",
                    sublabel: "(Frente y Dorso)",
                    icon: Icons.contact_page,
                    color: const Color(0xFF00796B),
                    onTap: () => _pickAndPrint(true, isCarnet: true),
                  ),
                  const SizedBox(height: 20),
                  _BigButton(
                    label: "IMPRIMIR FOTOS",
                    sublabel: "(Galería)",
                    icon: Icons.image,
                    color: const Color(0xFF283593),
                    onTap: () => _pickAndPrint(true, isCarnet: false),
                  ),
                ],
              ),
            ),
          ),
          // FOOTER ESTÉTICO (Separado por una línea sutil)
          const Divider(height: 1, color: Color(0xFFE0E0E0)),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            width: double.infinity,
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Version 1.0 • Impresión Rápida",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Desarrollado por ",
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                    const Text(
                      "Samuel Durán",
                      style: TextStyle(
                        color: Color(0xFF1976D2),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      " & ",
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                    const Text(
                      "Antigravity AI",
                      style: TextStyle(
                        color: Color(0xFF1976D2),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.6,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  "BUSCANDO EN RED...",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                if (_isScanning) const LinearProgressIndicator(),
                const SizedBox(height: 15),
                ElevatedButton(
                  onPressed: _isScanning
                      ? null
                      : () => _startScan(setModalState),
                  child: const Text("BUSCAR IMPRESORAS"),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _foundPrinters.length,
                    itemBuilder: (context, i) => ListTile(
                      leading: const Icon(Icons.print),
                      title: Text(_foundPrinters[i].name),
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'printer_name',
                          _foundPrinters[i].name,
                        );
                        await prefs.setString(
                          'printer_url',
                          _foundPrinters[i].url,
                        );
                        setState(() => _printerName = _foundPrinters[i].name);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  final List<Printer> _foundPrinters = [];
  Future<void> _startScan(Function setModalState) async {
    setModalState(() => _isScanning = true);
    _foundPrinters.clear();
    final ip = await NetworkInfo().getWifiIP();
    if (ip == null) return;
    final subnet = ip.substring(0, ip.lastIndexOf('.'));
    final stream = LanScanner().icmpScan(subnet, scanThreads: 20);
    stream.listen((host) async {
      try {
        final s = await Socket.connect(
          host.internetAddress.address,
          9100,
          timeout: const Duration(milliseconds: 500),
        );
        s.destroy();
        setModalState(() {
          _foundPrinters.add(
            Printer(
              name: "Impresora (${host.internetAddress.address})",
              url: "ipp://${host.internetAddress.address}:9100",
              isAvailable: true,
            ),
          );
        });
      } catch (_) {}
    }, onDone: () => setModalState(() => _isScanning = false));
  }
}

class _BigButton extends StatelessWidget {
  final String label, sublabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BigButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 130,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            const BoxShadow(
              color: Colors.black26,
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 50),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              sublabel,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class Printer {
  final String name;
  final String url;
  final bool isAvailable;

  Printer({required this.name, required this.url, required this.isAvailable});
}
