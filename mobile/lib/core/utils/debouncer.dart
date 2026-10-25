import 'dart:async';

/// Debounces rapid triggers (search-as-you-type) so we don't spam the API.
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 350)});

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Cancels any pending execution (call from dispose()).
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  bool get isPending => _timer?.isActive ?? false;

  void dispose() => cancel();
}
