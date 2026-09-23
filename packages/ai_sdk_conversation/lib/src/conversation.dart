import 'dart:convert';
import 'dart:typed_data';

const int conversationSchemaVersion = 1;

enum ConversationRole { system, user, assistant, tool }

enum ConversationMessageStatus {
  pending,
  streaming,
  complete,
  interrupted,
  failed,
  pendingApproval,
}

enum ApprovalStatus { pending, approved, rejected }

class ConversationSchemaException implements Exception {
  const ConversationSchemaException(this.message);
  final String message;
  @override
  String toString() => 'ConversationSchemaException: $message';
}

class ConversationValidationException implements Exception {
  const ConversationValidationException(this.message);
  final String message;
  @override
  String toString() => 'ConversationValidationException: $message';
}

class Conversation {
  Conversation({
    required this.id,
    required List<ConversationMessage> messages,
    Map<String, dynamic> metadata = const {},
    this.schemaVersion = conversationSchemaVersion,
    Map<String, dynamic> extra = const {},
  }) : messages = List.unmodifiable(messages),
       metadata = _freezeMap(metadata),
       extra = _freezeMap(extra) {
    _validate(this);
  }

  final int schemaVersion;
  final String id;
  final List<ConversationMessage> messages;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> extra;

  static void _validate(Conversation value) {
    _requireId(value.id, 'conversation');
    if (value.schemaVersion != conversationSchemaVersion) {
      throw ConversationSchemaException(
        'Unsupported conversation schema version ${value.schemaVersion}',
      );
    }
    final ids = <String>{};
    final callIds = <String>{};
    for (final message in value.messages) {
      if (!ids.add(message.id)) {
        throw ConversationValidationException(
          'Duplicate message or part id "${message.id}"',
        );
      }
      for (final part in message.parts) {
        if (!ids.add(part.id)) {
          throw ConversationValidationException(
            'Duplicate message or part id "${part.id}"',
          );
        }
        if (part case final ToolCallPart call) {
          if (!callIds.add(call.callId)) {
            throw ConversationValidationException(
              'Duplicate tool call id "${call.callId}"',
            );
          }
        }
      }
      if (message.status == ConversationMessageStatus.pendingApproval &&
          !message.parts.any(
            (part) =>
                part is ApprovalPart && part.status == ApprovalStatus.pending,
          )) {
        throw const ConversationValidationException(
          'pendingApproval messages require a pending approval part',
        );
      }
    }
    for (final message in value.messages) {
      for (final part in message.parts) {
        if (part case final ToolResultPart result) {
          if (!callIds.contains(result.callId)) {
            throw ConversationValidationException(
              'Tool result references unknown call id "${result.callId}"',
            );
          }
        }
        if (part case final ApprovalPart approval) {
          if (!callIds.contains(approval.callId)) {
            throw ConversationValidationException(
              'Approval references unknown call id "${approval.callId}"',
            );
          }
        }
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Conversation &&
      schemaVersion == other.schemaVersion &&
      id == other.id &&
      _deepEqual(messages, other.messages) &&
      _deepEqual(metadata, other.metadata) &&
      _deepEqual(extra, other.extra);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    _deepHash(messages),
    _deepHash(metadata),
    _deepHash(extra),
  );
}

class ConversationMessage {
  ConversationMessage({
    required this.id,
    required this.role,
    this.status = ConversationMessageStatus.complete,
    required List<ConversationPart> parts,
    Map<String, dynamic> metadata = const {},
    Map<String, dynamic> extra = const {},
  }) : parts = List.unmodifiable(parts),
       metadata = _freezeMap(metadata),
       extra = _freezeMap(extra) {
    _requireId(id, 'message');
  }

  final String id;
  final ConversationRole role;
  final ConversationMessageStatus status;
  final List<ConversationPart> parts;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> extra;

  @override
  bool operator ==(Object other) =>
      other is ConversationMessage &&
      id == other.id &&
      role == other.role &&
      status == other.status &&
      _deepEqual(parts, other.parts) &&
      _deepEqual(metadata, other.metadata) &&
      _deepEqual(extra, other.extra);

  @override
  int get hashCode => Object.hash(
    id,
    role,
    status,
    _deepHash(parts),
    _deepHash(metadata),
    _deepHash(extra),
  );
}

abstract class ConversationPart {
  ConversationPart({
    required String id,
    required this.type,
    Map<String, dynamic> extra = const {},
  }) : id = _validatedId(id, 'part'),
       extra = _freezeMap(extra);
  final String id;
  final String type;
  final Map<String, dynamic> extra;
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) =>
      other is ConversationPart &&
      runtimeType == other.runtimeType &&
      _deepEqual(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(runtimeType, _deepHash(toJson()));
}

class TextPart extends ConversationPart {
  TextPart({
    required super.id,
    required this.text,
    Map<String, dynamic> metadata = const {},
    super.extra,
  }) : metadata = _freezeMap(metadata),
       super(type: 'text');
  final String text;
  final Map<String, dynamic> metadata;
  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'text': text,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

class ReasoningPart extends ConversationPart {
  ReasoningPart({
    required super.id,
    required this.text,
    this.signature,
    Map<String, dynamic> metadata = const {},
    super.extra,
  }) : metadata = _freezeMap(metadata),
       super(type: 'reasoning');
  final String text;
  final String? signature;
  final Map<String, dynamic> metadata;
  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'text': text,
    if (signature != null) 'signature': signature,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// A file emitted by the model's reasoning trace.
class ReasoningFilePart extends ConversationPart {
  ReasoningFilePart({
    required super.id,
    this.uri,
    required this.mimeType,
    this.name,
    this.data,
    Map<String, dynamic> providerOptions = const {},
    super.extra,
  }) : providerOptions = _freezeMap(providerOptions),
       super(type: 'reasoning_file') {
    if (uri != null && data != null) {
      throw const ConversationValidationException(
        'Reasoning file parts cannot contain both a URI and typed data',
      );
    }
    if (uri == null && data == null) {
      throw const ConversationValidationException(
        'Reasoning file parts require a URI or typed data',
      );
    }
  }

  final String? uri;
  final String mimeType;
  final String? name;
  final ConversationFileData? data;
  final Map<String, dynamic> providerOptions;

  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    if (uri != null) 'uri': uri,
    'mimeType': mimeType,
    if (name != null) 'name': name,
    if (data case final ConversationFileBytes bytes)
      'data': {'kind': 'bytes', 'base64': base64Encode(bytes.bytes)},
    if (data case final ConversationFileProviderReference reference)
      'data': {
        'kind': 'provider_reference',
        'namespace': reference.namespace,
        'id': reference.id,
      },
    if (providerOptions.isNotEmpty) 'providerOptions': providerOptions,
  };
}

sealed class ConversationFileData {
  const ConversationFileData();
}

class ConversationFileBytes extends ConversationFileData {
  ConversationFileBytes(Uint8List bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
}

class ConversationFileProviderReference extends ConversationFileData {
  ConversationFileProviderReference({
    required this.namespace,
    required this.id,
  }) {
    if (namespace.isEmpty || id.isEmpty) {
      throw const ConversationValidationException(
        'Provider file data requires a non-empty namespace and id',
      );
    }
  }
  final String namespace;
  final String id;
}

class FilePart extends ConversationPart {
  FilePart({
    required super.id,
    this.uri,
    required this.mimeType,
    this.name,
    this.data,
    Map<String, dynamic> metadata = const {},
    super.extra,
  }) : metadata = _freezeMap(metadata),
       super(type: 'file') {
    if (uri != null && data != null) {
      throw const ConversationValidationException(
        'File parts cannot contain both a URI and typed data',
      );
    }
    if (uri == null && data == null) {
      throw const ConversationValidationException(
        'File parts require a URI or typed data',
      );
    }
  }
  final String? uri;
  final String mimeType;
  final String? name;
  final ConversationFileData? data;
  final Map<String, dynamic> metadata;
  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    if (uri != null) 'uri': uri,
    'mimeType': mimeType,
    if (name != null) 'name': name,
    if (data case final ConversationFileBytes bytes)
      'data': {'kind': 'bytes', 'base64': base64Encode(bytes.bytes)},
    if (data case final ConversationFileProviderReference reference)
      'data': {
        'kind': 'provider_reference',
        'namespace': reference.namespace,
        'id': reference.id,
      },
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

class SourcePart extends ConversationPart {
  SourcePart({
    required super.id,
    required this.uri,
    this.title,
    Map<String, dynamic> metadata = const {},
    Map<String, dynamic> providerMetadata = const {},
    super.extra,
  }) : metadata = _freezeMap(metadata),
       providerMetadata = _freezeMap(providerMetadata),
       super(type: 'source');
  final String uri;
  final String? title;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> providerMetadata;
  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'uri': uri,
    if (title != null) 'title': title,
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (providerMetadata.isNotEmpty) 'providerMetadata': providerMetadata,
  };
}

/// A document citation that has no URL and carries its media identity.
class DocumentSourcePart extends ConversationPart {
  DocumentSourcePart({
    required super.id,
    required this.mediaType,
    required this.title,
    this.name,
    Map<String, dynamic> providerMetadata = const {},
    super.extra,
  }) : providerMetadata = _freezeMap(providerMetadata),
       super(type: 'source-document');

  final String mediaType;
  final String title;
  final String? name;
  final Map<String, dynamic> providerMetadata;

  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'mediaType': mediaType,
    'title': title,
    if (name != null) 'name': name,
    if (providerMetadata.isNotEmpty) 'providerMetadata': providerMetadata,
  };
}

class ToolCallPart extends ConversationPart {
  ToolCallPart({
    required super.id,
    required this.callId,
    required this.name,
    required Map<String, dynamic> arguments,
    Map<String, dynamic> metadata = const {},
    Map<String, dynamic> providerOptions = const {},
    this.providerExecuted = false,
    super.extra,
  }) : arguments = _freezeMap(arguments),
       metadata = _freezeMap(metadata),
       providerOptions = _freezeMap(providerOptions),
       super(type: 'tool_call');
  final String callId;
  final String name;
  final Map<String, dynamic> arguments;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> providerOptions;
  final bool providerExecuted;
  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'callId': callId,
    'name': name,
    'arguments': arguments,
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (providerOptions.isNotEmpty) 'providerOptions': providerOptions,
    if (providerExecuted) 'providerExecuted': true,
  };
}

class ToolResultPart extends ConversationPart {
  ToolResultPart({
    required super.id,
    required this.callId,
    required Object? output,
    this.isError = false,
    this.toolName,
    this.outputKind,
    this.preliminary = false,
    this.isDynamic = false,
    this.executionDeniedReason,
    this.executionDeniedApprovalId,
    Map<String, dynamic> metadata = const {},
    Map<String, dynamic> providerOptions = const {},
    super.extra,
  }) : output = _freezeJson(output),
       metadata = _freezeMap(metadata),
       providerOptions = _freezeMap(providerOptions),
       super(type: 'tool_result');
  final String callId;
  final Object? output;
  final bool isError;
  final String? toolName;

  /// One of text, content, json, error_json, error_text, execution_denied.
  final String? outputKind;
  final bool preliminary;
  final bool isDynamic;
  final String? executionDeniedReason;
  final String? executionDeniedApprovalId;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> providerOptions;
  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'callId': callId,
    'output': output,
    'isError': isError,
    if (toolName != null) 'toolName': toolName,
    if (outputKind != null) 'outputKind': outputKind,
    if (preliminary) 'preliminary': true,
    if (isDynamic) 'isDynamic': true,
    if (executionDeniedReason != null)
      'executionDeniedReason': executionDeniedReason,
    if (executionDeniedApprovalId != null)
      'executionDeniedApprovalId': executionDeniedApprovalId,
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (providerOptions.isNotEmpty) 'providerOptions': providerOptions,
  };
}

class ApprovalPart extends ConversationPart {
  ApprovalPart({
    required super.id,
    required this.callId,
    required this.status,
    this.approvalId,
    this.toolName,
    this.argumentsFingerprint,
    this.policyVersion,
    Map<String, dynamic> metadata = const {},
    super.extra,
  }) : metadata = _freezeMap(metadata),
       super(type: 'approval');
  final String callId;
  final ApprovalStatus status;
  final String? approvalId;
  final String? toolName;
  final String? argumentsFingerprint;
  final String? policyVersion;
  final Map<String, dynamic> metadata;
  @override
  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'callId': callId,
    'status': status.name,
    if (approvalId != null) 'approvalId': approvalId,
    if (toolName != null) 'toolName': toolName,
    if (argumentsFingerprint != null)
      'argumentsFingerprint': argumentsFingerprint,
    if (policyVersion != null) 'policyVersion': policyVersion,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

class UnknownPart extends ConversationPart {
  UnknownPart({
    required super.id,
    required super.type,
    required Map<String, dynamic> raw,
  }) : raw = _freezeMap(raw) {
    if (this.raw['id'] != id || this.raw['type'] != type) {
      throw ConversationValidationException(
        'Unknown part raw id/type does not match its envelope',
      );
    }
  }
  final Map<String, dynamic> raw;
  @override
  Map<String, dynamic> toJson() => raw;
}

class ConversationCodec {
  static Map<String, dynamic> encode(Conversation value) => {
    ...value.extra,
    'schemaVersion': value.schemaVersion,
    'id': value.id,
    if (value.metadata.isNotEmpty) 'metadata': value.metadata,
    'messages': value.messages
        .map(
          (message) => {
            ...message.extra,
            'id': message.id,
            'role': message.role.name,
            'status': _statusToJson(message.status),
            if (message.metadata.isNotEmpty) 'metadata': message.metadata,
            'parts': message.parts.map((part) => part.toJson()).toList(),
          },
        )
        .toList(),
  };

