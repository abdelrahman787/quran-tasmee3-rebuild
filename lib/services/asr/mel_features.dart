/// Pure-Dart 80-dim log-mel spectrogram feature extraction.
///
/// Implements the exact feature pipeline used by the FastConformer-CTC
/// Quran ASR model (spec §4.1). All constants are sourced from
/// model_config.yaml and verified in Gate 0 (Python onnxruntime).
///
/// Constants justification:
///   sampleRate = 16000   — model_config.yaml: sample_rate=16000
///   nFft = 512           — model_config.yaml: n_fft=512
///   winLen = 400         — 25ms window × 16kHz = 400 samples
///   hopLen = 160         — 10ms stride × 16kHz = 160 samples
///   nMels = 80           — model_config.yaml: features=80
///   window = Hann        — model_config.yaml: window=hann
///   normalize = per_feature — model_config.yaml: normalize=per_feature
///                             (per-mel-bin CMVN: mean/std over utterance)
///   logOffset = 2^-24    — README reference: np.log(power + 2**-24)
///   melMaxFreq = 8000    — Nyquist at 16kHz (HTK mel scale upper bound)
///   melMinFreq = 0       — HTK mel scale lower bound
///
/// The output is [80, T] in row-major (mel_bins × time_frames),
/// matching the model input `audio_signal [B, 80, T]`.
///
/// This runs entirely in Dart — no native FFT library, no platform channels.
/// The Cooley-Tukey radix-2 FFT is hand-rolled for 512-point transforms.
library;

import 'dart:math';
import 'dart:typed_data';

/// Audio constants for the FastConformer-CTC model.
///
/// Every value here is justified by model_config.yaml or the README
/// reference implementation. Do NOT change any constant without
/// verifying against the model config first.
class AudioConstants {
  AudioConstants._();

  /// Model sample rate (Hz). From model_config.yaml: sample_rate=16000.
  static const int sampleRate = 16000;

  /// FFT size. From model_config.yaml: n_fft=512.
  static const int nFft = 512;

  /// Window length in samples (25ms × 16kHz). From model_config.yaml:
  /// window_size=0.025 → 400 samples.
  static const int winLen = 400;

  /// Hop length in samples (10ms × 16kHz). From model_config.yaml:
  /// window_stride=0.01 → 160 samples.
  static const int hopLen = 160;

  /// Number of mel filterbank bins. From model_config.yaml: features=80.
  static const int nMels = 80;

  /// CTC blank token ID. 1024 SentencePiece BPE tokens (0-1023) + 1 blank.
  static const int blankId = 1024;

  /// Log offset to avoid log(0). From README: np.log(power + 2**-24).
  static const double logOffset = 5.960464477539063e-08; // 2^-24

  /// Maximum mel frequency (Hz). Nyquist at 16kHz = 8000.
  static const double melMaxFreq = 8000.0;

  /// Minimum mel frequency (Hz).
  static const double melMinFreq = 0.0;

  /// CMVN epsilon for std division (avoid divide-by-zero).
  static const double cmvnEps = 1e-5;

  /// Output frame duration in seconds (8× temporal subsampling).
  /// From README: "80 ms per output frame".
  static const double outputHopSeconds = 0.080;
}

/// Pure-Dart 80-dim log-mel spectrogram extractor.
///
/// Produces features matching the Python reference pipeline:
///   1. Pad audio by (winLen - 1) samples
///   2. Frame with Hann window at hopLen stride
///   3. Compute STFT via radix-2 FFT (nFft=512)
///   4. Power spectrum = |STFT|²
///   5. Apply HTK mel filterbank (80 triangular filters)
///   6. Log-mel = log(filterbank × power + logOffset)
///   7. Per-feature CMVN: (mel - mean) / (std + eps) per mel bin
///
/// Output shape: [80, T] as a flat Float32List in row-major order,
/// where T = 1 + (len(audio) + winLen - 1 - winLen) / hopLen.
class MelFeatureExtractor {
  late final Float64List _hannWindow;
  late final Float64List _melFilterbank; // [nMels × (nFft/2+1)] row-major

  MelFeatureExtractor() {
    _hannWindow = _createHannWindow(AudioConstants.winLen);
    _melFilterbank = _createMelFilterbank();
  }

