import '../models/academic.dart';

class AcademicService {
  const AcademicService();

  StudentProfile get developmentProfile => const StudentProfile(
    name: 'Aluno GranMap',
    course: 'Engenharia da Computação',
    semester: 4,
    group: 'EC4A',
  );

  List<AcademicClass> get developmentSchedule => const [
    AcademicClass(
      backendId: 1,
      subject: 'Estrutura de Dados',
      professor: 'Prof. Carlos',
      roomPoiId: 'alan_turing',
      roomName: 'Alan Turing (Informática)',
      weekday: 'Segunda-feira',
      startTime: '19:00',
      endTime: '20:40',
    ),
    AcademicClass(
      backendId: 2,
      subject: 'Banco de Dados',
      professor: 'Prof. Rafael',
      roomPoiId: 'lab_informatica',
      roomName: 'Laboratório de Informática',
      weekday: 'Segunda-feira',
      startTime: '20:50',
      endTime: '22:30',
    ),
  ];

  AcademicClass get nextDevelopmentClass => developmentSchedule.first;
}
