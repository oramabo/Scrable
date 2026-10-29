import 'dart:async';

/// Runs the last scheduled action after [delay] of quiet; [flush] runs it now.
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;
  void Function()? _pending;

  void call(void Function() action) {
    _pending = action;
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  /// Runs the pending action immediately, if any.
  void flush() {
    _timer?.cancel();
    _timer = null;
    final p = _pending;
    _pending = null;
    p?.call();
  }

  bool get isPending => _pending != null;

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}
