// Keep large original art lossless without a >32MiB object in the Site repository.
export function installDownloads(){for(const link of document.querySelectorAll('[data-fx60-download]'))link.addEventListener('click',async event=>{
 event.preventDefault();if(link.dataset.busy)return;link.dataset.busy='1';const label=link.textContent;
 try{const url=new URL(link.getAttribute('href'),location.href),response=await fetch(url);if(!response.ok)throw Error('清单无法读取');const m=await response.json();const chunks=Array(m.parts.length);let next=0,done=0;
  await Promise.all(Array.from({length:4},async()=>{while(next<m.parts.length){const i=next++,part=m.parts[i],r=await fetch(new URL(part.path,url));if(!r.ok)throw Error('分片下载失败');const bytes=new Uint8Array(await r.arrayBuffer());if(bytes.length!==part.bytes)throw Error('分片长度不符');chunks[i]=bytes;link.textContent=`准备原画 ${++done}/${m.parts.length}…`;}}));
  const merged=new Uint8Array(m.bytes);let offset=0;for(const chunk of chunks){merged.set(chunk,offset);offset+=chunk.length;}if(offset!==m.bytes)throw Error('素材包长度不符');const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',merged)),x=>x.toString(16).padStart(2,'0')).join('');if(hash!==m.sha256)throw Error('素材包校验失败');
  const blobURL=URL.createObjectURL(new Blob([merged],{type:'application/zip'}));const a=document.createElement('a');a.href=blobURL;a.download=m.file;a.click();setTimeout(()=>URL.revokeObjectURL(blobURL),60000);link.textContent='原画已下载 · 再次下载 ↗';
 }catch(e){link.textContent='下载失败，点击重试';link.title=e.message;console.error(e);}finally{delete link.dataset.busy;}
});}
