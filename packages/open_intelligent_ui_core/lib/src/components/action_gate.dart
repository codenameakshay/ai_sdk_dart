import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/widgets.dart';

import '../localizations.dart';
import '../view.dart';
import 'controls.dart';

typedef _ConfirmationIdentity = ({
  String nodeId,
  String actionKey,
  String confirm,
});

/// Builds a control. [onTap] is null while the control is disabled.
typedef ActionGateBuilder =
    Widget Function(
      BuildContext context,
      ActionStatus? status,
      void Function(BuildContext context)? onTap,
    );

/// Wires a tappable control to its action's status. A handled action (one
/// with a handler) asks first when it has a `confirm`, shows its failure
/// (or, while the host checks a write cut off by a restore, "Checking…")
/// below the control, and takes no tap while pending, unknown, or after
/// success with `disableAfterSuccess`. Any other action runs as before, with no wrapper.
class ActionGate extends StatefulWidget {
  const ActionGate({
    super.key,
    required this.node,
    required this.prop,
    required this.enabled,
    required this.label,
    this.sendLabel = false,
    required this.builder,
  });

  final OpenUiNode node;

  /// The prop that holds the action.
  final String prop;

  /// False while the control is disabled for another reason, such as streaming.
  final bool enabled;

  /// The label sent with a plain action, read from the tap's context.
  final String Function(BuildContext context) label;

  /// Whether a plain action sends its label to the assistant.
  final bool sendLabel;

  final ActionGateBuilder builder;

  @override
  State<ActionGate> createState() => _ActionGateState();
}

class _ActionGateState extends State<ActionGate> {
  _ConfirmationIdentity? _askingFor;

  _ConfirmationIdentity? _confirmationIdentity(ActionStatus? status) {
    if (status?.confirm == null) return null;
    return (
      nodeId: widget.node.id,
      actionKey: status!.idempotencyKey,
      confirm: status.confirm!,
    );
  }

  void _tap(BuildContext context, ActionStatus? status) {
    if (status?.confirm != null) {
      setState(() => _askingFor = _confirmationIdentity(status));
    } else {
      widget.node.run(
        widget.prop,
        label: widget.label(context),
        sendLabel: widget.sendLabel,
      );
    }
  }

  void _confirm(_ConfirmationIdentity identity) {
    final status = widget.node.actionStatus(widget.prop);
    if (!widget.enabled ||
        status == null ||
        status.disabled ||
        _confirmationIdentity(status) != identity) {
      setState(() => _askingFor = null);
      return;
    }
    setState(() => _askingFor = null);
    widget.node.run(widget.prop, confirmed: true);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.node.actionStatus(widget.prop);
    final identity = _confirmationIdentity(status);
    if (_askingFor != null && _askingFor != identity) _askingFor = null;
    if (status == null) {
      return widget.builder(
        context,
        null,
        widget.enabled ? (ctx) => _tap(ctx, null) : null,
      );
    }
    final disabled = !widget.enabled || status.disabled;
    final control = widget.builder(
      context,
      status,
      disabled ? null : (ctx) => _tap(ctx, status),
    );
    final confirm = status.confirm;
    final asking = _askingFor == identity && identity != null;
    final failed = status.phase == ActionPhase.failed;
    final checking = status.phase == ActionPhase.unknown;
    if (!asking && !failed && !checking) return control;
    final theme = widget.node.theme;
    final text = OpenUiLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        control,
        if (asking)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.inner),
            child: Wrap(
              spacing: theme.spacing.inner,
              runSpacing: theme.spacing.inner,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  confirm!,
                  style: TextStyle(
                    fontFamily: theme.fontFamily,
                    fontSize: theme.typography.size(14),
                    height: 1.4,
                    color: theme.ink,
                  ),
                ),
                IuiButton(
                  label: text.confirm,
                  size: 'sm',
                  onTap: () => _confirm(identity),
                ),
                IuiButton(
                  label: text.cancel,
                  size: 'sm',
                  variant: 'outline',
                  onTap: () => setState(() => _askingFor = null),
                ),
              ],
            ),
          ),
        if (failed || checking)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.tight),
            child: Semantics(
              liveRegion: true,
              child: Text(
                checking
                    ? text.checkingAction
                    : status.message == null || status.message!.isEmpty
                    ? text.actionFailed
                    : status.message!,
                style: TextStyle(
                  fontFamily: theme.fontFamily,
                  fontSize: theme.typography.size(13),
                  height: 1.4,
                  color: checking
                      ? theme.muted
                      : theme.status['danger'] ?? theme.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
