import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/wish_repository.dart';


class WishPhoto extends StatefulWidget {
  const WishPhoto({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  State<WishPhoto> createState() => _WishPhotoState();
}

class _WishPhotoState extends State<WishPhoto> {
  Future<String>? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _url ??= context.read<WishRepository>().photoUrl(widget.path);
  }

  @override
  void didUpdateWidget(WishPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _url = context.read<WishRepository>().photoUrl(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unbounded = widget.fit == BoxFit.fitWidth;
    Widget box(Widget? child) {
      final filled = Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: child,
      );
      return unbounded ? AspectRatio(aspectRatio: 1, child: filled) : filled;
    }

    final broken = box(
      Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
    );
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.hasError) return broken;
        final url = snap.data;
        if (url == null) return box(null);
        return Image.network(
          url,
          key: Key('wish_photo_${widget.path}'),
          width: double.infinity,
          height: unbounded ? null : double.infinity,
          fit: widget.fit,
          frameBuilder: (_, child, frame, wasSync) =>
              frame == null && !wasSync ? box(null) : child,
          errorBuilder: (_, __, ___) => broken,
        );
      },
    );
  }
}
