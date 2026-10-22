'use strict';
const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../GasPractice.swiftpm'),web=path.join(root,'Resources/Web');
const html=fs.readFileSync(path.join(web,'index.html'),'utf8');
for(const [,file] of html.matchAll(/(?:src|href)="([^"#]+\.(?:js|css|svg|webmanifest))"/g)) {
 assert(fs.existsSync(path.join(web,file)),file);
}
const data={window:{}};vm.runInNewContext(fs.readFileSync(path.join(web,'data.js'),'utf8'),data);
const questions=data.window.PAPERS.flatMap(p=>p.questions);
assert.equal(questions.length,415);assert.equal(new Set(questions.map(q=>q.id)).size,415);
// v0.5 retains exact production learning assets; only app guide links differ.
for(const file of ['data.js','lessons.js','answer-cards.js','lesson-view.js','app.js','style.css','modern.css','dashboard.css','ink-gesture.js','ink-guard.js','ink-smoothing.js','question-follow.js']) {
 assert.deepEqual(fs.readFileSync(path.join(web,file)),fs.readFileSync(path.resolve(__dirname,'../../gas-practice/dist',file)),file+' source changed');
}
vm.runInNewContext(fs.readFileSync(path.join(web,'answer-cards.js'),'utf8'),data);for(const q of questions)assert(data.window.ANSWER_CARDS[q.id]?.answer,q.id);assert(!html.includes('class="hero"'));assert(html.indexOf('id="directAnswerText"')<html.indexOf('id="lessonText"'));
const native=fs.readFileSync(path.join(root,'PracticeController.swift'),'utf8').replace(/\r\n/g,'\n');
const bridge=native.match(/private static let bridge = #"""\n([\s\S]*?)\n\s*"""#/)[1];
const messages=[],events={};let callback,current=null;
function Anchor(){};let clicked=0;Anchor.prototype.click=function(){clicked++};
const study={hidden:true},title={textContent:'문제 1'};
const context={window:{webkit:{messageHandlers:{practice:{postMessage:value=>messages.push(value)}}}},
 document:{body:{},head:{append(){}},createElement:()=>({}),getElementById:id=>id==='study'?study:title},
 addEventListener:(event,cb)=>events[event]=cb,MutationObserver:class{constructor(cb){callback=cb}observe(){}},
 q:()=>current,setTimeout:cb=>cb(),HTMLAnchorElement:Anchor,fetch:()=>Promise.resolve({text:()=>Promise.resolve('{"records":{}}')})};
vm.runInNewContext(bridge,context);
assert.equal(messages.at(-1).id,null);
current={id:'q1',prompt:'한글 문제'};study.hidden=false;callback();
assert.equal(messages.at(-1).id,'q1');assert(messages.at(-1).title.includes('한글 문제'));
const n=messages.length;callback();assert.equal(messages.length,n,'no duplicate switches');
current={id:'q2',prompt:'다음 문제'};events.hashchange();assert.equal(messages.at(-1).id,'q2');
study.hidden=true;callback();assert.equal(messages.at(-1).id,null);
const external=new Anchor();external.href='https://example.com';external.click();assert.equal(clicked,1);
const backup=new Anchor();backup.download='backup.json';backup.href='blob:fixture';backup.click();
setImmediate(()=>{assert.equal(messages.at(-1).kind,'download');console.log('PASS: 415 questions; exact retained web assets; asset references; actual bridge question changes/home/deduplication/backup. Native Swift build NOT executed.');});
