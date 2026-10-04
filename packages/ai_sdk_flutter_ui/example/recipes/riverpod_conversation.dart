import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';

/// Inject this provider at the application boundary. The transport is owned
/// by the provider and disposed when the provider scope is torn down.
final conversationBackendProvider = Provider.autoDispose
    .family<ConversationBackend, ConversationBackend>((ref, backend) {
      ref.onDispose(backend.dispose);
      return backend;
    });

final conversationControllerProvider = Provider.autoDispose
    .family<ConversationController, ConversationBackend>((ref, backend) {
      final controller = ConversationController(
        ref.watch(conversationBackendProvider(backend)),
        disposeBackend: false,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Reactive snapshots for `ref.watch`. This provider rebuilds when the backend
/// emits a snapshot and cancels its subscription with the Riverpod scope.
final conversationSnapshotProvider = StreamProvider.autoDispose
    .family<Conversation, ConversationBackend>((ref, backend) async* {
      final owned = ref.watch(conversationBackendProvider(backend));
      yield owned.conversation;
      yield* owned.changes;
    });

/// Observation-only variant for a backend owned by another scope.
final conversationInjectedSnapshotProvider = StreamProvider.autoDispose
    .family<Conversation, ConversationBackend>((ref, backend) async* {
      yield backend.conversation;
      yield* backend.changes;
    });

/// Usage inside a [ConsumerWidget]:
/// `ref.watch(conversationSnapshotProvider(backend)).value` for an owned
/// backend, or `conversationInjectedSnapshotProvider` when the caller owns it.
