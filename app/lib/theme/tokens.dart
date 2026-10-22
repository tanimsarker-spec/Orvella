import 'package:flutter/material.dart';

@immutable
class OrvellaTokens extends ThemeExtension<OrvellaTokens> {
  const OrvellaTokens({required this.signature});

  /// Muted lavender / soft gray used only by the creator signature.
  final Color signature;

  TextStyle get signatureStyle => TextStyle(
    fontFamily: 'Jost',
    fontWeight: FontWeight.w200,
    fontSize: 11,
    letterSpacing: 1.4,
    color: signature,
  );

  static OrvellaTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<OrvellaTokens>();
    assert(tokens != null, 'OrvellaTokens missing from ThemeData.extensions');
    return tokens!;
  }

  static const dark = OrvellaTokens(signature: Color(0xFFB7A9D6));
  static const light = OrvellaTokens(signature: Color(0xFF7A7690));

  @override
  OrvellaTokens copyWith({Color? signature}) =>
      OrvellaTokens(signature: signature ?? this.signature);

  @override
  OrvellaTokens lerp(ThemeExtension<OrvellaTokens>? other, double t) {
    if (other is! OrvellaTokens) return this;
    return OrvellaTokens(signature: Color.lerp(signature, other.signature, t)!);
  }
}
