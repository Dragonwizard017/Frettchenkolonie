import re,glob
hits=[]
for f in glob.glob("**/*.gd",recursive=True):
    if f.startswith("_t/"): continue
    L=open(f,encoding="utf8").read().split("\n")
    def indent(l): return len(l)-len(l.lstrip("\t"))
    # Funktionsgrenzen
    fn_starts=[i for i,l in enumerate(L) if re.match(r'^(static )?func ',l)]
    fn_starts.append(len(L))
    for a,b in zip(fn_starts,fn_starts[1:]):
        locals_=set(re.findall(r'^\s*var\s+(\w+)',"\n".join(L[a:b]),re.M))
        i=a
        while i<b:
            l=L[i]
            if re.search(r'\bfunc\s*\(',l) and not re.match(r'^(static )?func ',l):
                base=indent(l)
                j=i+1; body=[]
                # Einzeiler-Lambda: Rest der Zeile nach "func(...):"
                m=re.search(r'func\s*\([^)]*\)\s*(->\s*\w+\s*)?:(.*)$',l)
                if m and m.group(2).strip(): body.append((i,m.group(2)))
                while j<b and (L[j].strip()=="" or indent(L[j])>base):
                    body.append((j,L[j])); j+=1
                declared=set(re.findall(r'\bvar\s+(\w+)',"\n".join(t for _,t in body)))
                params=set(re.findall(r'func\s*\(([^)]*)\)',l)[0].split(",")) if re.search(r'func\s*\(([^)]*)\)',l) else set()
                params={re.split(r'[:\s=]',p.strip())[0] for p in params if p.strip()}
                for ln,t in body:
                    m2=re.match(r'^\s*(\w+)\s*(=|\+=|-=|\*=|/=)\s',t.strip()+" ") if False else re.match(r'^\s*(\w+)\s*(\+=|-=|\*=|/=|=)(?!=)',t)
                    if m2:
                        v=m2.group(1)
                        if v in locals_ and v not in declared and v not in params and v not in ("self",):
                            hits.append(f"{f}:{ln+1}: Lambda ändert lokale Variable '{v}': {t.strip()[:80]}")
                i=j if j>i+1 else i+1
            else: i+=1
print("\n".join(hits) if hits else "keine Treffer"); print(len(hits),"Treffer")
