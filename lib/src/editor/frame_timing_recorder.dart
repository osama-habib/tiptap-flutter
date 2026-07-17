// Records the UI-thread and raster-thread durations of state-driven frames
// using the engine's FrameTiming reports.
//
// The editor arms the recorder from a post-frame callback of the frame a
// stateChanged rebuild produced. During that callback the platform
// dispatcher's frameData still identifies the frame being finalized, so its
// frame number is captured exactly; when FrameTiming reports later arrive in
// batches, each report is matched to a captured target by frame number. This
// pairing is exact — unlike the typing-latency tracker's in-order
// approximation, no ambiguity is possible, so nothing is dropped and no
// caveat applies to these samples.
//
// Timing sources: FrameTiming.buildDuration covers the frame's UI-thread
// work (widget build, layout, and paint recording), and
// FrameTiming.rasterDuration covers the raster thread's time for the same
// frame. Together with the bridge-measured decode/parse phases and the
// command round-trip, these account for the port's share of end-to-end
// typing latency; the only unmeasured remainder is frame-scheduling wait.
//
// The recorder knows nothing about the editor or controller; it reports
// through the [onSample] callback supplied at construction, mirroring the
// typing-latency tracker's shape.

import 'dart:ui';

import 'package:flutter/scheduler.dart';

/// Captures per-frame build and raster durations for explicitly targeted
/// frames and reports each matched frame through [onSample].
class FrameTimingRecorder {
  /// Called once per matched frame with the UI-thread build duration and
  /// the raster-thread duration, both in milliseconds.
  final void Function(double buildMs, double rasterMs) onSample;

  FrameTimingRecorder({required this.onSample});

  /// Frame numbers awaiting their FrameTiming report.
  final Set<int> _targetFrameNumbers = {};

  /// Whether the timings callback is currently registered with the
  /// scheduler. Registered lazily on the first capture so an editor that
  /// never receives a state update pays nothing.
  bool _listening = false;

  /// Mark the frame currently being finalized as a measurement target.
  ///
  /// Must be called from within a frame — in practice from a post-frame
  /// callback — because it reads the platform dispatcher's frameData, which
  /// identifies the frame being produced. Called outside a frame it would
  /// read a stale frame number and attribute the wrong frame's durations to
  /// the sample.
  void captureCurrentFrame() {
    _targetFrameNumbers.add(PlatformDispatcher.instance.frameData.frameNumber);

    if (!_listening) {
      _listening = true;
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    }
  }

  /// Match reported timings against captured targets and emit a sample for
  /// each hit. Targets at or below the newest reported frame number that
  /// were never matched are discarded afterward — frame numbers only
  /// increase, so an unmatched older target can never be reported later,
  /// and pruning keeps the set bounded if a report was missed.
  void _onTimings(List<FrameTiming> timings) {
    if (_targetFrameNumbers.isEmpty) return;

    var newestReported = -1;
    for (final timing in timings) {
      if (timing.frameNumber > newestReported) {
        newestReported = timing.frameNumber;
      }
      if (_targetFrameNumbers.remove(timing.frameNumber)) {
        onSample(
          timing.buildDuration.inMicroseconds / 1000.0,
          timing.rasterDuration.inMicroseconds / 1000.0,
        );
      }
    }

    _targetFrameNumbers.removeWhere((number) => number <= newestReported);
  }

  /// Unregister the timings callback and drop pending targets.
  void dispose() {
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _listening = false;
    }
    _targetFrameNumbers.clear();
  }
}
