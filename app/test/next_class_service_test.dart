import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/academic.dart';
import 'package:granmap/services/next_class_service.dart';

void main() {
  const service = NextClassService();

  const mondayClass = AcademicClass(
    subject: 'Estrutura de Dados',
    professor: 'Prof. Carlos',
    roomPoiId: 'alan_turing',
    roomName: 'Alan Turing',
    weekday: 'Segunda-feira',
    startTime: '19:00',
    endTime: '20:40',
  );

  test('identifica uma aula em andamento', () {
    final result = service.findNext(const [
      mondayClass,
    ], now: DateTime(2026, 8, 17, 19, 30));

    expect(result, isNotNull);
    expect(result!.isCurrent, isTrue);
    expect(result.academicClass.subject, 'Estrutura de Dados');
  });

  test('encontra a próxima ocorrência semanal', () {
    final result = service.findNext(const [
      mondayClass,
    ], now: DateTime(2026, 8, 19, 20, 0));

    expect(result, isNotNull);
    expect(result!.startsAt.weekday, DateTime.monday);
    expect(result.startsAt.isAfter(DateTime(2026, 8, 19, 20, 0)), isTrue);
  });
}
