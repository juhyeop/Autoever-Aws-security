"""Local demo only. No AWS SDK or credentials are used."""
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parent

def create_app():
    from flask import Flask, render_template
    app = Flask(__name__)
    @app.get('/')
    def index():
        return render_template('index.html')
    @app.get('/health')
    def health():
        return {'status': 'ok', 'mode': 'demo', 'aws_connected': False}
    return app

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=5000)
    args = parser.parse_args()
    try:
        app = create_app()
    except ModuleNotFoundError as exc:
        if exc.name != 'flask':
            raise
        # The same frontend can be previewed without installing Flask.
        from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
        class Handler(SimpleHTTPRequestHandler):
            def __init__(self, *a, **kw):
                super().__init__(*a, directory=str(ROOT), **kw)
            def do_GET(self):
                if self.path in ('/', '/index.html'):
                    self.path = '/templates/index.html'
                super().do_GET()
        print(f'Demo preview: http://127.0.0.1:{args.port}', flush=True)
        ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
    else:
        app.run(host='127.0.0.1', port=args.port, debug=False)
