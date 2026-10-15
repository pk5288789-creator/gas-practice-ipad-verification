'use strict';
/* Keep every explanation, but give each part its own readable step. */
window.lessonSteps = function(lesson){
  if(Array.isArray(lesson.steps)&&lesson.steps.length)return lesson.steps;
  const headings=/^(답안에 쓸 핵심(?:.*)?|왜 그런가요\??|기억할 점|사용 공식|단위 정리|적용 범위|계산과정|계산 과정|답|해설)$/;
  const text=lesson.text.replace(/\r/g,'').replace(/([^\n])\s*([①②③④⑤⑥⑦⑧⑨⑩])/g,'$1\n\n$2');
  const chunks=text.split(/\n+/).map(s=>s.trim()).filter(Boolean);
  let pending='';const steps=[];
  for(const chunk of chunks){
    if(headings.test(chunk)){pending=chunk;continue;}
    let lines=chunk.split('\n'),title=pending;pending='';
    if(headings.test(lines[0])&&lines.length>1){title=lines.shift();}
    const body=lines.join('\n').replace(/^[①②③④⑤⑥⑦⑧⑨⑩]\s*/,'');
    if(!title){
      if(/^(?:주의|원문|다만|단,|적용|기준 읽기|실제|이때|참고|확인)/.test(body))title='해석과 주의사항';
      else if(/^(?:단위|온도|압력|주어진 값|조건|먼저)/.test(body))title='조건과 단위 확인';
      else if(/^(?:사용 공식|공식|반응식|출발식|기본식)/.test(body))title='사용할 공식';
      else if(/^(?:답|최종|따라서|결과)/.test(body))title='결과 정리';
      else title=lesson.kind==='calculation'?(steps.length?'계산과 해석':'풀이의 출발점'):(steps.length?'원리와 기억할 점':'답안 핵심');
    }
    steps.push({title,body});
  }
  return steps;
};
window.renderLesson = function(lesson){
  const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const format=s=>escape(s).replace(/\^\(([^)]+)\)/g,'<sup>$1</sup>');
  const paragraphs=body=>String(body).replace(/^[①②③④⑤⑥⑦⑧⑨⑩]\s*/,'').split(/\n|(?<=[^\d]\.)\s+/).filter(s=>s.trim()).map(line=>{
    const formula=/[=→]|\^\(/.test(line)&&line.length<180;
    return `<p${formula?' class="formula-line"':''}>${format(line)}</p>`;
  }).join('');
  return '<ol class="lesson-steps">'+window.lessonSteps(lesson).map((s,i)=>`<li class="lesson-step"><div class="step-heading"><span class="step-number" aria-hidden="true">${String(i+1).padStart(2,'0')}</span><h3>${escape(s.title)}</h3></div><div class="step-body">${paragraphs(s.body)}</div></li>`).join('')+'</ol>';
};
