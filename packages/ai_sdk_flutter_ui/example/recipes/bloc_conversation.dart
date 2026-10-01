import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';

/// Inject a backend into the bloc. The bloc owns the subscription and closes
/// it on replacement/disposal; the caller owns the backend unless
/// [disposeBackend] is true.
class ConversationCubit extends Cubit<Conversation> {
  ConversationCubit(this.backend, {this.disposeBackend = false})
    : super(backend.conversation) {
    final epoch = _epoch;
    _subscription = backend.changes.listen((value) {
      if (!_closing && !isClosed && epoch == _epoch) emit(value);
    });
  }

  ConversationBackend backend;
  final bool disposeBackend;
  late StreamSubscription<Conversation> _subscription;
  int _epoch = 0;
  bool _closing = false;
  Future<void> _subscriptionCancel = Future<void>.value();
  Future<void>? _closeFuture;
  final _disposedBackends = <WeakReference<ConversationBackend>>[];

  Future<void> _disposeOwned(ConversationBackend value) async {
    if (!disposeBackend) {
      return;
    }
    _disposedBackends.removeWhere((entry) => entry.target == null);
    if (_disposedBackends.any((entry) => identical(entry.target, value))) {
      return;
    }
    _disposedBackends.add(WeakReference(value));
    try {
      await value.dispose();
    } catch (_) {
      // Disposal failures must not leave the cubit half-replaced.
    }
  }

  Future<void> _cancelSubscription([
    StreamSubscription<Conversation>? target,
  ]) async {
    final previous = _subscriptionCancel;
    final subscription = target ?? _subscription;
    final current = previous.then((_) => _cancelSubscriptionImpl(subscription));
    _subscriptionCancel = current;
    await current;
  }

  Future<void> _cancelSubscriptionImpl(
    StreamSubscription<Conversation> subscription,
  ) async {
    try {
      await subscription.cancel();
    } catch (_) {
      // A backend's stream cleanup must not escape replacement/close.
    }
  }

  Future<void> replaceBackend(ConversationBackend next) async {
    if (_closing || isClosed) return;
    if (identical(next, backend)) return;
    final epoch = ++_epoch;
    final oldSubscription = _subscription;
    // Invalidate callbacks synchronously; cancellation itself may wait on a
    // producer-controlled stream. The captured handle guarantees cleanup is
    // applied to the old subscription even after `_subscription` changes.
    unawaited(_cancelSubscription(oldSubscription));
    final previous = backend;
    await _disposeOwned(previous);
    if (_closing || isClosed || epoch != _epoch) {
      await _disposeOwned(next);
      return;
    }
    backend = next;
    emit(next.conversation);
    _subscription = next.changes.listen((value) {
      if (!_closing && !isClosed && epoch == _epoch) emit(value);
    });
  }

  @override
  // The actual super call is awaited in _finishClose so concurrent close()
  // callers share one cleanup future.
  // ignore: must_call_super
  Future<void> close() async {
    final inFlight = _closeFuture;
    if (inFlight != null) return inFlight;
    _closing = true;
    _epoch++;
    final closing = _finishClose();
    _closeFuture = closing;
    return closing;
  }

  Future<void> _finishClose() async {
    unawaited(_cancelSubscription(_subscription));
    await _disposeOwned(backend);
    await super.close();
  }
}
