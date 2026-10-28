"""Read the official release ZIP by HTTP ranges and extract selected members.

TLS hostname validation remains enabled. No mirror or unsigned replacement is
used. Partial ZIP ranges and hashes are retained on D: for provenance.
"""
import hashlib,io,json,socket,time,urllib.request,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]/'tools/rife'
ROOT.mkdir(parents=True,exist_ok=True)
URL='https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-windows.zip'
ORIGIN_URL=URL
native=socket.getaddrinfo
def resolve(host,port,*a,**kw):
    if host=='github.com':return native('20.27.177.113',port,*a,**kw)
    return native(host,port,*a,**kw)
socket.getaddrinfo=resolve
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))

def request(start=None,end=None):
    headers={'User-Agent':'DragonIsland-local-animation-tools'}
    if start is not None:headers['Range']=f'bytes={start}' if start<0 else f'bytes={start}-{end if end is not None else ""}'
    for attempt in range(4):
        try:return opener.open(urllib.request.Request(URL,headers=headers),timeout=20)
        except Exception as error:
            print('Retry',attempt+1,type(error).__name__,str(error)[:160],flush=True)
    raise RuntimeError('official release connection failed')

class RemoteZip(io.RawIOBase):
    def __init__(self):
        global URL
        with request() as response:
            self.length=int(response.headers['Content-Length'])
            URL=response.url
        with request(self.length-65557,self.length-1) as response:
            cr=response.headers.get('Content-Range')
            if not cr:raise RuntimeError('range request unsupported; refusing whole bundle download')
            self.length=int(cr.split('/')[-1]);start=int(cr.split()[1].split('-')[0]);data=response.read()
        self.cache={(start,self.length):data};self.pos=0
        print('Official ZIP length',self.length,flush=True)
    def seekable(self):return True
    def readable(self):return True
    def tell(self):return self.pos
    def seek(self,offset,whence=0):
        self.pos=offset if whence==0 else self.pos+offset if whence==1 else self.length+offset
        return self.pos
    def read(self,size=-1):
        if size<0:size=self.length-self.pos
        start=self.pos;end=min(self.length,start+size)
        for (left,right),data in self.cache.items():
            if left<=start and end<=right:
                self.pos=end;return data[start-left:end-left]
        with request(start,end-1) as response:
            if response.status!=206:raise RuntimeError('range ignored')
            data=response.read()
        if len(data)!=end-start:raise RuntimeError('truncated range')
        self.cache[(start,end)]=data;self.pos=end
        return data

if __name__=='__main__':
    remote=RemoteZip()
    with zipfile.ZipFile(remote) as archive:
        records=[]
        for info in archive.infolist():
            path=Path(info.filename)
            if info.is_dir():continue
            if path.name.endswith('.exe') or path.name.endswith('.dll') or 'rife-v4.6' in path.parts or path.name.lower().startswith(('license','readme')):
                target=ROOT/path
                if target.exists() and target.stat().st_size==info.file_size:
                    data=target.read_bytes()
                else:
                    print('Extract',info.filename,info.file_size,flush=True)
                    data=archive.read(info)
                    target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
                records.append(dict(path=str(target.relative_to(ROOT)),size=len(data),sha256=hashlib.sha256(data).hexdigest()))
        (ROOT/'provenance.json').write_text(json.dumps(dict(source=ORIGIN_URL,files=records),indent=2),encoding='utf-8')
    print('RIFE portable tools ready',flush=True)
