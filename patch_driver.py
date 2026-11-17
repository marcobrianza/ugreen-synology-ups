from pathlib import Path
import struct,hashlib,json,argparse
parser=argparse.ArgumentParser(description="Reproduce the tested UGREEN patch on the exact Synology original")
parser.add_argument("original",type=Path)
parser.add_argument("output",type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parent
orig=args.original.read_bytes()
assert hashlib.sha256(orig).hexdigest()=='c40952698fc8b333eba260169328c533f98c4a3dc58174774b0be87b549182c8'
b=bytearray(orig)
assert b[0x48920:0x48940]==bytes(32)
b[0x48920:0x48924]=struct.pack('<HH',0x2b89,0xffff)
assert b[0x253f9:0x2540a]==bytes.fromhex('c7055d2a0200020000004889055e2a0200')
b[0x253f9:0x2540a]=b'\x90'*17
h=struct.unpack_from('<16sHHIQQQIHHHHHH',orig)
ss=[struct.unpack_from('<IIQQQQIIQQ',orig,h[6]+i*h[11]) for i in range(h[12])]
def off(a):
 for s in ss:
  if s[1]!=8 and s[3]<=a<s[3]+s[5]:return a-s[3]+s[4]
 raise ValueError(hex(a))
def string(a):return orig[off(a):].split(b'\0')[0].decode()
# Reuse existing, standard read-only HID mappings. No write flags or instant commands.
sources=[0x48320,0x49d78,0x48400,0x4c1f0,0x4c110,0x48ba8,0x48be0,0x48c88]
# Eight mappings fit within nine former Arduino timer/command entries.
start=0x499a0;end=0x49b98
relocs=[]
for s in ss:
 if s[1]==4:
  for p in range(s[4],s[4]+s[5],24):
   target,typ,value=struct.unpack_from('<QQq',orig,p)
   if start<=target<end:
    assert typ==8
    relocs.append(p)
wanted=[];manifest=[]
for i,source in enumerate(sources):
 vals=list(struct.unpack_from('<7Q',orig,off(source)))
 assert vals[1]==0 and vals[3]==0
 assert vals[5] in [0,16]
 target=start+i*56
 struct.pack_into('<7Q',b,off(target),*vals)
 for j in [0,2,4,6]:
  if vals[j]:wanted.append((target+j*8,8,vals[j]))
 manifest.append({'name':string(vals[0]),'path':string(vals[2]),'source_address':hex(source)})
# Clear unused last entry and preserve original terminator.
b[off(start+len(sources)*56):off(end)+56]=bytes(end+56-(start+len(sources)*56))
assert len(wanted)<=len(relocs)
# Redundant RELATIVE relocations write the same first pointer, idempotently.
for i,p in enumerate(relocs):struct.pack_into('<QQq',b,p,*(wanted[i] if i<len(wanted) else wanted[0]))
# Validate the resulting table with a simulated dynamic-loader relocation pass.
loaded=bytearray(b)
for p in relocs:
 a,t,v=struct.unpack_from('<QQq',b,p);struct.pack_into('<Q',loaded,off(a),v)
for i,source in enumerate(sources):assert loaded[off(start+i*56):off(start+i*56)+56]==orig[off(source):off(source)+56]
assert loaded[off(start+len(sources)*56):off(end)+56]==bytes(end+56-(start+len(sources)*56))
assert len(b)==len(orig)
out=args.output;out.write_bytes(b);out.chmod(0o755)
report={'sha256':hashlib.sha256(b).hexdigest(),'mappings':manifest,'original_table_relocations':len(relocs),'needed_relocations':len(wanted),'validation':'ELF mapping table and relocations verified offline; runtime pending. No shutdown command mappings; monitoring-only test.'}
out.with_name(out.name+'.verification.json').write_text(json.dumps(report,indent=2)+'\n')
assert report['sha256']=='3a14cd2a9d982ef675032a509e3396e03e5636979d70e576557c369c4fee639a'
print(json.dumps(report,indent=2))
