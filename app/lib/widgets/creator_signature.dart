import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Discreet creator signature. Home screen only; never overlay on player/chat.
class CreatorSignature extends StatelessWidget {
  const CreatorSignature({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 16, bottom: 12),
      child: Center(
        child: Text(
          'TanimSarker',
          semanticsLabel: 'Created by TanimSarker',
          style: OrvellaTokens.of(context).signatureStyle,
        ),
      ),
    );
  }
}
