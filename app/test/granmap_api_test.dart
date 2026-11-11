import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:granmap/services/granmap_api.dart';

void main() {
  test('voto preserva revisão e chave em uma nova tentativa', () async {
    var calls = 0;
    final api = GranMapApi(
      baseUrl: 'https://api.granmap.test',
      client: MockClient((request) async {
        calls++;
        expect(jsonDecode(request.body)['intent_version'], 1234567890123456);
        expect(request.headers['Idempotency-Key'], 'vote-intent-123');
        if (calls == 1) throw http.ClientException('offline');
        return http.Response('{"id":1,"my_vote":false}', 200);
      }),
    );
    addTearDown(api.dispose);
    final result = await api.voteProposal(
      token: 'token-test',
      proposalId: 1,
      agrees: false,
      idempotencyKey: 'vote-intent-123',
      intentVersion: 1234567890123456,
    );
    expect(calls, 2);
    expect(result['my_vote'], false);
  });
  test('mapa usa ETag e aceita resposta 304', () async {
    late http.Request captured;
    final api = GranMapApi(
      baseUrl: 'https://api.granmap.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response('', 304, headers: {'etag': '"map-v10"'});
      }),
    );

    final result = await api.fetchCurrentMapConditional(etag: '"map-v10"');

    expect(result.notModified, isTrue);
    expect(captured.headers['If-None-Match'], '"map-v10"');
    expect(captured.headers['X-Request-ID'], startsWith('gm-'));
  });

  test('operação idempotente repete após falha de conexão', () async {
    var calls = 0;
    final api = GranMapApi(
      baseUrl: 'https://api.granmap.test',
      client: MockClient((request) async {
        calls++;
        expect(request.headers['Idempotency-Key'], 'proposal-user-123');
        if (calls == 1) throw http.ClientException('offline');
        return http.Response(
          '{"id":1,"subject":"Teste","author_name":"Aluno",'
          '"from_room":"A","to_room":"B","reason":"Mudança",'
          '"status":"unverified","yes_votes":0,"no_votes":0}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.createProposal(
      token: 'token-test',
      subject: 'Teste',
      fromRoom: 'A',
      toRoom: 'B',
      reason: 'Mudança',
      idempotencyKey: 'proposal-user-123',
    );

    expect(result['id'], 1);
    expect(calls, 2);
  });

  test('erro HTTP é classificado para a interface', () async {
    final api = GranMapApi(
      baseUrl: 'https://api.granmap.test',
      client: MockClient(
        (_) async => http.Response('{"detail":"Sessão expirada."}', 401),
      ),
    );

    await expectLater(
      api.fetchMe('expired'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'status', 401)
            .having((error) => error.kind, 'kind', ApiFailureKind.unauthorized),
      ),
    );
  });

  test('erro 422 com lista no detail usa mensagem amigável', () async {
    final api = GranMapApi(
      baseUrl: 'https://api.granmap.test',
      client: MockClient(
        (_) async => http.Response(
          '{"detail":[{"type":"string_too_short","loc":["body","name"],"msg":"too short"}]}',
          422,
        ),
      ),
    );

    await expectLater(
      api.fetchMe('token'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'status', 422)
            .having((error) => error.kind, 'kind', ApiFailureKind.validation)
            .having(
              (error) => error.message,
              'message',
              'Confira os dados informados e tente novamente.',
            ),
      ),
    );
  });
}
