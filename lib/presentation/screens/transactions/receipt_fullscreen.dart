import 'dart:io';
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
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(child: Image.file(File(imagePath), fit: BoxFit.contain)),
      ),
    );
  }
}
