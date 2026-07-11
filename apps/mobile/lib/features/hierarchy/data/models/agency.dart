// Story 12.4-mobile — partner agency model. Mirrors the `agencies` select
// (id, name) used by the admin /hierarchy page. Pure Dart.

class Agency {
  final String id;
  final String name;

  const Agency({required this.id, required this.name});

  factory Agency.fromJson(Map<String, dynamic> json) {
    return Agency(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
