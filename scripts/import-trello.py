#!/usr/bin/env python3
"""Convert a standard Trello board JSON export to Peperete's portable format."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path

def convert(board):
    stamp = datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
    result = dict(schemaVersion=1, revision=0, boards=[dict(id=board['id'], title=board['name'])], columns=[], cards=[])
    lists = sorted(board.get('lists', []), key=lambda value: value.get('pos', 0))
    result['columns'] = [dict(id=value['id'], boardID=board['id'], title=value['name'], position=index) for index, value in enumerate(lists)]
    valid = {value['id'] for value in lists}
    checklists = {value['id']: value for value in board.get('checklists', [])}
    for card in board.get('cards', []):
        if card['idList'] not in valid:
            raise ValueError(f"Card {card['id']} belongs to a list missing from this export")
        notes = [card.get('desc', '')]
        if card.get('labels'):
            notes.append('Labels: ' + ', '.join(value.get('name') or value.get('color', '') for value in card['labels']))
        for cid in card.get('idChecklists', []):
            if cid not in checklists:
                raise ValueError(f'Missing checklist {cid}; export the complete board first')
            checklist = checklists[cid]
            notes.append(checklist['name'] + '\n' + '\n'.join(('- [x] ' if item['state'] == 'complete' else '- [ ] ') + item['name'] for item in sorted(checklist.get('checkItems', []), key=lambda v: v.get('pos', 0))))
        comments = [value for value in board.get('actions', []) if value.get('type') == 'commentCard' and value.get('data', {}).get('card', {}).get('id') == card['id']]
        for comment in sorted(comments, key=lambda value: value.get('date', '')):
            notes.append(f"{comment.get('date', '')} — {comment.get('memberCreator', {}).get('fullName', 'Comment')}\n{comment['data'].get('text', '')}")
        if card.get('attachments'):
            notes.append('Attachments\n' + '\n'.join(value.get('name', 'Link') + ': ' + value['url'] for value in card['attachments']))
        item = dict(id=card['id'], columnID=card['idList'], title=card['name'], notes='\n\n'.join(value for value in notes if value),
                    completed=card.get('dueComplete', False), archived=card.get('closed', False), position=card.get('pos', 0),
                    sourceURL=card.get('url', 'https://trello.com/c/' + card.get('shortLink', '')), updatedAt=stamp)
        if card.get('due'):
            item['due'] = datetime.fromisoformat(card['due'].replace('Z', '+00:00')).astimezone(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
        result['cards'].append(item)
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = convert(json.loads(args.input.read_text()))
    # Never overwrite an existing backup/export.
    with args.output.open('x') as output: json.dump(result, output, ensure_ascii=False, indent=2)
    print(f"Converted {len(result['cards'])} cards; original export unchanged.")
