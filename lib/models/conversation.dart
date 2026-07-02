class Conversation {
  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<Message>? messages;

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    this.updatedAt,
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
      messages: json['messages'] != null
          ? (json['messages'] as List).map((m) => Message.fromJson(m)).toList()
          : null,
    );
  }
}

class Message {
  final String role;
  final String content;
  final String? model;
  final String? platform;
  final bool isStreaming;

  Message({
    required this.role,
    required this.content,
    this.model,
    this.platform,
    this.isStreaming = false,
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
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      model: model ?? this.model,
      platform: platform ?? this.platform,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
