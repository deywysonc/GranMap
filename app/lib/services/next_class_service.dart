import '../models/academic.dart';

class NextClassInfo {
  final AcademicClass academicClass;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isCurrent;

  const NextClassInfo({
    required this.academicClass,
    required this.startsAt,
    required this.endsAt,
    required this.isCurrent,
  });

  Duration timeUntil(DateTime now) => startsAt.difference(now);
}

class NextClassService {
  const NextClassService();

  NextClassInfo? findNext(List<AcademicClass> classes, {DateTime? now}) {
    if (classes.isEmpty) return null;

    final currentTime = now ?? DateTime.now();
    final candidates = <NextClassInfo>[];

    for (final item in classes) {
      final weekday = _weekdayNumber(item.weekday);
      final startParts = _timeParts(item.startTime);
      final endParts = _timeParts(item.endTime);

      if (weekday == null || startParts == null || endParts == null) {
        continue;
      }

      for (var addDays = 0; addDays <= 7; addDays++) {
        final date = DateTime(
          currentTime.year,
          currentTime.month,
          currentTime.day,
        ).add(Duration(days: addDays));

        if (date.weekday != weekday) continue;

        final startsAt = DateTime(
          date.year,
          date.month,
          date.day,
          startParts.$1,
          startParts.$2,
        );

        var endsAt = DateTime(
          date.year,
          date.month,
          date.day,
          endParts.$1,
          endParts.$2,
        );

        if (!endsAt.isAfter(startsAt)) {
          endsAt = endsAt.add(const Duration(days: 1));
        }

        final isCurrent =
            !currentTime.isBefore(startsAt) && currentTime.isBefore(endsAt);

        if (isCurrent || startsAt.isAfter(currentTime)) {
          candidates.add(
            NextClassInfo(
              academicClass: item,
              startsAt: startsAt,
              endsAt: endsAt,
              isCurrent: isCurrent,
            ),
          );
          break;
        }
      }
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      return a.startsAt.compareTo(b.startsAt);
    });

    return candidates.first;
  }

  int? _weekdayNumber(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('ç', 'c')
        .replaceAll('ê', 'e')
        .trim();

    if (normalized.startsWith('segunda')) return DateTime.monday;
    if (normalized.startsWith('terca')) return DateTime.tuesday;
    if (normalized.startsWith('quarta')) return DateTime.wednesday;
    if (normalized.startsWith('quinta')) return DateTime.thursday;
    if (normalized.startsWith('sexta')) return DateTime.friday;
    if (normalized.startsWith('sabado')) return DateTime.saturday;
    if (normalized.startsWith('domingo')) return DateTime.sunday;
    return null;
  }

  (int, int)? _timeParts(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }
}
