// Keep WebKit's native text-selection gesture separate from canvas ink.
// Pointer events draw; legacy touch events only cancel browser defaults.
function installInkGuard({canvas,notebook,isDrawing}){
 const editable=node=>!!node?.closest?.('textarea,input:not([type=checkbox]):not([type=range]),[contenteditable="true"]');
 const element=node=>node?.nodeType===3?node.parentElement:node;
 const inside=node=>!!node&&notebook.contains(element(node));
 let suppressSelectionUntil=0;
 function clearSelection(){
  const selection=window.getSelection();
  if(!selection||selection.isCollapsed)return;
  if(editable(element(selection.anchorNode))||editable(element(selection.focusNode)))return;
  if(inside(selection.anchorNode)||inside(selection.focusNode)||isDrawing())selection.removeAllRanges();
 }
 function prepare(){
  suppressSelectionUntil=Date.now()+1500;
  // Dismiss a focused memo/Scribble target before beginning freehand ink.
  if(editable(document.activeElement))document.activeElement.blur();
  clearSelection();
 }
 for(const name of ['touchstart','touchmove','touchend']){
  canvas.addEventListener(name,e=>{if(e.cancelable)e.preventDefault();suppressSelectionUntil=Date.now()+1500;clearSelection();},{passive:false});
 }
 for(const name of ['selectstart','contextmenu','dragstart']){
  notebook.addEventListener(name,e=>{if(editable(e.target))return;e.preventDefault();clearSelection();},{capture:true});
 }
 document.addEventListener('selectionchange',()=>{
  if(isDrawing()||Date.now()<suppressSelectionUntil)clearSelection();
 });
 // Ignore simultaneous secondary contacts outside the canvas while a stroke
 // owns the pointer. Normal toolbar taps and memo editing remain available.
 const blocked=new Set();
 document.addEventListener('pointerdown',e=>{
  if(isDrawing()&&e.target!==canvas&&e.pointerType==='touch'){
   blocked.add(e.pointerId);e.preventDefault();e.stopImmediatePropagation();
  }else blocked.delete(e.pointerId);
 },{capture:true,passive:false});
 document.addEventListener('click',e=>{
  if(blocked.has(e.pointerId)){blocked.delete(e.pointerId);e.preventDefault();e.stopImmediatePropagation();}
 },true);
 document.addEventListener('pointercancel',e=>blocked.delete(e.pointerId),true);
 return {prepare};
}
