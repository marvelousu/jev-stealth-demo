"""Run the same-choice response regression against a local, deterministic HTTP fixture."""
from pathlib import Path
import argparse,json,os,subprocess,threading
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def reply(self,payload):
  data=json.dumps(payload).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 def do_GET(self):self.reply({'enabled':True,'api_key_configured':True})
 def do_POST(self):
  request=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  self.reply({'request_id':request['request_id'],'revision':request['revision'],'choice':'inspect','source':'jev','status':'ok','confidence':1})
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--godot',required=True);parser.add_argument('--path',type=Path,default=Path(__file__).resolve().parents[1]);args=parser.parse_args()
 with ThreadingHTTPServer(('127.0.0.1',0),Handler) as server:
  threading.Thread(target=server.serve_forever,daemon=True).start()
  env=dict(os.environ,RELAY_TEST_URL=f'http://127.0.0.1:{server.server_port}')
  try:run=subprocess.run([args.godot,'--headless','--path',str(args.path),'--script',str(Path(__file__).with_name('verify_audit_ui.gd')),'--','--play'],env=env,timeout=35,capture_output=True,text=True,encoding="utf-8",errors="replace");print(run.stdout);print(run.stderr)
  finally:server.shutdown()
 raise SystemExit(run.returncode)
