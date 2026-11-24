'use strict';
const {onRequest} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {randomInt, randomBytes, createHash} = require('node:crypto');
initializeApp();
const db = getFirestore();
const options = {region:'us-central1', maxInstances:2, concurrency:10, timeoutSeconds:30, cors:['https://lynra.app']};
const hash = s => createHash('sha256').update(s).digest('hex');
const codes = db.collection('readRequests');
class Failure extends Error { constructor(status,message){super(message);this.status=status;} }
function endpoint(fn){return onRequest(options,async(req,res)=>{
  res.set('Cache-Control','no-store');
  if(req.method!=='POST') return res.status(405).json({error:'POST required'});
  if(!req.is('application/json')) return res.status(415).json({error:'JSON required'});
  if(!req.body || typeof req.body!=='object' || Buffer.byteLength(JSON.stringify(req.body))>200000) return res.status(400).json({error:'Invalid body'});
  try {res.json(await fn(req));} catch(e){if(!e.status) console.error('Backend error',e.code || e.name);res.status(e.status||500).json({error:e.status?e.message:'Server error'});}
});}
async function uid(req){const m=/^Bearer (\S+)$/.exec(req.get('Authorization')||'');if(!m)throw new Failure(401,'Authentication required');try{return (await getAuth().verifyIdToken(m[1])).uid;}catch{throw new Failure(401,'Invalid authentication');}}
async function limit(key,max,windowMs){const ref=db.collection('readRateLimits').doc(hash(key));await db.runTransaction(async t=>{const s=await t.get(ref);const d=s.data();const now=Date.now();const active=d && d.expiresAt.toMillis()>now;const count=active?d.count:0;if(count>=max)throw new Failure(429,'Too many requests');t.set(ref,{count:count+1,expiresAt:active?d.expiresAt:Timestamp.fromMillis(now+windowMs)});});}
function codeOf(req){const c=req.body.code;if(typeof c!=='string'||!/^\d{6}$/.test(c))throw new Failure(400,'Invalid code');return c;}
function active(d){return d && !d.used && d.expiresAt.toMillis()>Date.now();}
exports.createReadRequest=endpoint(async req=>{
 const owner=await uid(req);await limit('create:'+owner,5,30*60000);
 for(let i=0;i<12;i++){
  const code=String(randomInt(100000,1000000));const ref=codes.doc(code);const requestId=randomBytes(16).toString('hex');
  const expiresAt=Timestamp.fromMillis(Date.now()+30*60000);
  const ok=await db.runTransaction(async t=>{const s=await t.get(ref);if(s.exists&&s.data().expiresAt.toMillis()>Date.now())return false;t.set(ref,{ownerId:owner,requestId,expiresAt,used:false,createdAt:FieldValue.serverTimestamp()});return true;});
  if(ok)return {code,requestId,expiresAt:expiresAt.toMillis()};
 }throw new Failure(503,'Try again');
});
exports.validateReadCode=endpoint(async req=>{
 await limit('validate:'+req.ip,10,15*60000);const code=codeOf(req);const ref=codes.doc(code);const token=randomBytes(32).toString('hex');
 await db.runTransaction(async t=>{const s=await t.get(ref);const d=s.data();if(!active(d))throw new Failure(404,'Code invalid or expired');t.update(ref,{tokenHash:hash(token)});});return {token};
});
exports.submitReadProgram=endpoint(async req=>{
 await limit('submit:'+req.ip,10,15*60000);const code=codeOf(req);const {token,programJson}=req.body;
 if(typeof token!=='string'||! /^[a-f0-9]{64}$/.test(token)||typeof programJson!=='string'||Buffer.byteLength(programJson)>32768)throw new Failure(400,'Invalid program or token');
 let p;try{p=JSON.parse(programJson);}catch{throw new Failure(400,'Invalid JSON');}
 if(!p||p.formatVersion!==2||typeof p.name!=='string'||p.name.length>256||!Array.isArray(p.controlBlocks)||!p.controlBlocks.length)throw new Failure(400,'Invalid program format');
 await db.runTransaction(async t=>{const ref=codes.doc(code);const s=await t.get(ref);const d=s.data();if(!active(d)||d.tokenHash!==hash(token))throw new Failure(403,'Code or token invalid');
 const dest=db.collection('users').doc(d.ownerId).collection('programs').doc('read_'+d.requestId);
 t.create(dest,{name:p.name,program:p,createdAt:FieldValue.serverTimestamp(),updatedAt:FieldValue.serverTimestamp()});t.update(ref,{used:true,tokenHash:FieldValue.delete(),completedAt:FieldValue.serverTimestamp()});});return {ok:true};
});