  static Conversation decode(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version is! int || version != conversationSchemaVersion) {
      throw ConversationSchemaException(
        'Unsupported conversation schema version $version',
      );
    }
    final messages = json['messages'];
    if (json['id'] is! String || messages is! List) {
      throw const ConversationValidationException(
        'Conversation requires id and messages',
      );
    }
    return Conversation(
      schemaVersion: version,
      id: json['id'] as String,
      metadata: _optionalMap(json, 'metadata'),
      extra: _extras(json, {'schemaVersion', 'id', 'metadata', 'messages'}),
      messages: messages.map((entry) => _decodeMessage(entry)).toList(),
    );
  }

  static ConversationMessage _decodeMessage(Object? value) {
    if (value is! Map) {
      throw const ConversationValidationException('Message must be an object');
    }
    final json = _wireMap(value, 'message');
    final role = _enum(json['role'], ConversationRole.values, 'role');
    final status = _statusFromJson(json['status']);
    final parts = json['parts'];
    if (json['id'] is! String || parts is! List) {
      throw const ConversationValidationException(
        'Message requires id and parts',
      );
    }
    return ConversationMessage(
      id: json['id'] as String,
      role: role,
      status: status,
      metadata: _optionalMap(json, 'metadata'),
      extra: _extras(json, {'id', 'role', 'status', 'metadata', 'parts'}),
      parts: parts.map(_decodePart).toList(),
    );
  }

