// A project groups conversations and holds shared standing instructions (A.7).
class Project {
  final int id;
  final String name;
  final String? instructions;
  final int conversationCount;

  Project({
    required this.id,
    required this.name,
    this.instructions,
    this.conversationCount = 0,
  });

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        instructions: j['instructions'] as String?,
        conversationCount: (j['conversation_count'] ?? 0) as int,
      );
}
