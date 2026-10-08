import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:external_path/external_path.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_cropper/image_cropper.dart';

late List<CameraDescription> _cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const PDFCameraApp());
}

class PDFCameraApp extends StatefulWidget {
  const PDFCameraApp({super.key});
  @override
  State<PDFCameraApp> createState() => _PDFCameraAppState();
}

class _PDFCameraAppState extends State<PDFCameraApp> {
  bool _isDarkMode = false;

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
        primarySwatch: Colors.indigo,
      ),
      home: CameraHome(onToggleTheme: _toggleTheme),
    );
  }
}

class CameraHome extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const CameraHome({super.key, required this.onToggleTheme});

  @override
  State<CameraHome> createState() => _CameraHomeState();
}

class _CameraHomeState extends State<CameraHome> {
  late final CameraController _controller;
  final List<XFile> _capturedImages = [];
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeNotifications();
    Permission.notification.request();
  }

  Future<void> _initializeCamera() async {
    await Permission.camera.request();
    _controller = CameraController(_cameras.first, ResolutionPreset.max, enableAudio: false);
    await _controller.initialize();
    await _controller.setFocusMode(FocusMode.auto);
    setState(() {});
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings settings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notificationsPlugin.initialize(
      const InitializationSettings(android: settings),
      onDidReceiveNotificationResponse: (response) {
        final filePath = response.payload;
        if (filePath != null && filePath.isNotEmpty) OpenFilex.open(filePath);
      },
    );
  }

  Future<void> _toggleFlash() async {
    _flashOn = !_flashOn;
    await _controller.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  Future<void> _takePicture() async {
    final image = await _controller.takePicture();
    _capturedImages.add(image);
    setState(() {});
  }

  void _onTapCameraPreview(TapDownDetails details, BoxConstraints constraints) {
    if (!_controller.value.isInitialized) return;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPos = box.globalToLocal(details.globalPosition);
    final double dx = localPos.dx / constraints.maxWidth;
    final double dy = localPos.dy / constraints.maxHeight;
    final Offset point = Offset(dx, dy);
    _controller.setFocusPoint(point);
    _controller.setExposurePoint(point);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          onTapDown: (details) => _onTapCameraPreview(details, constraints),
          child: Stack(
            children: [
              Positioned.fill(child: CameraPreview(_controller)),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FloatingActionButton(
                        heroTag: 'flash',
                        mini: true,
                        onPressed: _toggleFlash,
                        child: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
                      ),
                      Row(
                        children: [
                          FloatingActionButton(
                            heroTag: 'theme',
                            mini: true,
                            onPressed: widget.onToggleTheme,
                            child: const Icon(Icons.brightness_6),
                          ),
                          const SizedBox(width: 8),
                          FloatingActionButton(
                            heroTag: 'preview',
                            mini: true,
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PreviewScreen(
                                    images: _capturedImages,
                                    onGeneratePDF: _generatePDF,
                                  ),
                                ),
                              );
                              setState(() {});
                            },
                            child: const Icon(Icons.photo_library),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: FloatingActionButton(
                    heroTag: 'capture',
                    onPressed: _takePicture,
                    child: const Icon(Icons.camera),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generatePDF() async {
    if (_capturedImages.isEmpty) return;

    await Permission.manageExternalStorage.request();
    await Permission.storage.request();

    final pdf = pw.Document();
    for (var img in _capturedImages) {
      final bytes = await File(img.path).readAsBytes();
      pdf.addPage(pw.Page(build: (pw.Context ctx) => pw.Center(child: pw.Image(pw.MemoryImage(bytes)))));
    }

    final downloadPath = await ExternalPath.getExternalStoragePublicDirectory("Download");
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final defaultPath = p.join(downloadPath, 'CapturedImages_$timestamp.pdf');
    final defaultFile = File(defaultPath);
    await defaultFile.writeAsBytes(await pdf.save());

    if (!mounted) return;

    final TextEditingController renameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Rename PDF"),
        content: TextField(
          controller: renameController,
          decoration: const InputDecoration(hintText: "Enter new filename"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );

    String newName = renameController.text.trim();
    if (newName.isNotEmpty) {
      final newPath = p.join(downloadPath, '$newName.pdf');
      await defaultFile.rename(newPath);
      _showPDFNotification(newPath);
    } else {
      _showPDFNotification(defaultPath);
    }
  }

  void _showPDFNotification(String filePath) {
    _notificationsPlugin.show(
      0,
      '✅ Your PDF is ready!',
      'Tap to open the PDF',
      NotificationDetails(
        android: AndroidNotificationDetails('pdf_channel', 'PDF Notifications', importance: Importance.max, priority: Priority.high),
      ),
      payload: filePath,
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Success'),
        content: Text('Saved as ${p.basename(filePath)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// PreviewScreen remains unchanged
/// Screen to preview & optionally crop images
class PreviewScreen extends StatefulWidget {
  final List<XFile> images;
  final Future<void> Function() onGeneratePDF;
  const PreviewScreen({super.key, required this.images, required this.onGeneratePDF});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  Future<void> _cropImage(int index) async {
    final CroppedFile? cropped = await ImageCropper().cropImage(sourcePath: widget.images[index].path);
    if (cropped != null) {
      widget.images[index] = XFile(cropped.path);
      setState(() {});
    }
  }

  void _showCropOrDeleteDialog(int index) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.crop),
            title: const Text('Crop'),
            onTap: () {
              Navigator.pop(context);
              _cropImage(index);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(context);
              setState(() {
                File(widget.images[index].path).deleteSync();
                widget.images.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview & Crop'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: widget.onGeneratePDF,
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: widget.images.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => _showCropOrDeleteDialog(index),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.file(
                  File(widget.images[index].path),
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  color: Colors.black45,
                  child: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