  static ConversationPart _decodePart(Object? value) {
    if (value is! Map) {
      throw const ConversationValidationException('Part must be an object');
    }
    final json = _wireMap(value, 'part');
    final id = json['id'];
    final type = json['type'];
    if (id is! String || type is! String) {
      throw const ConversationValidationException('Part requires id and type');
    }
    switch (type) {
      case 'text':
        return TextPart(
          id: id,
          text: _text(json, 'text'),
          metadata: _optionalMap(json, 'metadata'),
          extra: _extras(json, {'id', 'type', 'text', 'metadata'}),
        );
      case 'reasoning':
        return ReasoningPart(
          id: id,
          text: _text(json, 'text'),
          signature: _optionalString(json, 'signature'),
          metadata: _optionalMap(json, 'metadata'),
          extra: _extras(json, {'id', 'type', 'text', 'signature', 'metadata'}),
        );
      case 'file':
        return FilePart(
          id: id,
          uri: _optionalString(json, 'uri'),
          mimeType: _string(json, 'mimeType'),
          name: _optionalString(json, 'name'),
          data: _decodeFileData(json['data'], 'File'),
          metadata: _optionalMap(json, 'metadata'),
          extra: _extras(json, {
            'id',
            'type',
            'uri',
            'mimeType',
            'name',
            'data',
            'metadata',
          }),
        );
      case 'reasoning_file':
        return ReasoningFilePart(
          id: id,
          uri: _optionalString(json, 'uri'),
          mimeType: _string(json, 'mimeType'),
          name: _optionalString(json, 'name'),
          data: _decodeFileData(json['data'], 'Reasoning file'),
          providerOptions: _optionalMap(json, 'providerOptions'),
          extra: _extras(json, {
            'id',
            'type',
            'uri',
            'mimeType',
            'name',
            'data',
            'providerOptions',
          }),
        );
      case 'source':
        return SourcePart(
          id: id,
          uri: _string(json, 'uri'),
          title: _optionalString(json, 'title'),
          metadata: _optionalMap(json, 'metadata'),
          providerMetadata: _optionalMap(json, 'providerMetadata'),
          extra: _extras(json, {
            'id',
            'type',
            'uri',
            'title',
            'metadata',
            'providerMetadata',
          }),
        );
      case 'source-document':
        return DocumentSourcePart(
          id: id,
          mediaType: _string(json, 'mediaType'),
          title: _string(json, 'title'),
          name: _optionalString(json, 'name'),
          providerMetadata: _optionalMap(json, 'providerMetadata'),
          extra: _extras(json, {
            'id',
            'type',
            'mediaType',
            'title',
            'name',
            'providerMetadata',
          }),
        );
      case 'tool_call':
        return ToolCallPart(
          id: id,
          callId: _string(json, 'callId'),
          name: _string(json, 'name'),
          arguments: _requiredMap(json, 'arguments'),
          metadata: _optionalMap(json, 'metadata'),
          providerOptions: _optionalMap(json, 'providerOptions'),
          providerExecuted: json['providerExecuted'] == true,
          extra: _extras(json, {
            'id',
            'type',
            'callId',
            'name',
            'arguments',
            'metadata',
            'providerOptions',
            'providerExecuted',
          }),
        );
      case 'tool_result':
        if (!json.containsKey('output')) {
          throw const ConversationValidationException(
            'Tool result requires output',
          );
        }
        final isError = json['isError'];
        if (isError is! bool) {
          throw const ConversationValidationException(
            'Tool result isError must be boolean',
          );
        }
        return ToolResultPart(
          id: id,
          callId: _string(json, 'callId'),
          output: _freezeJson(json['output']),
          isError: isError,
          toolName: _optionalString(json, 'toolName'),
          outputKind: _optionalString(json, 'outputKind'),
          preliminary: json['preliminary'] == true,
          isDynamic: json['isDynamic'] == true,
          executionDeniedReason: _optionalString(json, 'executionDeniedReason'),
          executionDeniedApprovalId: _optionalString(
            json,
            'executionDeniedApprovalId',
          ),
          metadata: _optionalMap(json, 'metadata'),
          providerOptions: _optionalMap(json, 'providerOptions'),
          extra: _extras(json, {
            'id',
            'type',
            'callId',
            'output',
            'isError',
            'toolName',
            'outputKind',
            'preliminary',
            'isDynamic',
            'executionDeniedReason',
            'executionDeniedApprovalId',
            'metadata',
            'providerOptions',
          }),
        );
      case 'approval':
        return ApprovalPart(
          id: id,
          callId: _string(json, 'callId'),
          status: _enum(
            json['status'],
            ApprovalStatus.values,
            'approval status',
          ),
          approvalId: _optionalString(json, 'approvalId'),
          toolName: _optionalString(json, 'toolName'),
          argumentsFingerprint: _optionalString(json, 'argumentsFingerprint'),
          policyVersion: _optionalString(json, 'policyVersion'),
          metadata: _optionalMap(json, 'metadata'),
          extra: _extras(json, {
            'id',
            'type',
            'callId',
            'status',
            'approvalId',
            'toolName',
            'argumentsFingerprint',
            'policyVersion',
            'metadata',
          }),
        );
      default:
        return UnknownPart(id: id, type: type, raw: json);
    }
  }
}

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw ConversationValidationException('Expected string "$key"');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw ConversationValidationException('Expected non-empty string "$key"');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw ConversationValidationException('Expected string "$key"');
  }
  return value;
}

