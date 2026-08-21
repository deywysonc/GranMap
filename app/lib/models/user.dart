class AppUser {
  final int id;
  final String name;
  final String email;
  final String course;
  final int semester;
  final String group;
  final String role;
  final int reputation;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.course,
    required this.semester,
    required this.group,
    required this.role,
    this.reputation = 0,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      name: (json['name'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      course: (json['course_name'] ?? '') as String,
      semester: (json['semester'] ?? 1) as int,
      group: (json['group_name'] ?? '') as String,
      role: (json['role'] ?? 'student') as String,
      reputation: (json['reputation'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'course_name': course,
    'semester': semester,
    'group_name': group,
    'role': role,
    'reputation': reputation,
  };

  AppUser copyWith({
    String? name,
    String? course,
    int? semester,
    String? group,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email,
      course: course ?? this.course,
      semester: semester ?? this.semester,
      group: group ?? this.group,
      role: role,
      reputation: reputation,
    );
  }
}

class AuthResult {
  final String token;
  final AppUser user;

  const AuthResult({required this.token, required this.user});

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      token: json['token'] as String,
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
