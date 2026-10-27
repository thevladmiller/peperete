import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('trello_import', Path(__file__).resolve().parents[1] / 'scripts/import-trello.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class TrelloImportTests(unittest.TestCase):
    def test_preserves_card_metadata_and_supplementary_content(self):
        raw = {
            'id': 'board', 'name': 'Test', 'lists': [{'id': 'todo', 'name': 'To do', 'pos': 1}],
            'cards': [{'id': 'card', 'idList': 'todo', 'name': 'Café', 'desc': 'Original notes',
                       'pos': 42, 'due': '2026-11-01T10:30:00.000+01:00', 'dueComplete': True,
                       'closed': True, 'url': 'https://trello.com/c/test', 'idChecklists': ['check'],
                       'attachments': [{'name': 'Reference', 'url': 'https://example.com/reference'}],
                       'labels': [{'name': 'Priority'}]}],
            'checklists': [{'id': 'check', 'name': 'Steps', 'checkItems': [{'name': 'First', 'state': 'complete', 'pos': 1}]}],
            'actions': [{'type': 'commentCard', 'date': '2026-10-01T12:00:00Z', 'memberCreator': {'fullName': 'Example'},
                         'data': {'card': {'id': 'card'}, 'text': 'Discussion'}}]
        }
        result = module.convert(raw)
        card = result['cards'][0]
        self.assertEqual(card['due'], '2026-11-01T09:30:00Z')
        self.assertTrue(card['completed'])
        self.assertTrue(card['archived'])
        self.assertEqual(card['position'], 42)
        for expected in ['Original notes', '- [x] First', 'Priority', 'Discussion', 'https://example.com/reference']:
            self.assertIn(expected, card['notes'])

    def test_rejects_missing_parent_instead_of_dropping_card(self):
        with self.assertRaises(ValueError):
            module.convert({'id': 'board', 'name': 'Test', 'lists': [], 'cards': [{'id': 'x', 'idList': 'missing'}]})

    def test_rejects_incomplete_checklist_export(self):
        with self.assertRaises(ValueError):
            module.convert({'id': 'b', 'name': 'Test', 'lists': [{'id': 'l', 'name': 'List'}],
                            'cards': [{'id': 'c', 'idList': 'l', 'name': 'Card', 'idChecklists': ['missing']}]})

if __name__ == '__main__': unittest.main()
