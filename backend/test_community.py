from pathlib import Path
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor

from pydantic import ValidationError

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

    def test_late_retry_cannot_replace_newer_vote(self):
        proposal = self.create_proposal()
        for agrees, revision in [(True, 100), (False, 102), (True, 101), (True, 100)]:
            result = main.vote(
                proposal["id"], main.VoteIn(agrees=agrees, intent_version=revision),
                authorization=self.authorization(0),
            )
        self.assertFalse(result["my_vote"])
        self.assertEqual(result["yes_votes"], 0)
        self.assertEqual(result["no_votes"], 1)
        with db.connect() as con:
            audits = con.execute(
                "SELECT COUNT(*) FROM audit_log WHERE action = 'proposal.voted'"
            ).fetchone()[0]
        self.assertEqual(audits, 2)

    def test_same_revision_is_idempotent_and_scoped_to_voter(self):
        proposal = self.create_proposal()
        for index, agrees in [(0, True), (0, False), (1, False)]:
            main.vote(
                proposal["id"], main.VoteIn(agrees=agrees, intent_version=1234),
                authorization=self.authorization(index),
            )
        result = main._proposal_with_votes(proposal["id"], 1)
        self.assertEqual(result["yes_votes"], 1)
        self.assertEqual(result["no_votes"], 1)

    def test_concurrent_votes_keep_newest_revision_and_one_record(self):
        proposal = self.create_proposal()

        def submit(revision):
            return main.vote(
                proposal["id"],
                main.VoteIn(agrees=revision % 2 == 0, intent_version=revision),
                authorization=self.authorization(0),
            )

        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(submit, [105, 102, 110, 101, 108, 103]))
        result = main._proposal_with_votes(proposal["id"], 1)
        self.assertEqual(result["yes_votes"], 1)
        self.assertEqual(result["no_votes"], 0)
        with db.connect() as con:
            rows = con.execute("SELECT * FROM votes").fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["intent_version"], 110)

    def test_vote_revision_is_bounded_for_mobile_and_web(self):
        for revision in [0, -1, 9007199254740992]:
            with self.assertRaises(ValidationError):
                main.VoteIn(agrees=True, intent_version=revision)

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