  /// Create a Hann window of length n.
  ///
  /// Matches numpy.hanning: w[i] = 0.5 * (1 - cos(2π*i/(n-1)))
  /// for i = 0, 1, ..., n-1.
  Float64List _createHannWindow(int n) {
    final w = Float64List(n);
    for (int i = 0; i < n; i++) {
      w[i] = 0.5 * (1.0 - cos(2.0 * pi * i / (n - 1)));
    }
    return w;
  }

  /// Convert frequency in Hz to mel scale (HTK formula).
  ///
  /// mel = 2595 * log10(1 + hz / 700)
  double _hzToMel(double hz) {
    return 2595.0 * log(1.0 + hz / 700.0) / ln10;
  }

  /// Convert mel scale to frequency in Hz (inverse HTK formula).
  ///
  /// hz = 700 * (10^(mel/2595) - 1)
  double _melToHz(double mel) {
    return 700.0 * (pow(10.0, mel / 2595.0) - 1.0);
  }

  /// Create HTK-style mel filterbank: [nMels × (nFft/2+1)].
  ///
  /// Matches the Python reference:
  ///   mel_pts = linspace(0, hzToMel(melMaxFreq), nMels + 2)
  ///   hz_pts  = melToHz(mel_pts)
  ///   bins    = floor((nFft + 1) * hz_pts / sampleRate)
  ///
  /// Then triangular filters are constructed between adjacent mel points.
  Float64List _createMelFilterbank() {
    final nFft = AudioConstants.nFft;
    final nMels = AudioConstants.nMels;
    final sr = AudioConstants.sampleRate;
    final nBins = nFft ~/ 2 + 1; // 257

    // Mel points: linearly spaced in mel scale
    final melPts = List<double>.filled(nMels + 2, 0.0);
    final melMax = _hzToMel(AudioConstants.melMaxFreq);
    final melMin = _hzToMel(AudioConstants.melMinFreq);
    for (int i = 0; i < nMels + 2; i++) {
      melPts[i] = melMin + (melMax - melMin) * i / (nMels + 1);
    }

    // Convert to Hz
    final hzPts = List<double>.filled(nMels + 2, 0.0);
    for (int i = 0; i < nMels + 2; i++) {
      hzPts[i] = _melToHz(melPts[i]);
    }

    // Convert to FFT bin indices
    final bins = List<int>.filled(nMels + 2, 0);
    for (int i = 0; i < nMels + 2; i++) {
      bins[i] = ((nFft + 1) * hzPts[i] / sr).floor();
    }

    // Build triangular filterbank [nMels × nBins]
    final fb = Float64List(nMels * nBins);
    for (int m = 1; m <= nMels; m++) {
      final left = bins[m - 1];
      final center = bins[m];
      final right = bins[m + 1];
      final rowOffset = (m - 1) * nBins;

      // Rising slope
      if (center > left) {
        for (int k = left; k < center; k++) {
          fb[rowOffset + k] = (k - left) / (center - left);
        }
      }
      // Falling slope
      if (right > center) {
        for (int k = center; k < right; k++) {
          fb[rowOffset + k] = (right - k) / (right - center);
        }
      }
    }

    return fb;
  }

