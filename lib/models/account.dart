class Account {
  final int id;
  final String email;
  final String? name;

  Account({required this.id, required this.email, this.name});

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as int,
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString(),
    );
  }

  /// Best-effort display label: name if present, otherwise the email local part.
  String get displayName {
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }
}
