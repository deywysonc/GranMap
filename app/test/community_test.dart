import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/community/community_models.dart';

void main() {
  test('Confiança comunitária é calculada corretamente', () {
    const proposal = RoomChangeContribution(
      id: '1',
      subject: 'Teste',
      authorName: 'Aluno',
      fromRoomName: 'Sala A',
      toRoomName: 'Sala B',
      reason: 'Teste',
      status: ContributionStatus.voting,
      yesVotes: 8,
      noVotes: 2,
    );

    expect(proposal.confidence, 0.8);
  });

  test('Resposta comunitária preserva governança e voto pessoal', () {
    final proposal = RoomChangeContribution.fromJson({
      'id': 42,
      'subject': 'Estrutura de Dados',
      'author_name': 'Aluno',
      'author_reputation': 3,
      'from_room': 'Alan Turing',
      'to_room': 'Henry Ford',
      'reason': 'Mudança comunicada pelo professor.',
      'status': 'confirmed',
      'yes_votes': 4,
      'no_votes': 1,
      'my_vote': true,
      'official_priority': true,
      'moderation_note': 'Conferido pela coordenação.',
    });

    expect(proposal.id, '42');
    expect(proposal.status, ContributionStatus.confirmed);
    expect(proposal.myVote, isTrue);
    expect(proposal.officialPriority, isTrue);
    expect(proposal.authorReputation, 3);
    expect(proposal.confidence, 0.8);
  });
}