  /// Extract log-mel features from raw audio samples.
  ///
  /// [audio] — Float32List of mono audio samples at 16kHz.
  /// Returns (features, numFrames) where features is a Float32List
  /// of shape [nMels × numFrames] in row-major order (mel bin rows,
  /// time frame columns), normalized with per-feature CMVN.
  (Float32List, int) extract(Float32List audio) {
    final winLen = AudioConstants.winLen;
    final hopLen = AudioConstants.hopLen;
    final nFft = AudioConstants.nFft;
    final nMels = AudioConstants.nMels;
    final nBins = nFft ~/ 2 + 1; // 257

    // Pad audio by (winLen - 1) samples
    final paddedLen = audio.length + winLen - 1;
    final padded = Float64List(paddedLen);
    for (int i = 0; i < audio.length; i++) {
      padded[i] = audio[i].toDouble();
    }
    // Remaining samples are 0.0 (zero padding)

    // Number of frames
    final numFrames = 1 + (paddedLen - winLen) ~/ hopLen;
    if (numFrames <= 0) {
      return (Float32List(0), 0);
    }

    // Compute STFT: for each frame, apply Hann window then FFT
    // Store power spectrum: |STFT|² for each frame
    // powerSpectrum: [nBins × numFrames] row-major
    final powerSpectrum = Float64List(nBins * numFrames);

    // Reusable FFT buffers
    final fftReal = Float64List(nFft);
    final fftImag = Float64List(nFft);

    for (int t = 0; t < numFrames; t++) {
      final start = t * hopLen;

      // Apply Hann window
      for (int i = 0; i < winLen; i++) {
        fftReal[i] = padded[start + i] * _hannWindow[i];
      }
      // Zero-pad the rest (winLen to nFft)
      for (int i = winLen; i < nFft; i++) {
        fftReal[i] = 0.0;
      }
      // Imag part starts at zero
      for (int i = 0; i < nFft; i++) {
        fftImag[i] = 0.0;
      }

      // In-place FFT
      _fft(fftReal, fftImag);

      // Power spectrum = real² + imag² (only first nBins = nFft/2+1)
      final frameOffset = t; // column in powerSpectrum
      for (int k = 0; k < nBins; k++) {
        final re = fftReal[k];
        final im = fftImag[k];
        powerSpectrum[k * numFrames + frameOffset] = re * re + im * im;
      }
    }

    // Apply mel filterbank: mel = filterbank × power
    // melOutput: [nMels × numFrames] row-major
    final melOutput = Float64List(nMels * numFrames);
    for (int m = 0; m < nMels; m++) {
      final fbRowOffset = m * nBins;
      final melRowOffset = m * numFrames;
      for (int t = 0; t < numFrames; t++) {
        double sum = 0.0;
        for (int k = 0; k < nBins; k++) {
          sum += _melFilterbank[fbRowOffset + k] * powerSpectrum[k * numFrames + t];
        }
        // Log-mel: log(power + logOffset)
        melOutput[melRowOffset + t] = log(sum + AudioConstants.logOffset);
      }
    }

    // Per-feature CMVN: for each mel bin, compute mean and std over
    // all frames, then normalize: (x - mean) / (std + eps)
    // This matches normalize='per_feature' in NeMo config.
    final features = Float32List(nMels * numFrames);
    for (int m = 0; m < nMels; m++) {
      final rowOffset = m * numFrames;

      // Compute mean
      double mean = 0.0;
      for (int t = 0; t < numFrames; t++) {
        mean += melOutput[rowOffset + t];
      }
      mean /= numFrames;

      // Compute std
      double variance = 0.0;
      for (int t = 0; t < numFrames; t++) {
        final diff = melOutput[rowOffset + t] - mean;
        variance += diff * diff;
      }
      final std = sqrt(variance / numFrames);

      // Normalize
      final denom = std + AudioConstants.cmvnEps;
      for (int t = 0; t < numFrames; t++) {
        features[rowOffset + t] = ((melOutput[rowOffset + t] - mean) / denom);
      }
    }

    return (features, numFrames);
  }

  /// In-place Cooley-Tukey radix-2 FFT.
  ///
  /// [real] and [imag] must have the same length, which must be a
  /// power of 2. After the call, they contain the FFT of the input.
  void _fft(Float64List real, Float64List imag) {
    final n = real.length;
    assert(n > 0 && (n & (n - 1)) == 0, 'FFT length must be power of 2');

    // Bit-reversal permutation
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        // Swap real
        final tr = real[i];
        real[i] = real[j];
        real[j] = tr;
        // Swap imag
        final ti = imag[i];
        imag[i] = imag[j];
        imag[j] = ti;
      }
    }

    // Cooley-Tukey butterfly
    for (int len = 2; len <= n; len <<= 1) {
      final halfLen = len >> 1;
      final angle = -2.0 * pi / len;
      final wReal = cos(angle);
      final wImag = sin(angle);

      for (int i = 0; i < n; i += len) {
        double curWReal = 1.0;
        double curWImag = 0.0;
        for (int k = 0; k < halfLen; k++) {
          final idxEven = i + k;
          final idxOdd = i + k + halfLen;

          final evenReal = real[idxEven];
          final evenImag = imag[idxEven];
          final oddReal = real[idxOdd];
          final oddImag = imag[idxOdd];

          // t = w * odd
          final tReal = curWReal * oddReal - curWImag * oddImag;
          final tImag = curWReal * oddImag + curWImag * oddReal;

          // butterfly
          real[idxEven] = evenReal + tReal;
          imag[idxEven] = evenImag + tImag;
          real[idxOdd] = evenReal - tReal;
          imag[idxOdd] = evenImag - tImag;

          // Update twiddle factor: curW *= w
          final newWReal = curWReal * wReal - curWImag * wImag;
          final newWImag = curWReal * wImag + curWImag * wReal;
          curWReal = newWReal;
          curWImag = newWImag;
        }
      }
    }
  }
}
