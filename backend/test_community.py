from pathlib import Path
import tempfile
import unittest

import auth_router
import db
import main


class CommunityFlowTest(unittest.TestCase):
    def setUp(self):
        self._original_db_path = db.DB_PATH
        self._temporary = tempfile.TemporaryDirectory()
        db.DB_PATH = Path(self._temporary.name) / "test.db"
        db.init_db()

        with db.connect() as con:
            con.execute(
                "INSERT INTO courses(name) VALUES (?)",
                ("Engenharia da Computação",),
            )
            con.commit()

        self.tokens = []
        for index in range(6):
            result = auth_router.register(
                auth_router.RegisterIn(
                    name=f"Pessoa {index}",
                    email=f"pessoa{index}@teste.local",
                    password="segredo123",
                    course_name="Engenharia da Computação",
                    semester=4,
                    group_name="EC4A",
                )
            )
            self.tokens.append(result["token"])

    def tearDown(self):
        db.DB_PATH = self._original_db_path
        self._temporary.cleanup()

    def authorization(self, index: int) -> str:
        return f"Bearer {self.tokens[index]}"

    def create_proposal(self):
        return main.create_proposal(
            main.ProposalIn(
                subject="Estrutura de Dados",
                from_room="Alan Turing",
                to_room="Henry Ford",
                reason="Alteração informada em sala pelo professor.",
            ),
            authorization=self.authorization(0),
        )

    def test_unique_vote_consensus_and_reputation(self):
        proposal = self.create_proposal()
        self.assertEqual(proposal["status"], "unverified")

        for index in range(5):
            result = main.vote(
                proposal["id"],
                main.VoteIn(agrees=index < 4),
                authorization=self.authorization(index),
            )

        self.assertEqual(result["status"], "confirmed")
        self.assertEqual(result["yes_votes"], 4)
        self.assertEqual(result["no_votes"], 1)

        changed = main.vote(
            proposal["id"],
            main.VoteIn(agrees=False),
            authorization=self.authorization(0),
        )
        self.assertEqual(changed["yes_votes"], 3)
        self.assertEqual(changed["no_votes"], 2)

        with db.connect() as con:
            vote_count = con.execute(
                "SELECT COUNT(*) FROM votes WHERE proposal_id = ?",
                (proposal["id"],),
            ).fetchone()[0]
            reputation = con.execute(
                "SELECT reputation FROM users WHERE email = ?",
                ("pessoa0@teste.local",),
            ).fetchone()[0]

        self.assertEqual(vote_count, 5)
        self.assertEqual(reputation, 3)

    def test_idempotency_key_does_not_duplicate_proposal_or_reputation(self):
        payload = main.ProposalIn(
            subject="Banco de Dados",
            from_room="Alan Turing",
            to_room="Henry Ford",
            reason="Mudança informada pelo professor.",
        )
        first = main.create_proposal(
            payload,
            authorization=self.authorization(0),
            idempotency_key="proposal-student-123",
        )
        repeated = main.create_proposal(
            payload,
            authorization=self.authorization(0),
            idempotency_key="proposal-student-123",
        )

        self.assertEqual(first["id"], repeated["id"])
        with db.connect() as con:
            count = con.execute("SELECT COUNT(*) FROM proposals").fetchone()[0]
            reputation = con.execute(
                "SELECT reputation FROM users WHERE email = ?",
                ("pessoa0@teste.local",),
            ).fetchone()[0]
        self.assertEqual(count, 1)
        self.assertEqual(reputation, 1)

    def test_official_write_requires_coordination_or_admin(self):
        with self.assertRaises(Exception) as raised:
            main.create_course(
                main.CourseIn(name="Administração"),
                authorization=self.authorization(0),
            )
        self.assertEqual(raised.exception.status_code, 403)

        with db.connect() as con:
            con.execute(
                "UPDATE users SET role = 'admin' WHERE email = ?",
                ("pessoa0@teste.local",),
            )
            con.commit()

        created = main.create_course(
            main.CourseIn(name="Administração"),
            authorization=self.authorization(0),
        )
        self.assertEqual(created["name"], "Administração")

    def test_moderator_can_close_proposal(self):
        proposal = self.create_proposal()
        with db.connect() as con:
            con.execute(
                "UPDATE users SET role = 'moderator' WHERE email = ?",
                ("pessoa1@teste.local",),
            )
            con.commit()

        moderated = main.moderate_proposal(
            proposal["id"],
            main.ModerationIn(
                status="rejected",
                moderation_note="Informação institucional confirmou a sala original.",
                official_priority=True,
            ),
            authorization=self.authorization(1),
        )
        self.assertEqual(moderated["status"], "rejected")
        self.assertTrue(moderated["official_priority"])


if __name__ == "__main__":
    unittest.main()
