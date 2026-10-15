'use strict';
const $=id=>document.getElementById(id),papers=window.PAPERS,all=papers.flatMap(p=>p.questions),validIds=new Set(all.map(q=>q.id));
let records={},db=null,type='written',year='all',paper=null,queue=[],index=0,tool='pen',ink='#203f38',activeStroke=null,activePointer=null,redo=[],saveChain=Promise.resolve(),saveFailure=false,fingerScroll=null,lastPen=0;
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmt=s=>esc(s).replace(/\^\(([^)]+)\)/g,'<sup>$1</sup>');
const label=p=>`${p.year}년 ${p.round} · ${p.type==='written'?'필답형':'작업형'}`;
function toast(t){$('toast').textContent=t;$('toast').classList.add('show');clearTimeout(toast.timer);toast.timer=setTimeout(()=>$('toast').classList.remove('show'),4000);}
function rec(id){return records[id]||(records[id]={strokes:[],text:'',done:false,review:false,updatedAt:0});}
function q(){return queue[index];}
function storageError(){saveFailure=true;$('saveState').textContent='저장 실패 · 백업 필요';toast('기기에 저장하지 못했습니다. 목록의 학습 기록 백업을 이용하세요.');}
function persist(id){let r=rec(id);r.updatedAt=Date.now();const copy=JSON.parse(JSON.stringify(r));$('saveState').textContent='저장 중…';saveChain=saveChain.catch(()=>{}).then(()=>new Promise((resolve,reject)=>{if(!db){try{localStorage.setItem('gas-practice-v1',JSON.stringify(records));resolve();}catch(e){reject(e)}return;}const tx=db.transaction('records','readwrite');tx.objectStore('records').put(copy,id);tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error);})).then(()=>{saveFailure=false;$('saveState').textContent='✓ 이 기기에 저장됨';}).catch(storageError);return saveChain;}
async function init(){try{db=await new Promise((resolve,reject)=>{let req=indexedDB.open('gas-practice',1);req.onupgradeneeded=()=>req.result.createObjectStore('records');req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);req.onblocked=()=>reject(new Error('blocked'));});await new Promise((resolve,reject)=>{const req=db.transaction('records').objectStore('records').openCursor();req.onsuccess=()=>{const c=req.result;if(c){if(validIds.has(c.key))records[c.key]=c.value;c.continue();}else resolve();};req.onerror=reject;});}catch(e){try{records=JSON.parse(localStorage.getItem('gas-practice-v1')||'{}');}catch(e){records={};storageError();}}
renderLibrary();$('saveState').textContent='✓ 이 기기에 자동 저장';try{const last=JSON.parse(localStorage.getItem('gas-last')||'null');if(last&&papers.some(p=>p.id===last.paper))$('resume').textContent='이어서 연습하기 ↗';}catch(e){}if(location.hash.startsWith('#exam='))route();}
function renderLibrary(){const totalDone=all.filter(x=>rec(x.id).done).length,totalReview=all.filter(x=>rec(x.id).review).length;$('totalCount').textContent=all.length;$('doneCount').textContent=totalDone;$('reviewCount').textContent=totalReview;
$('years').innerHTML=['all',...new Set(papers.map(p=>p.year).sort((a,b)=>b-a))].map(y=>`<button data-year="${y}" class="${String(y)===String(year)?'active':''}" aria-pressed="${String(y)===String(year)}">${y==='all'?'전체 연도':y+'년'}<small>${papers.filter(p=>p.type===type&&(y==='all'||p.year===y)).length}</small></button>`).join('');
document.querySelectorAll('[data-type]').forEach(b=>{const selected=b.dataset.type===type;b.classList.toggle('active',selected);b.setAttribute('aria-pressed',selected);});
const search=$('search').value.trim().toLowerCase(),ps=papers.filter(p=>p.type===type&&(year==='all'||p.year==year)&&(!search||(`${label(p)} ${p.questions.map(q=>q.prompt).join(' ')}`).toLowerCase().includes(search)));
$('listTitle').textContent=(year==='all'?'전체 연도':year+'년')+' · '+(type==='written'?'필답형':'작업형');$('listCount').textContent=ps.length+'개 자료';$('noResults').hidden=ps.length>0;
$('cards').innerHTML=ps.map(p=>{let n=p.questions.filter(q=>rec(q.id).done).length;return `<article class="exam-card"><div class="card-top"><span class="pill ${p.type}">${p.type==='written'?'필답형':'작업형'}</span>${p.partial?'<span class="partial">부분 복원</span>':'<span class="partial">복원문제</span>'}</div><h3>${p.year}년 ${esc(p.round)}</h3><p>${p.questions.length}문항 · ${p.type==='written'?'서술·계산 연습':'상황·설비 연습'}</p><div class="progress-track"><i style="width:${n/p.questions.length*100}%"></i></div><div class="card-footer"><small>${n} / ${p.questions.length} 완료</small><button data-paper="${p.id}" aria-label="${esc(label(p))} 연습하기">연습하기 ↗</button></div></article>`;}).join('');}
function openPaper(id,no){paper=papers.find(p=>p.id===id);if(!paper)return;queue=[...paper.questions];index=Math.max(0,queue.findIndex(q=>q.no===Number(no)));$('onlyReview').checked=false;location.hash=`exam=${id}&q=${queue[index].no}`;showStudy();}
function route(){finishStroke();const match=location.hash.match(/^#exam=(\d+)&q=(\d+)$/);if(!match){$('library').hidden=false;$('study').hidden=true;paper=null;renderLibrary();return;}const p=papers.find(p=>p.id===match[1]);if(!p)return;if(!paper||paper.id!==p.id){paper=p;queue=[...p.questions];$('onlyReview').checked=false;}let ix=queue.findIndex(q=>q.no===+match[2]);if(ix<0){queue=[...paper.questions];ix=queue.findIndex(q=>q.no===+match[2]);$('onlyReview').checked=false;}index=Math.max(0,ix);showStudy();}
function showStudy(){finishStroke();$('library').hidden=true;$('study').hidden=false;$('paperLabel').textContent=label(paper);$('examTitle').textContent=`${paper.year}년 ${paper.round}`;$('sourceSide').href=paper.url;renderQuestion();try{localStorage.setItem('gas-last',JSON.stringify({paper:paper.id,no:q().no}));}catch(e){}window.scrollTo({top:0,behavior:'instant'});}
function updateSidebar(){const n=paper.questions.filter(q=>rec(q.id).done).length;$('examDone').textContent=`${n} / ${paper.questions.length} 학습 완료`;$('examProgress').style.width=n/paper.questions.length*100+'%';$('questionNumbers').innerHTML=queue.map((x,i)=>`<button data-index="${i}" class="${i===index?'active ':''}${rec(x.id).done?'done ':''}${rec(x.id).review?'review':''}" aria-label="${x.no}번 문제${rec(x.id).done?' 학습 완료':''}" aria-current="${i===index?'true':'false'}">${x.no}</button>`).join('');}
function renderQuestion(){hideCursor();const current=q(),r=rec(current.id);redo=[];$('qType').textContent=paper.type==='written'?'필답형':'작업형';$('qType').className='pill '+paper.type;$('qPosition').textContent=`${index+1} / ${queue.length}`;$('qTitle').textContent=`문제 ${String(current.no).padStart(2,'0')}`;$('questionText').innerHTML=fmt(current.prompt);$('answerText').innerHTML=fmt(current.answer||'원문에 풀이가 아직 제공되지 않았습니다.');const lesson=window.LESSONS?.[current.id];$('lesson').hidden=!lesson;$('answer').querySelector('details').open=!lesson;$('lessonText').innerHTML=lesson?window.renderLesson(lesson):'';$('lessonSources').innerHTML=lesson?(lesson.sources||[]).map(x=>`<a href="${esc(x.url)}" target="_blank" rel="noopener">${esc(x.title)} ↗</a>`).join(' · '):'';$('notices').innerHTML=current.notice.map(n=>`<div class="notice">${esc(n)}</div>`).join('');$('source').href=paper.url;$('answer').hidden=true;$('answerToggle').textContent='풀이 확인하기';$('answerToggle').setAttribute('aria-expanded','false');$('typed').value=r.text;updateMarks();updateSidebar();$('navPosition').textContent=`${index+1} / ${queue.length}`;$('prev').disabled=index===0;$('next').disabled=index===queue.length-1;draw();}
function updateMarks(){const r=rec(q().id);$('bookmark').textContent=r.review?'★ 다시 풀기':'☆ 다시 풀기';$('bookmark').classList.toggle('selected',r.review);$('bookmark').setAttribute('aria-pressed',r.review);$('complete').textContent=r.done?'✓ 완료 · 다음 문제':'✓ 학습 완료 · 다음 문제';$('complete').classList.toggle('selected',r.done);$('complete').setAttribute('aria-pressed',r.done);}
function navigate(i){finishStroke();index=i;location.hash=`exam=${paper.id}&q=${q().no}`;}
const canvas=$('canvas'),ctx=canvas.getContext('2d');
const SMOOTHING_KEY='gas-practice-smoothing-v1';
let smoothingStrength=0,completedLayer=null;
try{smoothingStrength=InkSmoothing.normalizeStrength(localStorage.getItem(SMOOTHING_KEY));}catch(e){}
function paint(rawStroke){const stroke=InkSmoothing.deriveStroke(rawStroke,smoothingStrength);if(!stroke)return;ctx.globalCompositeOperation=stroke.tool==='eraser'?'destination-out':'source-over';ctx.strokeStyle=stroke.color;ctx.fillStyle=stroke.color;ctx.lineCap='round';ctx.lineJoin='round';const pts=stroke.points;for(let i=0;i<pts.length;i++){const p=pts[i],a=pts[Math.max(0,i-1)];ctx.lineWidth=stroke.tool==='eraser'&&stroke.diameter?stroke.diameter:stroke.width*(stroke.tool==='eraser'?7:1)*(0.55+(p[2]||0.5));ctx.beginPath();ctx.moveTo(a[0]*canvas.width,a[1]*canvas.height);ctx.lineTo(p[0]*canvas.width,p[1]*canvas.height);ctx.stroke();if(i===0){ctx.beginPath();ctx.arc(p[0]*canvas.width,p[1]*canvas.height,ctx.lineWidth/2,0,Math.PI*2);ctx.fill();}}ctx.globalCompositeOperation='source-over';}
function draw(){ctx.clearRect(0,0,canvas.width,canvas.height);if(!q())return;for(const s of rec(q().id).strokes)paint(s);if(activeStroke)paint(activeStroke);$('canvasHint').hidden=rec(q().id).strokes.length>0||!!activeStroke;$('undo').disabled=rec(q().id).strokes.length===0;$('redo').disabled=redo.length===0;}
function captureCompleted(){completedLayer=document.createElement('canvas');completedLayer.width=canvas.width;completedLayer.height=canvas.height;completedLayer.getContext('2d').drawImage(canvas,0,0);}
function previewActive(){ctx.clearRect(0,0,canvas.width,canvas.height);ctx.drawImage(completedLayer,0,0);paint(activeStroke);}
function updateSmoothing(){
 finishStroke();smoothingStrength=InkSmoothing.normalizeStrength($('smoothing').value);
 $('smoothing').value=String(smoothingStrength);$('smoothingValue').value=smoothingStrength+'%';
 try{localStorage.setItem(SMOOTHING_KEY,String(smoothingStrength));}catch(e){}
 draw();
}
$('smoothing').value=String(smoothingStrength);$('smoothingValue').value=smoothingStrength+'%';$('smoothing').oninput=updateSmoothing;
let hoverPoint=null;
function hideCursor(){ $('toolCursor').hidden=true;hoverPoint=null; }
function updateCursor(e){
 if(e&&e.pointerType==='touch'&&(activePointer!==null||Date.now()-lastPen<800))return;
 if(e&&e.pointerType==='touch'&&!$('finger').checked){hideCursor();return;}
 const b=canvas.getBoundingClientRect();if(!b.width)return;
 if(e)hoverPoint={x:e.clientX-b.left,y:e.clientY-b.top};
 if(!hoverPoint)return;
 const d=tool==='eraser'?+$('eraserSize').value:+$('width').value;
 const c=$('toolCursor');c.hidden=false;c.classList.toggle('is-eraser',tool==='eraser');
 c.style.width=d+'px';c.style.height=d+'px';c.style.left=hoverPoint.x+'px';c.style.top=hoverPoint.y+'px';
}
function updateEraser(){const n=+$('eraserSize').value;$('eraserValue').value=n+' px';$('eraserPreview').style.width=n+'px';$('eraserPreview').style.height=n+'px';updateCursor();}
$('eraserSize').oninput=updateEraser;
canvas.addEventListener('pointerenter',updateCursor);canvas.addEventListener('pointerleave',hideCursor);
window.addEventListener('scroll',hideCursor,{passive:true});window.addEventListener('resize',hideCursor);
let strokeRect=null,gestureCandidate=null;
function captureGesture(e,release=false){
 const g=gestureCandidate;if(!g||!g.eligible)return;
 const x=e.clientX-strokeRect.left,y=e.clientY-strokeRect.top,timeStamp=e.timeStamp;
 if(g.samples.length>=InkGesture.LIMITS.MAX_SAMPLES||![x,y,timeStamp,e.pressure].every(Number.isFinite)||timeStamp<g.lastTime||e.pointerType!=='pen'||e.isPrimary!==true||(!release&&e.buttons===0)||x<0||y<0||x>strokeRect.width||y>strokeRect.height){g.eligible=false;return;}
 g.samples.push({x,y,timeStamp,pressure:e.pressure,pointerType:e.pointerType,isPrimary:e.isPrimary,contact:true});g.lastTime=timeStamp;
}
function point(e){const b=strokeRect||canvas.getBoundingClientRect();return [Math.max(0,Math.min(1,(e.clientX-b.left)/b.width)),Math.max(0,Math.min(1,(e.clientY-b.top)/b.height)),e.pointerType==='pen'?Math.max(.25,Math.min(1,e.pressure||.5)):.5];}
canvas.style.touchAction='none';
const inkGuard=installInkGuard({canvas,notebook:canvas.closest('.notebook'),isDrawing:()=>activeStroke!==null});
for(const name of ['contextmenu','selectstart','dragstart'])canvas.addEventListener(name,e=>e.preventDefault());
canvas.addEventListener('pointerdown',e=>{
 if(!q())return;
 if(e.pointerType==='pen'){lastPen=Date.now();fingerScroll=null;if(activeStroke)finishStroke();}
 if(activePointer!==null||(!e.isPrimary&&e.pointerType!=='pen')||e.button!==0)return;
 if(e.pointerType==='touch'&&Date.now()-lastPen<1200){e.preventDefault();return;}
 if(e.pointerType==='touch'&&!$('finger').checked){fingerScroll={id:e.pointerId,y:e.clientY};canvas.setPointerCapture(e.pointerId);e.preventDefault();return;}
 e.preventDefault();inkGuard.prepare();strokeRect=canvas.getBoundingClientRect();activePointer=e.pointerId;captureCompleted();
 gestureCandidate={samples:[],lastTime:-Infinity,eligible:tool==='pen'&&e.pointerType==='pen'&&e.isPrimary===true&&e.buttons!==0,parent:canvas.parentNode,backingWidth:canvas.width,backingHeight:canvas.height};captureGesture(e);
 activeStroke={tool,color:ink,width:Math.min(60,+$('width').value*canvas.width/strokeRect.width),...(tool==='eraser'?{diameter:+$('eraserSize').value*canvas.width/strokeRect.width}:{}),points:[point(e)],id:q().id};
 canvas.setPointerCapture(e.pointerId);updateCursor(e);previewActive();$('canvasHint').hidden=true;
});
function appendInk(e,release=false){
 const b=canvas.getBoundingClientRect();
 if(!strokeRect||Math.abs(b.left-strokeRect.left)>1||Math.abs(b.top-strokeRect.top)>1||Math.abs(b.width-strokeRect.width)>1||Math.abs(b.height-strokeRect.height)>1||canvas.parentNode!==gestureCandidate.parent||canvas.width!==gestureCandidate.backingWidth||canvas.height!==gestureCandidate.backingHeight){finishStroke();return;}
 // Use the captured coordinate frame through harmless subpixel layout jitter.
 if(e.clientX<b.left||e.clientX>b.right||e.clientY<b.top||e.clientY>b.bottom){finishStroke();return;}
 const events=e.getCoalescedEvents?e.getCoalescedEvents():[];
 for(const ev of events.length?events:[e]){captureGesture(ev,release);activeStroke.points.push(point(ev));}
 if(events.length&&release){captureGesture(e,true);activeStroke.points.push(point(e));}
 previewActive();
}
canvas.addEventListener('pointermove',e=>{
 if(e.pointerType==='pen')lastPen=Date.now();updateCursor(e);
 if(fingerScroll&&e.pointerId===fingerScroll.id){if(activePointer!==null||Date.now()-lastPen<1200){fingerScroll=null;return;}const delta=fingerScroll.y-e.clientY;fingerScroll.y=e.clientY;const dock=canvas.closest('.study-dock');if(dock)dock.scrollBy(0,delta);else window.scrollBy(0,delta);return;}
 if(e.pointerId!==activePointer||!activeStroke)return;e.preventDefault();
 if(e.buttons===0){finishStroke();return;}appendInk(e);
});
function finishStroke(e,cleanRelease=false){
 if(!activeStroke||(e&&e.pointerId!==activePointer))return;
 let s=activeStroke;const id=s.id,pointer=activePointer,g=gestureCandidate;
 const area=InkGesture.recognize(g.samples,{tool:s.tool,pointerType:e?.pointerType,isPrimary:e?.isPrimary,cleanRelease,eligible:g.eligible});
 const erased=area&&InkGesture.eraserStroke(area,{width:strokeRect.width,height:strokeRect.height,backingWidth:canvas.width,backingHeight:canvas.height});if(erased)s=erased;
 if(erased){ctx.clearRect(0,0,canvas.width,canvas.height);ctx.drawImage(completedLayer,0,0);paint(erased);}
 delete s.id;rec(id).strokes.push(s);activeStroke=null;activePointer=null;strokeRect=null;gestureCandidate=null;completedLayer=null;redo=[];
 if(canvas.hasPointerCapture(pointer))canvas.releasePointerCapture(pointer);
 persist(id);$('undo').disabled=false;$('redo').disabled=true;
}
for(const event of ['pointerup','pointercancel','lostpointercapture'])canvas.addEventListener(event,e=>{if(fingerScroll?.id===e.pointerId)fingerScroll=null;if(event==='pointerup'&&activeStroke&&e.pointerId===activePointer)appendInk(e,true);finishStroke(e,event==='pointerup');if(e.pointerType==='touch'||event==='pointercancel')hideCursor();});
canvas.addEventListener('pointerleave',e=>{if(gestureCandidate&&e.pointerId===activePointer)gestureCandidate.eligible=false;});
window.addEventListener('pointerup',e=>finishStroke(e));
window.addEventListener('blur',()=>{finishStroke();fingerScroll=null;});
document.addEventListener('visibilitychange',()=>{if(document.hidden){finishStroke();fingerScroll=null;}});
window.addEventListener('resize',()=>finishStroke());
document.addEventListener('scroll',()=>{if(activeStroke)finishStroke();},true);
$('width').onchange=()=>updateCursor();
$('finger').onchange=()=>canvas.classList.toggle('touch-ink',$('finger').checked);
function setTool(t){finishStroke();tool=t;$('eraserSettings').hidden=t!=='eraser';canvas.classList.toggle('erasing',t==='eraser');updateCursor();for(const id of ['pen','eraser']){$(id).classList.toggle('selected',id===t);$(id).setAttribute('aria-pressed',id===t);}}
$('pen').onclick=()=>setTool('pen');$('eraser').onclick=()=>setTool('eraser');document.querySelectorAll('[data-color]').forEach(b=>b.onclick=()=>{ink=b.dataset.color;setTool('pen');document.querySelectorAll('[data-color]').forEach(x=>{x.classList.toggle('selected',x===b);x.setAttribute('aria-pressed',x===b);});});
$('undo').onclick=()=>{finishStroke();const s=rec(q().id).strokes.pop();if(s)redo.push(s);persist(q().id);draw();};$('redo').onclick=()=>{finishStroke();const s=redo.pop();if(s)rec(q().id).strokes.push(s);persist(q().id);draw();};$('clearInk').onclick=()=>{finishStroke();if(confirm('이 문항의 필기를 모두 지울까요? 글 메모는 유지됩니다.')){rec(q().id).strokes=[];redo=[];persist(q().id);draw();}};
$('typed').oninput=()=>{rec(q().id).text=$('typed').value;persist(q().id);};
let completing=false;
$('complete').onclick=async()=>{
 if(completing||!q())return;completing=true;$('complete').disabled=true;finishStroke();
 const id=q().id;rec(id).done=true;await persist(id);
 if(q()?.id===id){updateMarks();updateSidebar();if(saveFailure){toast('저장하지 못해 현재 문제에 머물렀습니다. 기록을 백업해 주세요.');}else{let next=-1;for(let n=1;n<=queue.length;n++){const i=(index+n)%queue.length;if(!rec(queue[i].id).done){next=i;break;}}if(next<0){location.hash='';toast('선택한 문제를 모두 완료했습니다. 수고하셨습니다!');}else navigate(next);}}
 completing=false;$('complete').disabled=false;
};$('bookmark').onclick=()=>{rec(q().id).review=!rec(q().id).review;persist(q().id);updateMarks();updateSidebar();};
$('answerToggle').onclick=()=>{const open=$('answer').hidden;$('answer').hidden=!open;$('answerToggle').textContent=open?'풀이 접기':'풀이 확인하기';$('answerToggle').setAttribute('aria-expanded',open);};
$('prev').onclick=()=>navigate(index-1);$('next').onclick=()=>navigate(index+1);$('questionNumbers').onclick=e=>{const b=e.target.closest('[data-index]');if(b)navigate(+b.dataset.index);};
$('shuffle').onclick=()=>{for(let i=queue.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[queue[i],queue[j]]=[queue[j],queue[i]];}index=0;history.replaceState(null,'',`#exam=${paper.id}&q=${q().no}`);showStudy();toast('이번 회차의 문제 순서를 섞었습니다.');};
$('onlyReview').onchange=()=>{const next=$('onlyReview').checked?paper.questions.filter(x=>rec(x.id).review):paper.questions;if(!next.length){$('onlyReview').checked=false;toast('이 회차에 다시 풀 문제가 없습니다.');return;}queue=[...next];index=0;history.replaceState(null,'',`#exam=${paper.id}&q=${q().no}`);showStudy();};
$('back').onclick=()=>{finishStroke();location.hash='';};window.addEventListener('hashchange',route);document.querySelector('.brand').onclick=()=>{finishStroke();location.hash='';};
document.querySelectorAll('[data-type]').forEach(b=>b.onclick=()=>{type=b.dataset.type;renderLibrary();});$('years').onclick=e=>{const b=e.target.closest('[data-year]');if(b){year=b.dataset.year;renderLibrary();}};$('search').oninput=renderLibrary;$('cards').onclick=e=>{const b=e.target.closest('[data-paper]');if(b)openPaper(b.dataset.paper);};
$('resume').onclick=()=>{let last;try{last=JSON.parse(localStorage.getItem('gas-last'));}catch(e){}openPaper(last?.paper||papers[0].id,last?.no);};
$('reviewOnly').onclick=()=>{const p=papers.find(p=>p.questions.some(q=>rec(q.id).review));if(!p){toast('문제의 ☆ 다시 풀기를 누르면 여기에서 복습할 수 있습니다.');return;}paper=p;queue=p.questions.filter(q=>rec(q.id).review);index=0;$('onlyReview').checked=true;history.replaceState(null,'',`#exam=${paper.id}&q=${q().no}`);showStudy();toast('다시 풀 문제가 있는 첫 회차를 열었습니다.');};
function download(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);}
$('backup').onclick=()=>{finishStroke();download(new Blob([JSON.stringify({format:'gas-practice',version:1,exportedAt:new Date().toISOString(),records},null,2)],{type:'application/json'}),'gas-practice-backup.json');};
$('restore').onchange=async e=>{const f=e.target.files[0];if(!f)return;try{if(f.size>30*1024*1024)throw Error('파일은 30 MB 이하만 지원합니다.');const data=JSON.parse(await f.text());if(data.format!=='gas-practice'||data.version!==1||!data.records||Array.isArray(data.records))throw Error('연습실 백업 파일이 아닙니다.');const entries=Object.entries(data.records);for(const [id,r]of entries){if(!validIds.has(id)||!r||typeof r.text!=='string'||r.text.length>100000||!Array.isArray(r.strokes)||r.strokes.length>30000||typeof r.done!=='boolean'||typeof r.review!=='boolean')throw Error('백업 내용이 올바르지 않습니다.');for(const s of r.strokes){if(!['pen','eraser'].includes(s.tool)||!/^#[0-9a-f]{6}$/i.test(s.color)||!Number.isFinite(s.width)||s.width<1||s.width>60||(s.diameter!==undefined&&(!Number.isFinite(s.diameter)||s.diameter<1||s.diameter>2000))||!Array.isArray(s.points)||s.points.length>200000||s.points.some(p=>!Array.isArray(p)||p.length!==3||p.some(x=>!Number.isFinite(x)||x<0||x>1)))throw Error('필기 자료 형식이 올바르지 않습니다.');}}
if(!confirm('백업 기록을 가져올까요? 같은 문항은 더 최근에 수정된 기록을 유지합니다.'))return;let n=0;for(const[id,r]of entries){if(!records[id]||(r.updatedAt||0)>=(records[id].updatedAt||0)){records[id]=r;await persist(id);n++;}}renderLibrary();toast(n+'개 문항 기록을 가져왔습니다.');}catch(err){toast(err.message||'파일을 읽을 수 없습니다.');}finally{e.target.value='';}};
$('help').onclick=()=>$('helpDialog').showModal();$('helpDialog').querySelector('.close').onclick=()=>$('helpDialog').close();
window.addEventListener('pagehide',()=>finishStroke());
updateEraser();init();if('serviceWorker'in navigator&&location.protocol.startsWith('http'))navigator.serviceWorker.register('sw.js').catch(()=>{});
