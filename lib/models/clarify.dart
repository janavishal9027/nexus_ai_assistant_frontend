// The Clarifier's structured question (chat-module A.2) — an AskUserQuestion the
// UI renders in a docked panel before the answer streams.

class ClarifyOption {
  final String label;
  final String? description;
  ClarifyOption({required this.label, this.description});

  factory ClarifyOption.fromJson(Map<String, dynamic> j) => ClarifyOption(
        label: (j['label'] ?? '').toString(),
        description: j['description']?.toString(),
      );
}

class ClarifyQuestion {
  final String header;
  final String question;
  final bool multiSelect;
  final List<ClarifyOption> options;

  ClarifyQuestion({
    required this.header,
    required this.question,
    this.multiSelect = false,
    this.options = const [],
  });

  factory ClarifyQuestion.fromJson(Map<String, dynamic> j) => ClarifyQuestion(
        header: (j['header'] ?? 'Clarify').toString(),
        question: (j['question'] ?? '').toString(),
        multiSelect: (j['multi_select'] ?? false) as bool,
        options: ((j['options'] as List?) ?? [])
            .map((e) => ClarifyOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
