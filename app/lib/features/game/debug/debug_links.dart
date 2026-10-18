import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';

/// Links to the spike's measurement screens. Developer tooling in English only, shown in the dev
/// flavor and never in a prod build, so it is not part of the translated UI.
class DebugLinks extends StatelessWidget {
  const DebugLinks({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppConfig.flavor != 'dev') return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => context.push('/debug/clip-playback'),
          child: const Text('Clip playback debug'),
        ),
        TextButton(
          onPressed: () => context.push('/debug/sessions'),
          child: const Text('Saved sessions debug'),
        ),
      ],
    );
  }
}
