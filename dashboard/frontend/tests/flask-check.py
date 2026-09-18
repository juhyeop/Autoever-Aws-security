"""Run with Flask installed: python tests/flask-check.py."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run import create_app
client = create_app().test_client()
assert client.get('/').status_code == 200
assert client.get('/health').json == {'status': 'ok', 'mode': 'demo', 'aws_connected': False}
for asset in ('js/app.js', 'js/store.js', 'js/data.js', 'css/app.css', 'css/tailwind.css', 'vendor/chart.umd.js', 'data/countries.geojson'):
    assert client.get('/static/' + asset).status_code == 200, asset
print('PASS: Flask page, health, and all application assets')
