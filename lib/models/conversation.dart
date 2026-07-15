import 'chat_attachment.dart';

class Conversation {
  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? parentId; // source conversation, if this is a branch
  final int? projectId; // project this chat is grouped under (A.7), or null
  final List<Message>? messages;

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    this.updatedAt,
    this.parentId,
    this.projectId,
    this.messages,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      title: json['title'] ?? 'New Chat',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      parentId: json['parent_id'],
      projectId: json['project_id'],
      messages: json['messages'] != null
          ? (json['messages'] as List).map((m) => Message.fromJson(m)).toList()
          : null,
    );
  }
}

/// A single tool invocation surfaced live during agent streaming.
class ToolActivity {
  final String name;
  bool running;
  double? durationMs;

  ToolActivity({required this.name, this.running = true, this.durationMs});
}

/// Agent-orchestration activity attached to a streaming assistant message:
/// the planner's steps and the tools it ran. Mutable so the provider can update
/// it in place as WebSocket events arrive.
class AgentActivity {
  List<String> planSteps;
  final List<ToolActivity> tools;

  AgentActivity({List<String>? planSteps, List<ToolActivity>? tools})
      : planSteps = planSteps ?? [],
        tools = tools ?? [];

  bool get isEmpty => planSteps.isEmpty && tools.isEmpty;
}

class Message {
  final String role;
  final String content;
  final String? model;
  final String? platform;
  final bool isStreaming;
  final AgentActivity? activity;
  // Files attached to this (user) turn — shown as chips/thumbnails on the
  // bubble. Not populated when reloading history from the server.
  final List<ChatAttachment>? attachments;

  Message({
    required this.role,
    required this.content,
    this.model,
    this.platform,
    this.isStreaming = false,
    this.activity,
    this.attachments,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      role: json['role'] ?? 'user',
      content: json['content']?.toString() ?? '',
      model: json['model']?.toString(),
      platform: json['platform']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
    };
  }

  Message copyWith({
    String? role,
    String? content,
    String? model,
    String? platform,
    bool? isStreaming,
    AgentActivity? activity,
    List<ChatAttachment>? attachments,
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      model: model ?? this.model,
      platform: platform ?? this.platform,
      isStreaming: isStreaming ?? this.isStreaming,
      activity: activity ?? this.activity,
      attachments: attachments ?? this.attachments,
    );
  }
}
