import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createApp} from '../server.mjs';
test('two-person cycle, hidden answer, access control, persistence and role reversal',async()=>{
 const dataDir=await mkdtemp(path.join(tmpdir(),'shotrelay-'));let server,base;
 async function boot(){server=await createApp({dataDir});await new Promise(r=>server.listen(0,'127.0.0.1',r));base=`http://127.0.0.1:${server.address().port}`}
 const close=()=>new Promise(r=>server.close(r));await boot();
 async function request(route,data,cookie){const r=await fetch(base+'/api/'+route,{method:data?'POST':'GET',headers:{...(data?{'Content-Type':'application/json'}:{}),...(cookie?{Cookie:cookie}:{})},body:data?JSON.stringify(data):undefined});return{status:r.status,data:await r.json(),cookie:r.headers.get('set-cookie')?.split(';')[0]}}
 try{
 const a=(await request('login',{name:'A'})).cookie,b=(await request('login',{name:'B'})).cookie,c=(await request('login',{name:'outside'})).cookie;
 const room=await request('rooms',{},a);assert.equal(room.status,201);assert.equal((await request('join',{code:room.data.code},b)).status,200);assert.equal((await request('join',{code:room.data.code},c)).status,409);
 const jpeg='data:image/jpeg;base64,'+(await readFile(new URL('fixtures/photo.jpg',import.meta.url))).toString('base64');
 assert.equal((await request('rounds',{photos:['data:image/jpeg;base64,YWJj']},a)).status,400);
 const round=await request('rounds',{photos:[jpeg,jpeg,jpeg,jpeg]},a);assert.equal(round.status,201);
 const before=(await request('state',null,b)).data.rounds[0];assert.equal(before.photos.length,4);const favoriteId=before.photos[2].id;
 assert.equal((await fetch(base+`/api/photos/${round.data.id}/${favoriteId}`,{headers:{Cookie:c}})).status,404);
 assert.equal((await request(`rounds/${round.data.id}/favorite`,{photoId:favoriteId},a)).status,403);
 assert.equal((await request(`rounds/${round.data.id}/favorite`,{photoId:favoriteId,reasons:['背景が好き']},b)).status,200);
 const hidden=(await request('state',null,a)).data.rounds[0];assert.equal(hidden.status,'guessing');assert.equal(hidden.favorite,null);assert.equal(hidden.answer,null);assert.equal(hidden.photos.length,3);assert.ok(hidden.photos.some(p=>p.id===favoriteId));
 assert.equal((await request(`rounds/${round.data.id}/guess`,{photoId:favoriteId},a)).status,200);
 const revealed=(await request('state',null,a)).data.rounds[0];assert.equal(revealed.answer.correct,true);assert.equal(revealed.favorite.photoId,favoriteId);assert.deepEqual(revealed.favorite.reasons,['背景が好き']);
 await close();await boot();assert.equal((await request('state',null,a)).data.rounds[0].answer.correct,true);
 const reverse=await request('rounds',{photos:[jpeg]},b);assert.equal(reverse.status,201);const inbox=(await request('state',null,a)).data.rounds[0];assert.equal((await request(`rounds/${reverse.data.id}/favorite`,{photoId:inbox.photos[0].id,reasons:[]},a)).status,200);const result=(await request('state',null,b)).data.rounds[0];assert.equal(result.status,'revealed');assert.equal(result.answer.skipped,true);
 const outsider=(await request('state',null,c)).data;assert.deepEqual(outsider.rounds,[]);
 const cross=await fetch(base+'/api/rooms',{method:'POST',headers:{Origin:'https://evil.example','Content-Type':'application/json',Cookie:c},body:'{}'});assert.equal(cross.status,403);
 }finally{await close();await rm(dataDir,{recursive:true,force:true})}
});
