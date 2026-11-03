import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../application/services/security/receipt_store.dart';

class ReceiptImage extends StatefulWidget {
  final String path;
  final double? width, height;
  final BoxFit fit;
  const ReceiptImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });
  @override
  State<ReceiptImage> createState() => _ReceiptImageState();
}

class _ReceiptImageState extends State<ReceiptImage> {
  late Future<Uint8List> _bytes;
  @override
  void initState() {
    super.initState();
    _bytes = ReceiptStore().read(widget.path);
  }

  @override
  void didUpdateWidget(covariant ReceiptImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _bytes = ReceiptStore().read(widget.path);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Receipt unavailable'));
        }
        return Image.memory(
          snapshot.data!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          semanticLabel: 'Receipt photo',
          errorBuilder: (_, error, stack) =>
              const Center(child: Text('Receipt unavailable')),
        );
      },
    ),
  );
}
