import 'package:expencify/presentation/theme/app_icons.dart';
import '../../widgets/receipt_image.dart';
import 'package:flutter/material.dart';

/// Full-screen receipt image viewer with pinch-to-zoom.
class ReceiptFullscreen extends StatelessWidget {
  final String imagePath;
  const ReceiptFullscreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Receipt', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(AppIcons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Center(child: ReceiptImage(path: imagePath)),
        ),
      ),
    );
  }
}
