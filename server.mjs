import http from 'node:http';
import { randomBytes, randomInt } from 'node:crypto';
import { mkdir, readFile, writeFile, rename, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const id=()=>randomBytes(16).toString('hex');
export async function createApp({dataDir=path.join(root,'data'), webDir=path.join(root,'flutter_app','build','web')}={}) {
 let flutterReady=false;try{await access(path.join(webDir,'index.html'));flutterReady=true}catch{}
 await mkdir(dataDir,{recursive:true});const dbPath=path.join(dataDir,'state.json');
 let db;try{db=JSON.parse(await readFile(dbPath,'utf8'))}catch(e){if(e.code!=='ENOENT')throw e;db={users:{},rooms:{},rounds:{}}}
 let writes=Promise.resolve();const persist=()=>{const snapshot=JSON.stringify(db);writes=writes.then(async()=>{await writeFile(dbPath+'.tmp',snapshot,{mode:0o600});await rename(dbPath+'.tmp',dbPath)});return writes};
 const fail=(status,message)=>{throw Object.assign(new Error(message),{status})};
 const server=http.createServer(async(req,res)=>{
  const send=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(data))};
  try{
   const url=new URL(req.url,'http://localhost');const cookies=Object.fromEntries((req.headers.cookie||'').split(';').map(x=>x.trim().split('=')));const user=db.users[cookies.shotrelay];
   if((req.method==='GET'||req.method==='HEAD')&&!url.pathname.startsWith('/api/')){
    const legacyRoute=url.pathname==='/legacy'||url.pathname.startsWith('/legacy/');
    const legacy=legacyRoute||['/app.js','/style.css'].includes(url.pathname);
    const staticRoot=flutterReady&&!legacy?webDir:path.join(root,'public');
    let relative=legacyRoute?url.pathname.slice('/legacy'.length):url.pathname;
    if(relative===''||relative==='/')relative='/index.html';
    const target=path.resolve(staticRoot,'.'+decodeURIComponent(relative));
    if(!target.startsWith(path.resolve(staticRoot)+path.sep))fail(403,'このファイルは閲覧できません');
    const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json','.png':'image/png','.jpg':'image/jpeg','.svg':'image/svg+xml','.wasm':'application/wasm','.ttf':'font/ttf','.otf':'font/otf','.woff2':'font/woff2'};
    let bytes;try{bytes=await readFile(target)}catch(e){if(e.code==='ENOENT')fail(404,'ファイルが見つかりません');throw e}
    res.writeHead(200,{'Content-Type':types[path.extname(target)]||'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});res.end(req.method==='HEAD'?undefined:bytes);return;
   }

   if(!url.pathname.startsWith('/api/')){send(404,{error:'見つかりません'});return}
   if(req.method!=='GET'&&req.headers.origin&&req.headers.origin!==`http://${req.headers.host}`&&req.headers.origin!==`https://${req.headers.host}`)fail(403,'別のサイトからは操作できません');
   let body={};if(req.method==='POST'){if(!req.headers['content-type']?.startsWith('application/json'))fail(415,'JSONで送信してください');let size=0,chunks=[];for await(const chunk of req){size+=chunk.length;if(size>20*1024*1024)fail(413,'写真が大きすぎます。一度に送る枚数を減らしてください');chunks.push(chunk)}try{body=JSON.parse(Buffer.concat(chunks).toString())}catch{fail(400,'送信内容を読み取れません')}}
   if(url.pathname==='/api/login'&&req.method==='POST'){
    const name=String(body.name||'').trim().slice(0,24);if(!name)fail(400,'名前を入力してください');
    if(user){user.name=name;await persist();send(200,{ok:true});return}
    const token=id();db.users[token]={id:id(),name,roomId:null};await persist();res.setHeader('Set-Cookie',`shotrelay=${token}; Path=/; HttpOnly; SameSite=Strict${req.socket.encrypted?'; Secure':''}`);send(200,{ok:true});return;
   }
   if(!user)fail(401,'最初に名前を入力してください');
   const room=user.roomId?db.rooms[user.roomId]:null;
   const roundFor=(rid)=>{const r=db.rounds[rid];if(!r||!room||r.roomId!==user.roomId||!room.members.includes(user.id))fail(404,'この写真は閲覧できません');return r};
   if(url.pathname==='/api/state'&&req.method==='GET'){
    const rounds=room?Object.values(db.rounds).filter(r=>r.roomId===user.roomId).map(r=>({id:r.id,photographerId:r.photographerId,subjectId:r.subjectId,createdAt:r.createdAt,photos:r.photos.filter(p=>r.photographerId!==user.id||!r.quizCandidates||r.answer||r.quizCandidates.includes(p.id)).map(p=>({id:p.id})),status:!r.favorite?'selecting':r.answer?'revealed':'guessing',favorite:r.subjectId===user.id||r.answer?r.favorite:null,answer:r.answer||null})).reverse():[];
    send(200,{user:{id:user.id,name:user.name},room:room?{code:room.code,members:room.members.map(uid=>{const u=Object.values(db.users).find(u=>u.id===uid);return{id:uid,name:u?.name||'相手'}})}:null,rounds});return;
   }
   if(url.pathname==='/api/rooms'&&req.method==='POST'){
    if(room)fail(409,'すでにペアに参加しています');let code;do{code=String(randomInt(100000,1000000))}while(Object.values(db.rooms).some(r=>r.code===code));const rid=id();db.rooms[rid]={code,members:[user.id]};user.roomId=rid;await persist();send(201,{code});return;
   }
   if(url.pathname==='/api/join'&&req.method==='POST'){
    if(room)fail(409,'すでにペアに参加しています');const entry=Object.entries(db.rooms).find(([,r])=>r.code===String(body.code).trim());if(!entry)fail(404,'招待コードが見つかりません');const[rid,target]=entry;if(target.members.length>=2)fail(409,'このペアはすでに2人参加しています');target.members.push(user.id);user.roomId=rid;await persist();send(200,{ok:true});return;
   }
   if(url.pathname==='/api/rounds'&&req.method==='POST'){
    if(!room||room.members.length!==2)fail(400,'相手が参加してから撮影してください');if(!Array.isArray(body.photos)||body.photos.length<1||body.photos.length>9)fail(400,'写真は1〜9枚で送ってください');
    const photos=body.photos.map(src=>{if(typeof src!=='string'||!/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(src)||src.length>2500000)fail(400,'JPEG写真のサイズまたは形式を確認してください');const buf=Buffer.from(src.split(',')[1],'base64');if(buf[0]!==255||buf[1]!==216||buf[2]!==255)fail(400,'JPEG写真ではありません');return{id:id(),src}});
    const rid=id();db.rounds[rid]={id:rid,roomId:user.roomId,photographerId:user.id,subjectId:room.members.find(uid=>uid!==user.id),photos,createdAt:new Date().toISOString(),favorite:null,answer:null};await persist();send(201,{id:rid});return;
   }
   const photoMatch=url.pathname.match(/^\/api\/photos\/([a-f0-9]+)\/([a-f0-9]+)$/);
   if(photoMatch&&req.method==='GET'){const r=roundFor(photoMatch[1]);const p=r.photos.find(p=>p.id===photoMatch[2]);if(!p)fail(404,'写真が見つかりません');res.writeHead(200,{'Content-Type':'image/jpeg','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(Buffer.from(p.src.split(',')[1],'base64'));return}
   const action=url.pathname.match(/^\/api\/rounds\/([a-f0-9]+)\/(favorite|guess)$/);
   if(action&&req.method==='POST'){
    const r=roundFor(action[1]);
    if(action[2]==='favorite'){if(r.subjectId!==user.id)fail(403,'撮られた人が選んでください');if(r.favorite)fail(409,'すでに選びました');if(!r.photos.some(p=>p.id===body.photoId))fail(400,'写真を選んでください');r.favorite={photoId:body.photoId,reasons:Array.isArray(body.reasons)?body.reasons.filter(x=>['構図が好き','表情がいい','背景が好き','雰囲気が好き','自分らしい'].includes(x)):[]};if(r.photos.length>=3){const other=r.photos.filter(p=>p.id!==body.photoId);for(let i=other.length-1;i>0;i--){const j=randomInt(i+1);[other[i],other[j]]=[other[j],other[i]]}r.quizCandidates=[body.photoId,...other.slice(0,2).map(p=>p.id)];for(let i=2;i>0;i--){const j=randomInt(i+1);[r.quizCandidates[i],r.quizCandidates[j]]=[r.quizCandidates[j],r.quizCandidates[i]]}}else r.answer={photoId:null,correct:null,skipped:true};}
    else{if(r.photographerId!==user.id)fail(403,'撮った人が予想してください');if(!r.favorite)fail(409,'相手の選択を待っています');if(r.answer)fail(409,'すでに答え合わせしました');if(!body.skip&&!r.quizCandidates?.includes(body.photoId))fail(400,'写真を選んでください');r.answer={photoId:body.skip?null:body.photoId,correct:body.skip?null:body.photoId===r.favorite.photoId,skipped:!!body.skip};}
    await persist();send(200,{ok:true});return;
   }
   send(404,{error:'見つかりません'});
  }catch(e){if(!res.headersSent)send(e.status||500,{error:e.status?e.message:'保存または通信に失敗しました。もう一度お試しください。'});else res.end();if(!e.status)console.error(e)}
 });return server;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){const server=await createApp({dataDir:process.env.DATA_DIR||undefined});server.listen(Number(process.env.PORT||3000),'0.0.0.0',()=>console.log(`ShotRelay: http://localhost:${process.env.PORT||3000}`))}
