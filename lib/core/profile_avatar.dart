import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/avatar_repository.dart';
import 'initial_avatar.dart';

/// The signed-in user's photo, falling back to [InitialAvatar] while it
/// loads, when there is none, or when it fails to load.
///
/// [AvatarRepository] is only read when there IS a [path], so screens shown
/// for a profile with no photo do not need one provided.
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    required this.path,
    this.radius = 20,
  });

  final String name;
  final String? path;
  final double radius;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  // Held across rebuilds: a FutureBuilder handed a fresh future on every
  // build restarts from "waiting" and flashes the initial each time.
  Future<String>? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _url ??= _lookup();
  }

  @override
  void didUpdateWidget(ProfileAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _url = _lookup();
  }

  Future<String>? _lookup() {
    final p = widget.path;
    return p == null ? null : context.read<AvatarRepository>().signedUrl(p);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = InitialAvatar(name: widget.name, radius: widget.radius);
    final url = _url;
    if (url == null) return fallback;
    final size = widget.radius * 2;
    return FutureBuilder<String>(
      future: url,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return fallback;
        return ClipOval(
          child: Image.network(
            data,
            key: const Key('profile_avatar_image'),
            width: size,
            height: size,
            fit: BoxFit.cover,
            frameBuilder: (_, child, frame, wasSync) =>
                frame == null && !wasSync ? fallback : child,
            errorBuilder: (_, __, ___) => fallback,
          ),
        );
      },
    );
  }
}
