import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/models.dart';

/// Emojis that float up over the video when anyone in the party reacts.
class ReactionOverlay extends StatefulWidget {
  const ReactionOverlay({required this.stream, super.key});

  final Stream<Reaction> stream;

  @override
  State<ReactionOverlay> createState() => _ReactionOverlayState();
}

class _Floating {
  _Floating(this.id, this.reaction, this.x);
  final int id;
  final Reaction reaction;
  final double x;
}

class _ReactionOverlayState extends State<ReactionOverlay> {
  final List<_Floating> _items = [];
  final Random _random = Random();
  StreamSubscription<Reaction>? _sub;
  int _next = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen((r) {
      if (!mounted) return;
      setState(() => _items.add(_Floating(_next++, r, _random.nextDouble())));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final item in _items)
              Positioned(
                key: ValueKey(item.id),
                left: item.x * max(0, c.maxWidth - 72),
                bottom: 0,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 2500),
                  onEnd: () {
                    if (mounted) setState(() => _items.remove(item));
                  },
                  builder: (context, t, child) => Opacity(
                    opacity: 1 - t,
                    child: Transform.translate(
                      offset: Offset(0, -t * c.maxHeight * 0.8),
                      child: child,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.reaction.emoji,
                        style: const TextStyle(fontSize: 34),
                      ),
                      Text(
                        item.reaction.fromName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