ConversationFileData? _decodeFileData(Object? wireData, String label) {
  if (wireData == null) return null;
  if (wireData is! Map || wireData['kind'] is! String) {
    throw ConversationValidationException('$label data must be a typed object');
  }
  switch (wireData['kind']) {
    case 'bytes':
      if (wireData['base64'] is! String) {
        throw ConversationValidationException(
          '$label byte data requires base64',
        );
      }
      try {
        return ConversationFileBytes(
          Uint8List.fromList(base64Decode(wireData['base64'] as String)),
        );
      } on FormatException {
        throw ConversationValidationException(
          '$label byte data has invalid base64',
        );
      }
    case 'provider_reference':
      if (wireData['namespace'] is! String || wireData['id'] is! String) {
        throw ConversationValidationException(
          '$label provider data requires namespace and id',
        );
      }
      return ConversationFileProviderReference(
        namespace: wireData['namespace'] as String,
        id: wireData['id'] as String,
      );
    default:
      throw ConversationValidationException(
        'Unsupported $label data kind ${wireData['kind']}',
      );
  }
}

T _enum<T extends Enum>(Object? value, List<T> values, String field) {
  if (value is! String) throw ConversationValidationException('Invalid $field');
  return values.firstWhere(
    (item) => item.name == value,
    orElse: () =>
        throw ConversationValidationException('Invalid $field "$value"'),
  );
}

