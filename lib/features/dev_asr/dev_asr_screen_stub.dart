/// Web stub for the dev ASR screen.
///
/// The real dev screen (dev_asr_screen.dart) imports dart:io, record,
/// and onnxruntime — none of which are available on web. This stub
/// provides the same [DevAsrScreen] class so that home_screen.dart can
/// use a conditional import and compile on both platforms.
library;

import 'package:flutter/material.dart';

class DevAsrScreen extends StatelessWidget {
  const DevAsrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dev ASR Testing')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'On-device ASR testing is not available on web.\n\n'
            'This screen requires a physical Android device with the '
            'onnxruntime model and microphone access.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
