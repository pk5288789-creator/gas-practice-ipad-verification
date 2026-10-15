'use strict';
(()=>{
  const FALLBACK_TOP=8,COMPACT_CLEARANCE=44;
  const study=document.getElementById('study'),question=document.getElementById('questionText');
  const title=document.getElementById('qTitle');
  const rail=document.createElement('aside');rail.className='question-follow';rail.setAttribute('aria-label','현재 문제 참고');
  rail.innerHTML='<details><summary><span class="follow-title"></span><span class="follow-hint">문제 펼치기</span></summary><div class="follow-body prose" tabindex="0" aria-label="현재 문제 내용"></div></details>';
  const dock=document.createElement('div');dock.className='study-dock';dock.append(rail);
  document.querySelector('.study-layout').append(dock);
  const notebook=document.querySelector('.notebook'),home=document.createComment('notebook home');notebook.before(home);
  const details=rail.querySelector('details'),body=rail.querySelector('.follow-body');
  const wide=matchMedia('(min-width:900px) and (orientation:landscape)');
  let scheduled=false,dirty=false,lastTitle,lastBody;
  function finish(){if(typeof finishStroke==='function')finishStroke();}
  function position(){
    const cssTop=Number.parseFloat(getComputedStyle(rail).top);
    const boundary=(Number.isFinite(cssTop)?cssTop:FALLBACK_TOP)+COMPACT_CLEARANCE;
    const start=Math.min(title.getBoundingClientRect().top,question.getBoundingClientRect().top);
    const visible=!study.hidden&&(wide.matches||(Number.isFinite(start)&&start<boundary));
    rail.hidden=study.hidden;rail.classList.toggle('is-visible',visible);rail.inert=!visible;
  }
  function update(){scheduled=false;if(dirty){dirty=false;sync();}position();}
  function schedule(){if(!scheduled){scheduled=true;requestAnimationFrame(update);}}
  function hint(){rail.querySelector('.follow-hint').textContent=details.open?'문제 접기':'문제 펼치기';}
  function reset(){
    finish();
    if(wide.matches){if(notebook.parentNode!==dock)dock.append(notebook);}
    else if(notebook.parentNode===dock)home.after(notebook);
    details.open=wide.matches;hint();
  }
  function sync(){
    if(lastTitle===title.textContent&&lastBody===question.innerHTML)return;
    reset();lastTitle=title.textContent;lastBody=question.innerHTML;
    rail.querySelector('.follow-title').textContent=lastTitle+' · 현재 문제';
    body.innerHTML=lastBody;body.scrollTop=0;
  }
  function changed(){dirty=true;schedule();}
  const contentObserver=new MutationObserver(changed);
  for(const target of [title,question])contentObserver.observe(target,{childList:true,subtree:true,characterData:true});
  new MutationObserver(()=>{position();schedule();}).observe(study,{attributes:true,attributeFilter:['hidden']});
  const geometryObserver=new ResizeObserver(schedule);
  for(const target of [title,question,rail.querySelector('summary')])geometryObserver.observe(target);
  details.addEventListener('toggle',()=>{finish();hint();schedule();});
  // Finish before a user's toggle changes the dock layout beneath captured ink.
  rail.querySelector('summary').addEventListener('click',finish);
  wide.addEventListener('change',()=>{reset();schedule();});
  document.addEventListener('scroll',schedule,{capture:true,passive:true});
  addEventListener('resize',()=>{finish();schedule();},{passive:true});
  sync();position();
})();
