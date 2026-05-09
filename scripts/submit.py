import jwt, time, requests, sys

KEY_ID = 'WDXGY9WX55'
ISSUER = '2be0734f-943a-4d61-9dc9-5d9045c46fec'
APP_ID = '6767871447'
BUILD_NUMBER = sys.argv[1]

p8 = open('/tmp/asc_key.p8').read()

def make_token():
    return jwt.encode(
        {'iss': ISSUER, 'iat': int(time.time()), 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'},
        p8, algorithm='ES256', headers={'kid': KEY_ID}
    )

def headers():
    return {'Authorization': f'Bearer {make_token()}', 'Content-Type': 'application/json'}

def api(method, path, **kwargs):
    r = requests.request(method, f'https://api.appstoreconnect.apple.com/v1{path}',
        headers=headers(), **kwargs)
    return r

print(f'Waiting for build {BUILD_NUMBER} to be processed...')
build_id = None
for i in range(80):
    r = api('GET', f'/builds?filter[app]={APP_ID}&filter[version]={BUILD_NUMBER}&filter[processingState]=VALID&limit=1')
    data = r.json()
    if data.get('data'):
        build_id = data['data'][0]['id']
        print(f'Build ready: {build_id}')
        break
    print(f'  Waiting... ({i+1}/80)')
    time.sleep(30)

if not build_id:
    print('WARNING: Build not found after 40 minutes. Check ASC manually.')
    sys.exit(0)

r = api('PATCH', f'/builds/{build_id}',
    json={'data': {'type': 'builds', 'id': build_id, 'attributes': {'usesNonExemptEncryption': False}}})
print(f'Export compliance: {r.status_code}')

version_id = None
version_state = None
r = api('GET', f'/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=1')
data = r.json()
if data.get('data'):
    version_id = data['data'][0]['id']
    version_state = data['data'][0]['attributes']['appStoreState']
    print(f'Found version: {version_id} state={version_state}')

if version_state in ('WAITING_FOR_REVIEW', 'IN_REVIEW'):
    print(f'Already in review ({version_state}). Nothing to do.')
    sys.exit(0)

if not version_id or version_state in ('READY_FOR_DISTRIBUTION',):
    print('Creating new version...')
    r = api('POST', '/appStoreVersions', json={
        'data': {
            'type': 'appStoreVersions',
            'attributes': {'platform': 'IOS', 'versionString': '1.0'},
            'relationships': {'app': {'data': {'type': 'apps', 'id': APP_ID}}}
        }
    })
    if r.status_code not in (200, 201):
        print(f'Failed to create version: {r.text[:300]}')
        sys.exit(1)
    version_id = r.json()['data']['id']
    version_state = 'PREPARE_FOR_SUBMISSION'

print(f'Version ID: {version_id} state={version_state}')

# Set App Review Notes
review_notes = """1. Screen recording: The app launches directly to the Othello (Reversi) game board. The user plays as black against an AI opponent. Tap any valid move (highlighted cells) to place a piece. The app displays joseki (opening theory) names and descriptions as the game follows known patterns. Users can undo moves, adjust AI difficulty, and start new games. ATT prompt appears for AdMob ad personalization.

2. Tested on: iPhone 15 Pro (iOS 18.4), iPhone 16 Pro Max (iOS 18.4), iPhone SE 3rd gen (iOS 18.4), iPad Pro 11-inch (iPadOS 18.4)

3. Purpose: An Othello/Reversi game app with built-in joseki (opening theory) education. Target audience: Othello enthusiasts who want to learn classic opening strategies while playing against AI. The app solves the problem of learning Othello joseki by showing real-time joseki names, descriptions, and available branches as the player makes moves. It includes 20+ named joseki patterns (Tiger, Rabbit, Rose, etc.).

4. Setup: No login required. Launch the app and the game board is ready. Tap a highlighted cell to place a black piece. The AI responds automatically. The joseki panel below the board shows current opening theory. Use the undo button to take back moves, the slider to adjust AI difficulty (1-5), and the reset button to start a new game.

5. External services:
- Google AdMob: Banner and interstitial advertisements
- No other external services. The AI opponent and joseki database are entirely on-device.

6. Regional differences: None. The app functions consistently across all regions. UI is in Japanese. The game of Othello/Reversi is universal.

7. Not applicable. Othello/Reversi is a public domain board game. The app does not operate in a regulated industry and does not include protected third-party material."""

r = api('GET', f'/appStoreVersions/{version_id}/appStoreReviewDetail')
if r.status_code == 200 and r.json().get('data'):
    detail_id = r.json()['data']['id']
    r = api('PATCH', f'/appStoreReviewDetails/{detail_id}', json={
        'data': {'type': 'appStoreReviewDetails', 'id': detail_id,
                 'attributes': {'notes': review_notes}}
    })
    print(f'Review notes updated: {r.status_code}')
else:
    r = api('POST', '/appStoreReviewDetails', json={
        'data': {
            'type': 'appStoreReviewDetails',
            'attributes': {'notes': review_notes},
            'relationships': {
                'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version_id}}
            }
        }
    })
    print(f'Review notes created: {r.status_code}')

r = api('PATCH', f'/appStoreVersions/{version_id}/relationships/build',
    json={'data': {'type': 'builds', 'id': build_id}})
print(f'Build assigned: {r.status_code}')

canceled_any = False
for state_filter in ['UNRESOLVED_ISSUES', 'READY_FOR_REVIEW']:
    r = api('GET', f'/apps/{APP_ID}/reviewSubmissions?filter[state]={state_filter}')
    if r.status_code == 200:
        for sub in r.json().get('data', []):
            sid = sub['id']
            st = sub['attributes']['state']
            cr = api('PATCH', f'/reviewSubmissions/{sid}', json={
                'data': {'type': 'reviewSubmissions', 'id': sid, 'attributes': {'canceled': True}}
            })
            print(f'Cancel {sid} state={st}: {cr.status_code}')
            canceled_any = True

if canceled_any:
    print('Waiting 30s for cancellations to propagate...')
    time.sleep(30)
    r = api('GET', f'/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=1')
    data = r.json()
    if data.get('data'):
        version_id = data['data'][0]['id']
        version_state = data['data'][0]['attributes']['appStoreState']
        print(f'Version after cancel: {version_id} state={version_state}')
    r = api('PATCH', f'/appStoreVersions/{version_id}/relationships/build',
        json={'data': {'type': 'builds', 'id': build_id}})
    print(f'Build re-assigned: {r.status_code}')

submission_id = None
for attempt in range(5):
    r = api('POST', '/reviewSubmissions', json={
        'data': {
            'type': 'reviewSubmissions',
            'relationships': {'app': {'data': {'type': 'apps', 'id': APP_ID}}}
        }
    })
    if r.status_code == 201:
        submission_id = r.json()['data']['id']
        print(f'ReviewSubmission created: {submission_id}')
        break
    print(f'Create reviewSubmission attempt {attempt+1}/5 failed: {r.status_code} {r.text[:200]}')
    if attempt < 4:
        time.sleep(15)

if not submission_id:
    print('Could not create reviewSubmission after 5 attempts.')
    sys.exit(0)

item_added = False
for attempt in range(5):
    r = api('POST', '/reviewSubmissionItems', json={
        'data': {
            'type': 'reviewSubmissionItems',
            'relationships': {
                'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': submission_id}},
                'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version_id}}
            }
        }
    })
    print(f'Add item attempt {attempt+1}/5: {r.status_code}')
    if r.status_code == 201:
        item_added = True
        break
    if attempt < 4:
        time.sleep(15)

if not item_added:
    print(f'Failed to add item: {r.text[:300]}')
    sys.exit(0)

r = api('PATCH', f'/reviewSubmissions/{submission_id}', json={
    'data': {
        'type': 'reviewSubmissions',
        'id': submission_id,
        'attributes': {'submitted': True}
    }
})
if r.status_code == 200:
    state = r.json()['data']['attributes']['state']
    print(f'Submitted! State: {state}')
else:
    print(f'Submit failed: {r.status_code} {r.text[:300]}')
