import struct,sys

def u16(b,o): return struct.unpack_from('>H',b,o)[0]
def u32(b,o): return struct.unpack_from('>I',b,o)[0]
def s16(b,o): return struct.unpack_from('>h',b,o)[0]

def tables(b):
    n=u16(b,4); t={}
    for i in range(n):
        o=12+16*i
        tag=b[o:o+4].decode('latin1')
        t[tag]=(u32(b,o+8),u32(b,o+12))
    return t

def names(b,t):
    if 'name' not in t: return {}
    off,_=t['name']
    cnt=u16(b,off+2); so=off+u16(b,off+4)
    out={}
    for i in range(cnt):
        o=off+6+12*i
        pid,eid,lid,nid,ln,no=struct.unpack_from('>6H',b,o)
        raw=b[so+no:so+no+ln]
        try:
            s=raw.decode('utf-16-be') if pid==3 else raw.decode('latin1')
        except Exception: s=repr(raw)
        out.setdefault(nid,s)
    return out

def cmaps(b,t):
    off,_=t['cmap']; n=u16(b,off+2); res=[]
    for i in range(n):
        pid,eid,so=struct.unpack_from('>HHI',b,off+4+8*i)
        sub=off+so; fmt=u16(b,sub)
        m={}
        if fmt==4:
            segX2=u16(b,sub+6); seg=segX2//2
            endo=sub+14; starto=endo+segX2+2; deltao=starto+segX2; rangeo=deltao+segX2
            for s_ in range(seg):
                end=u16(b,endo+2*s_); start=u16(b,starto+2*s_)
                delta=u16(b,deltao+2*s_); ro=u16(b,rangeo+2*s_)
                if start==0xFFFF: continue
                for c in range(start,min(end,0xFFFE)+1):
                    if ro==0: g=(c+delta)&0xFFFF
                    else:
                        gi=rangeo+2*s_+ro+2*(c-start)
                        if gi+1>=len(b): continue
                        g=u16(b,gi)
                        if g: g=(g+delta)&0xFFFF
                    if g: m[c]=g
        elif fmt==6:
            first=u16(b,sub+6); cnt=u16(b,sub+8)
            for k in range(cnt): 
                g=u16(b,sub+10+2*k)
                if g: m[first+k]=g
        elif fmt==0:
            for c in range(256):
                g=b[sub+6+c]
                if g: m[c]=g
        elif fmt==12:
            ng=u32(b,sub+12)
            for k in range(ng):
                s_,e_,gs=struct.unpack_from('>III',b,sub+16+12*k)
                for c in range(s_,min(e_,s_+65535)+1): m[c]=gs+(c-s_)
        res.append((pid,eid,fmt,m))
    return res

def gsub_info(b,t):
    if 'GSUB' not in t: return None
    off,ln=t['GSUB']
    scripts=[]; feats=[]
    sl=off+u16(b,off+4); fl=off+u16(b,off+6); ll=off+u16(b,off+8)
    for i in range(u16(b,sl)):
        scripts.append(b[sl+2+6*i:sl+6+6*i].decode('latin1'))
    for i in range(u16(b,fl)):
        feats.append(b[fl+2+6*i:fl+6+6*i].decode('latin1'))
    return dict(len=ln,scripts=scripts,features=sorted(set(feats)),nlookups=u16(b,ll))

for path in sys.argv[1:]:
    b=open(path,'rb').read()
    t=tables(b)
    nm=names(b,t)
    print("="*70); print(path, len(b),"bytes")
    print(" tables:", " ".join(sorted(t)))
    for k,v in [(1,'family'),(2,'sub'),(4,'full'),(5,'ver'),(6,'ps'),(0,'copyright')]:
        if k in nm: print(f"  name[{k}] {v}: {nm[k][:90]!r}")
    print(" units/em:", u16(b,t['head'][0]+18), " numGlyphs:", u16(b,t['maxp'][0]+4))
    for pid,eid,fmt,m in cmaps(b,t):
        ks=sorted(m)
        bng=[c for c in ks if 0x0980<=c<=0x09FF]
        lat=[c for c in ks if 0x20<=c<=0x7E]
        hi =[c for c in ks if 0xA0<=c<=0xFF]
        print(f"  cmap (pid={pid},eid={eid},fmt={fmt}): {len(m)} maps | ascii={len(lat)} latin1hi={len(hi)} bengali={len(bng)}")
    g=gsub_info(b,t)
    print("  GSUB:", g)
    print("  GPOS:", ('present %d bytes'%t['GPOS'][1]) if 'GPOS' in t else None)