String _statusToJson(ConversationMessageStatus status) =>
    status == ConversationMessageStatus.pendingApproval
    ? 'pending_approval'
    : status.name;

ConversationMessageStatus _statusFromJson(Object? value) {
  if (value == 'pending_approval') {
    return ConversationMessageStatus.pendingApproval;
  }
  return _enum(value, ConversationMessageStatus.values, 'message status');
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw ConversationValidationException('Expected object "$key"');
  }
  return _freezeMap(_wireMap(value, key));
}

Map<String, dynamic> _optionalMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return const {};
  if (value is! Map) {
    throw ConversationValidationException('Expected object "$key"');
  }
  return _freezeMap(_wireMap(value, key));
}

Map<String, dynamic> _wireMap(Map value, String kind) {
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw ConversationValidationException(
        '$kind object keys must be strings',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, dynamic> _extras(Map<String, dynamic> json, Set<String> known) {
  final result = <String, dynamic>{};
  for (final entry in json.entries) {
    if (!known.contains(entry.key)) result[entry.key] = entry.value;
  }
  return _freezeMap(result);
}

const _maxJsonDepth = 64;
const _maxJsonNodes = 10000;

class _JsonFreezeState {
  final active = Set<Object>.identity();
  int nodes = 0;
}

Object? _freezeJson(Object? value, [_JsonFreezeState? state, int depth = 0]) {
  final context = state ?? _JsonFreezeState();
  if (depth > _maxJsonDepth) {
    throw const ConversationValidationException(
      'JSON value is too deeply nested',
    );
  }
  context.nodes++;
  if (context.nodes > _maxJsonNodes) {
    throw const ConversationValidationException(
      'JSON value contains too many nodes',
    );
  }
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) {
      throw const ConversationValidationException(
        'JSON numbers must be finite',
      );
    }
    return value;
  }
  if (value is List) {
    if (!context.active.add(value)) {
      throw const ConversationValidationException('Cyclic JSON value');
    }
    final result = List<Object?>.unmodifiable(
      value.map((item) => _freezeJson(item, context, depth + 1)),
    );
    context.active.remove(value);
    return result;
  }
  if (value is Map) {
    if (!context.active.add(value)) {
      throw const ConversationValidationException('Cyclic JSON value');
    }
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const ConversationValidationException(
          'JSON object keys must be strings',
        );
      }
      result[entry.key as String] = _freezeJson(
        entry.value,
        context,
        depth + 1,
      );
    }
    context.active.remove(value);
    return Map<String, dynamic>.unmodifiable(result);
  }
  throw ConversationValidationException(
    'Unsupported JSON value ${value.runtimeType}',
  );
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
    _freezeJson(value) as Map<String, dynamic>;

void _requireId(String value, String kind) {
  if (value.trim().isEmpty) {
    throw ConversationValidationException('$kind id must not be empty');
  }
}

String _validatedId(String value, String kind) {
  _requireId(value, kind);
  return value;
}

bool _deepEqual(Object? a, Object? b) {
  if (a is List && b is List) {
    return a.length == b.length &&
        a.asMap().keys.every((i) => _deepEqual(a[i], b[i]));
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _deepEqual(a[key], b[key]));
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is Map) {
    final entries =
        value.keys
            .map((key) => MapEntry(key.toString(), _deepHash(value[key])))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }
  if (value is List) return Object.hashAll(value.map(_deepHash));
  return value.hashCode;
}
