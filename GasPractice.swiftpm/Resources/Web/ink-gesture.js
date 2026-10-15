'use strict';
(function(root){
 const LIMITS=Object.freeze({MAX_SAMPLES:8192,MIN_SAMPLES:32,MIN_POSITIONS:12,MAX_MS:3500,MIN_TURNS:2.75,MIN_SPEED:.85,MIN_DIRECTION:.85,MIN_DIAMETER:16,MAX_DIAMETER:240,MIN_ASPECT:.5,MAX_ASPECT:2,MAX_RADIAL_CV:.35,MAX_GAP:Math.PI/2,BRUSH:4,ROW_GAP:2,MAX_ROWS:128});
 function derive(samples){
  if(!Array.isArray(samples)||samples.length>LIMITS.MAX_SAMPLES||samples.length< LIMITS.MIN_SAMPLES)return null;
  const points=[],positions=new Set();let time=-Infinity,minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;
  for(const s of samples){
   if(!s||![s.x,s.y,s.timeStamp,s.pressure].every(Number.isFinite)||s.timeStamp<time||s.pressure<0||s.pressure>1||s.pointerType!=='pen'||s.isPrimary!==true||s.contact!==true)return null;
   time=s.timeStamp;const last=points[points.length-1];if(last&&last.x===s.x&&last.y===s.y)continue;
   points.push(s);positions.add(s.x+','+s.y);minX=Math.min(minX,s.x);maxX=Math.max(maxX,s.x);minY=Math.min(minY,s.y);maxY=Math.max(maxY,s.y);
  }
  const duration=samples[samples.length-1].timeStamp-samples[0].timeStamp;
  if(positions.size<LIMITS.MIN_POSITIONS||duration<=0||duration>LIMITS.MAX_MS)return null;
  const rx=(maxX-minX)/2,ry=(maxY-minY)/2,aspect=rx/ry;
  if(Math.min(rx,ry)*2<LIMITS.MIN_DIAMETER||Math.max(rx,ry)*2>LIMITS.MAX_DIAMETER||aspect<LIMITS.MIN_ASPECT||aspect>LIMITS.MAX_ASPECT)return null;
  return {points,duration,cx:(maxX+minX)/2,cy:(maxY+minY)/2,rx,ry};
 }
 function recognize(samples,context){
  if(!context||context.tool!=='pen'||context.pointerType!=='pen'||context.isPrimary!==true||context.cleanRelease!==true||context.eligible!==true)return null;
  const fit=derive(samples);if(!fit)return null;
  let signed=0,total=0,radius=0,radiusSquared=0,previous=null;
  for(const p of fit.points){
   const x=(p.x-fit.cx)/fit.rx,y=(p.y-fit.cy)/fit.ry,r=Math.hypot(x,y),angle=Math.atan2(y,x);
   if(previous!==null){const delta=Math.atan2(Math.sin(angle-previous),Math.cos(angle-previous));if(Math.abs(delta)>LIMITS.MAX_GAP)return null;signed+=delta;total+=Math.abs(delta);}
   radius+=r;radiusSquared+=r*r;previous=angle;
  }
  const turns=Math.abs(signed)/(2*Math.PI),mean=radius/fit.points.length,cv=Math.sqrt(Math.max(0,radiusSquared/fit.points.length-mean*mean))/mean;
  const epsilon=1e-9;
  // Repeated turns establish intent; lifting at the original start is not required.
  if(turns+epsilon<LIMITS.MIN_TURNS||turns*1000/fit.duration+epsilon<LIMITS.MIN_SPEED||Math.abs(signed)/total<LIMITS.MIN_DIRECTION||cv>LIMITS.MAX_RADIAL_CV)return null;
  return {cx:fit.cx,cy:fit.cy,rx:fit.rx,ry:fit.ry};
 }
 function eraserStroke(area,geometry){
  if(!area||!geometry||![area.cx,area.cy,area.rx,area.ry,geometry.width,geometry.height,geometry.backingWidth,geometry.backingHeight].every(Number.isFinite))return null;
  const {cx,cy,rx,ry}=area,{width,height,backingWidth,backingHeight}=geometry;
  if(Math.min(width,height,backingWidth,backingHeight)<=0||rx<=LIMITS.BRUSH/2||ry<=LIMITS.BRUSH/2||cx-rx<0||cy-ry<0||cx+rx>width||cy+ry>height)return null;
  const insetX=rx-LIMITS.BRUSH/2,insetY=ry-LIMITS.BRUSH/2,rows=Math.ceil(2*insetY/LIMITS.ROW_GAP);
  if(rows+1>LIMITS.MAX_ROWS)return null;
  const points=[];
  for(let row=0;row<=rows;row++){
   const y=-insetY+row*(2*insetY/rows),chord=insetX*Math.sqrt(Math.max(0,1-(y/insetY)**2));
   const ends=row%2?[chord,-chord]:[-chord,chord];for(const x of ends)points.push([(cx+x)/width,(cy+y)/height,.5]);
  }
  return {tool:'eraser',color:'#203f38',width:1,diameter:LIMITS.BRUSH*backingWidth/width,points};
 }
 const api=Object.freeze({recognize,eraserStroke,LIMITS});
 if(typeof module==='object'&&module.exports)module.exports=api;
 else root.InkGesture=api;
})(typeof globalThis==='object'?globalThis:this);
