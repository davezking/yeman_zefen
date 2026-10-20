import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ads/ads_providers.dart';
import '../../../prototype/screens/message_screens.dart' show ConsentScreen;

/// Ad consent after a finished game (H15), where Google says it is required: the approved screen,
/// then Google's form, then on iOS Apple's tracking question, then Results. Back does not skip it.
/// Closing the form without answering still goes on to Results; the screen comes back after the
/// next game until consent is answered.
class ConsentRoute extends ConsumerStatefulWidget {
  const ConsentRoute({super.key});

  @override
  ConsumerState<ConsentRoute> createState() => _ConsentRouteState();
}

class _ConsentRouteState extends ConsumerState<ConsentRoute> {
  var _busy = false;

  Future<void> _continue() async {
    if (_busy) return;
    _busy = true;
    try {
      await ref.read(consentServiceProvider).showForm();
    } finally {
      _busy = false;
    }
    if (mounted) context.go('/results');
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: ConsentScreen(onContinue: _continue),
  );
}
