#!/usr/bin/env bash
# Fetch project data via GraphQL and produce data.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

gh api graphql -f query='
{
  organization(login: "LOGNEXTCODE") {
    projectV2(number: 1) {
      title
      items(first: 100) {
        nodes {
          id
          fieldValues(first: 20) {
            nodes {
              ... on ProjectV2ItemFieldTextValue { text field { ... on ProjectV2Field { name } } }
              ... on ProjectV2ItemFieldNumberValue { number field { ... on ProjectV2Field { name } } }
              ... on ProjectV2ItemFieldDateValue { date field { ... on ProjectV2Field { name } } }
              ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2SingleSelectField { name } } }
            }
          }
          content {
            ... on Issue {
              number
              title
              state
              url
              labels(first: 10) { nodes { name } }
              parent { number title }
              subIssues(first: 30) {
                totalCount
                nodes { number title state }
              }
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}' | python3 -c "
import json, sys
from datetime import datetime, timezone

raw = json.load(sys.stdin)
nodes = raw['data']['organization']['projectV2']['items']['nodes']

items = []
for node in nodes:
    content = node.get('content')
    if not content or not content.get('number'):
        continue

    fields = {}
    for fv in node.get('fieldValues', {}).get('nodes', []):
        field_name = fv.get('field', {}).get('name', '')
        if 'text' in fv:
            fields[field_name] = fv['text']
        elif 'number' in fv:
            fields[field_name] = fv['number']
        elif 'date' in fv:
            fields[field_name] = fv['date']
        elif 'name' in fv and 'field' in fv:
            fields[field_name] = fv['name']

    item = {
        'id': node['id'],
        'number': content['number'],
        'title': content['title'],
        'state': content.get('state', ''),
        'url': content.get('url', ''),
        'labels': [l['name'] for l in content.get('labels', {}).get('nodes', [])],
        'status': fields.get('Status', ''),
        'phase': fields.get('Phase', ''),
        'startDate': fields.get('Start Date', ''),
        'targetDate': fields.get('Target Date', ''),
        'estimate': fields.get('Estimate', 0),
        'parentNumber': content.get('parent', {}).get('number') if content.get('parent') else None,
        'parentTitle': content.get('parent', {}).get('title') if content.get('parent') else None,
        'subIssuesTotal': content.get('subIssues', {}).get('totalCount', 0),
        'subIssues': [
            {'number': s['number'], 'title': s['title'], 'state': s['state']}
            for s in content.get('subIssues', {}).get('nodes', [])
        ],
    }
    items.append(item)

output = {
    'generatedAt': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'items': items,
}
json.dump(output, sys.stdout, indent=2)
" > "$SCRIPT_DIR/data.json"

echo "Generated data.json with $(python3 -c "import json; print(len(json.load(open('$SCRIPT_DIR/data.json'))['items']))" ) items"
