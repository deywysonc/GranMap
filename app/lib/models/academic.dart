class StudentProfile {
  final String name;
  final String course;
  final int semester;
  final String group;

  const StudentProfile({
    required this.name,
    required this.course,
    required this.semester,
    required this.group,
  });
}

class AcademicClass {
  final int? backendId;
  final String subject;
  final String professor;
  final String roomPoiId;
  final String roomName;
  final String weekday;
  final String startTime;
  final String endTime;

  const AcademicClass({
    this.backendId,
    required this.subject,
    required this.professor,
    required this.roomPoiId,
    required this.roomName,
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  factory AcademicClass.fromApi(Map<String, dynamic> json) {
    return AcademicClass(
      backendId: json['id'] as int?,
      subject: (json['subject'] ?? '') as String,
      professor:
          (json['professor_name'] ?? 'Professor não informado') as String,
      roomPoiId: (json['room_poi_id'] ?? '') as String,
      roomName: (json['room_name'] ?? 'Sala não informada') as String,
      weekday: (json['weekday'] ?? '') as String,
      startTime: (json['start_time'] ?? '') as String,
      endTime: (json['end_time'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': backendId,
    'subject': subject,
    'professor_name': professor,
    'room_poi_id': roomPoiId,
    'room_name': roomName,
    'weekday': weekday,
    'start_time': startTime,
    'end_time': endTime,
  };
}

enum AcademicDataSource { online, cache, none }

class AcademicSnapshot {
  final List<AcademicClass> classes;
  final AcademicDataSource source;
  final DateTime? cachedAt;
  final String? message;

  const AcademicSnapshot({
    required this.classes,
    required this.source,
    this.cachedAt,
    this.message,
  });

  bool get isOnline => source == AcademicDataSource.online;
  bool get isOfflineCache => source == AcademicDataSource.cache;
}
