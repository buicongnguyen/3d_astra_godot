import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve('build/web');
const types={'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml'};
http.createServer((req,res)=>{
  let pathname;
  try { pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\/3d_astra_godot(?=\/)/,''); } catch {res.writeHead(400).end();return;}
  const file=path.resolve(root,'.'+(pathname.endsWith('/')?pathname+'index.html':pathname));
  if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
  fs.readFile(file,(error,data)=>{if(error){res.writeHead(404).end();return;}res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(data);});
}).listen(Number(process.env.PORT||4176),'127.0.0.1',()=>console.log('Godot web build: http://127.0.0.1:4176/3d_astra_godot/'));
