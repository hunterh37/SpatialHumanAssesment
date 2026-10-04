import math, random, os
OUT = os.path.join(os.path.dirname(__file__), "..", "svg")
INK="#1b2430"; PAPER="#f6f4ef"; GRID="#d9d4c7"; MUTE="#8a8f99"
BLUE="#2f6bff"; ORANGE="#ff7a3d"; GOLD="#ffc83d"; TEAL="#14b8a6"; WALL="#ebe7dd"; WALL2="#e3ded2"; FLOOR="#efece4"
FONT="font-family='Helvetica Neue, Helvetica, Arial, sans-serif'"
W,H=1200,800
C30=math.cos(math.radians(30)); S30=0.5

def iso(x,y,z,s=52,cx=600,cy=250):
    return (cx+(x-y)*C30*s, cy+(x+y)*S30*s - z*s)
def pts(ps): return " ".join(f"{a:.1f},{b:.1f}" for a,b in ps)
def poly(ps,fill,stroke=INK,sw=2,extra=""):
    return f"<polygon points='{pts(ps)}' fill='{fill}' stroke='{stroke}' stroke-width='{sw}' stroke-linejoin='round' {extra}/>"
def line(a,b,stroke=INK,sw=2,dash=None,extra=""):
    d=f" stroke-dasharray='{dash}'" if dash else ""
    return f"<line x1='{a[0]:.1f}' y1='{a[1]:.1f}' x2='{b[0]:.1f}' y2='{b[1]:.1f}' stroke='{stroke}' stroke-width='{sw}' stroke-linecap='round'{d} {extra}/>"
def text(x,y,t,size=18,fill=INK,weight=400,anchor="start",extra=""):
    return f"<text x='{x:.1f}' y='{y:.1f}' font-size='{size}' fill='{fill}' font-weight='{weight}' text-anchor='{anchor}' {FONT} {extra}>{t}</text>"
def svg(body,w=W,h=H,bg=PAPER):
    return f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {w} {h}' width='{w}' height='{h}'><rect width='{w}' height='{h}' fill='{bg}'/>{body}</svg>"
def save(name,s):
    open(os.path.join(OUT,name),"w").write(s)

def box(x0,y0,z0,dx,dy,dz,top,side1,side2,**k):
    x1,y1,z1=x0+dx,y0+dy,z0+dz
    P=lambda x,y,z: iso(x,y,z,**k)
    o=poly([P(x0,y0,z1),P(x1,y0,z1),P(x1,y1,z1),P(x0,y1,z1)],top)
    o+=poly([P(x1,y0,z0),P(x1,y1,z0),P(x1,y1,z1),P(x1,y0,z1)],side1)
    o+=poly([P(x0,y1,z0),P(x1,y1,z0),P(x1,y1,z1),P(x0,y1,z1)],side2)
    return o

def room(**k):
    P=lambda x,y,z: iso(x,y,z,**k)
    X,Y,Z=10,9,4.4
    o=poly([P(0,0,0),P(X,0,0),P(X,Y,0),P(0,Y,0)],FLOOR)
    o+=poly([P(0,0,0),P(X,0,0),P(X,0,Z),P(0,0,Z)],WALL)
    o+=poly([P(0,0,0),P(0,Y,0),P(0,Y,Z),P(0,0,Z)],WALL2)
    for i in range(1,10): o+=line(P(i,0,0),P(i,Y,0),GRID,1)
    for j in range(1,9): o+=line(P(0,j,0),P(X,j,0),GRID,1)
    # window on back wall
    o+=poly([P(5.5,0,1.8),P(8.5,0,1.8),P(8.5,0,3.7),P(5.5,0,3.7)],"#dfe8f5")
    o+=line(P(7,0,1.8),P(7,0,3.7),INK,1.5)
    # door on left wall
    o+=poly([P(0,5.6,0),P(0,7.4,0),P(0,7.4,3.6),P(0,5.6,3.6)],"#e6e0d2")
    # sofa
    o+=box(0.2,1.2,0,1.6,3.8,1.0,"#c9d3e3","#b7c3d8","#aab7cd",**k)
    o+=box(0.2,1.2,1.0,0.5,3.8,0.9,"#c9d3e3","#b7c3d8","#aab7cd",**k)
    # table
    o+=box(3.6,2.2,1.3,2.6,1.6,0.18,"#e8d9c0","#d6c3a3","#cbb593",**k)
    for (a,b) in [(3.7,3.6),(6.0,3.6),(6.0,2.3)]:
        o+=box(a,b,0,0.15,0.15,1.3,"#cbb593","#bfa680","#b39a74",**k)
    # shelf on back wall
    o+=box(1.2,0,2.8,3.0,0.5,0.14,"#e8d9c0","#d6c3a3","#cbb593",**k)
    # plant
    o+=box(8.6,0.4,0,0.8,0.8,0.9,"#d8cfc0","#c8bca8","#bcae97",**k)
    cx,cy=P(9.0,0.8,1.5)
    o+=f"<ellipse cx='{cx:.1f}' cy='{cy:.1f}' rx='26' ry='34' fill='#9cc9a5' stroke='{INK}' stroke-width='2'/>"
    return o

def target(x,y,z,color,r=17,label=None,ring=True,**k):
    sx,sy=iso(x,y,z,**k); fx,fy=iso(x,y,0,**k)
    o=f"<ellipse cx='{fx:.1f}' cy='{fy:.1f}' rx='{r*0.9:.1f}' ry='{r*0.45:.1f}' fill='{INK}' opacity='0.12'/>"
    o+=line((fx,fy),(sx,sy+r),MUTE,1.2,"3 5")
    if ring: o+=f"<circle cx='{sx:.1f}' cy='{sy:.1f}' r='{r+9}' fill='none' stroke='{color}' stroke-width='1.5' opacity='0.45'/>"
    o+=f"<circle cx='{sx:.1f}' cy='{sy:.1f}' r='{r}' fill='{color}' stroke='{INK}' stroke-width='2'/>"
    o+=f"<circle cx='{sx-r*0.35:.1f}' cy='{sy-r*0.35:.1f}' r='{r*0.28:.1f}' fill='white' opacity='0.7'/>"
    if label: o+=text(sx,sy+5,label,14,"white",700,"middle")
    return o

def person(x,y,reach_to=None,color=INK,**k):
    fx,fy=iso(x,y,0,**k)
    f=k.get('s',52)/52
    if reach_to: reach_to=(fx+(reach_to[0]-fx)/f, fy+(reach_to[1]-fy)/f)
    return f"<g transform='translate({fx:.1f},{fy:.1f}) scale({f:.3f}) translate({-fx:.1f},{-fy:.1f})'>"+_person(fx,fy,reach_to)+"</g>"
def _person(fx,fy,reach_to):
    hx,hy=fx,fy-205
    o=f"<ellipse cx='{fx:.1f}' cy='{fy:.1f}' rx='34' ry='15' fill='{INK}' opacity='0.15'/>"
    # legs
    o+=f"<path d='M{fx-14},{fy} L{fx-10},{fy-90} M{fx+14},{fy} L{fx+10},{fy-90}' stroke='{INK}' stroke-width='16' stroke-linecap='round' fill='none'/>"
    # torso
    o+=f"<path d='M{fx-26},{fy-92} Q{fx-30},{fy-160} {fx-20},{fy-172} L{fx+20},{fy-172} Q{fx+30},{fy-160} {fx+26},{fy-92} Z' fill='#3a4a63' stroke='{INK}' stroke-width='2'/>"
    # head + headset
    o+=f"<circle cx='{hx}' cy='{hy}' r='22' fill='#d9b99b' stroke='{INK}' stroke-width='2'/>"
    o+=f"<rect x='{hx-20}' y='{hy-10}' width='36' height='16' rx='8' fill='{INK}'/>"
    o+=f"<path d='M{hx-21},{hy-4} Q{hx},{hy-34} {hx+21},{hy-4}' stroke='{MUTE}' stroke-width='4' fill='none'/>"
    # other arm
    o+=f"<path d='M{fx-22},{fy-165} Q{fx-36},{fy-125} {fx-30},{fy-95}' stroke='#3a4a63' stroke-width='12' stroke-linecap='round' fill='none'/>"
    if reach_to:
        tx,ty=reach_to; sx,sy=fx+20,fy-165
        mx,my=(sx+tx)/2+10,(sy+ty)/2+25
        o+=f"<path d='M{sx},{sy} Q{mx:.1f},{my:.1f} {tx:.1f},{ty:.1f}' stroke='#3a4a63' stroke-width='12' stroke-linecap='round' fill='none'/>"
        o+=f"<circle cx='{tx:.1f}' cy='{ty:.1f}' r='7' fill='#d9b99b' stroke='{INK}' stroke-width='2'/>"
    return o

def gaze(x,y,tx,ty,**k):
    fx,fy=iso(x,y,0,**k); hx,hy=fx,fy-205*k.get('s',52)/52
    return line((hx+18,hy),(tx,ty),BLUE,1.5,"2 6")

def title(t,sub,num):
    return (text(48,64,f"FIG {num:02d}",14,MUTE,700,extra="letter-spacing='3'")+
            text(48,100,t,32,INK,700)+text(48,130,sub,17,MUTE))

def legend_item(x,y,color,label):
    return f"<circle cx='{x}' cy='{y}' r='9' fill='{color}' stroke='{INK}' stroke-width='1.5'/>"+text(x+18,y+6,label,16)

def hand_skeleton(ox,oy,s=1.0,tip_target=True):
    # 2D hand joint skeleton, index pointing up-right
    wrist=(0,0)
    chains={
     "thumb":[(-30,-20),(-55,-45),(-72,-70),(-84,-92)],
     "index":[(-12,-70),(-4,-115),(4,-150),(10,-180)],
     "middle":[(12,-72),(20,-110),(24,-130),(26,-146)],
     "ring":[(32,-66),(42,-98),(44,-114),(44,-128)],
     "little":[(48,-56),(62,-82),(64,-96),(64,-108)],
    }
    T=lambda p:(ox+p[0]*s,oy+p[1]*s)
    o=""
    # palm silhouette
    o+=f"<path d='M{T((-40,10))[0]},{T((-40,10))[1]} Q{T((-60,-40))[0]},{T((-60,-40))[1]} {T((-14,-74))[0]},{T((-14,-74))[1]} L{T((50,-60))[0]},{T((50,-60))[1]} Q{T((66,-10))[0]},{T((66,-10))[1]} {T((40,14))[0]},{T((40,14))[1]} Z' fill='#e9ddd0' stroke='none'/>"
    for name,ch in chains.items():
        prev=wrist
        for p in ch:
            o+=line(T(prev),T(p),INK,3*s)
            prev=p
    for name,ch in chains.items():
        for i,p in enumerate(ch):
            last=i==len(ch)-1
            col=TEAL if (name=="index" and last) else "white"
            r=(9 if (name=="index" and last) else 5)*s
            o+=f"<circle cx='{T(p)[0]:.1f}' cy='{T(p)[1]:.1f}' r='{r:.1f}' fill='{col}' stroke='{INK}' stroke-width='{2*s:.1f}'/>"
    o+=f"<circle cx='{ox}' cy='{oy}' r='{7*s}' fill='white' stroke='{INK}' stroke-width='{2*s}'/>"
    return o, T((10,-180))

# ---------- FIG 1: reaction task ----------
def fig1():
    random.seed(4)
    b=title("Simple reaction","A target spawns somewhere in the real room. Reach it, touch it with a fingertip.",1)
    k=dict(s=42,cx=470,cy=330)
    b+=room(**k)
    tgts=[(2.0,0.6,3.4),(8.8,3.0,2.6),(1.0,7.5,2.2)]
    for t in tgts: b+=target(*t,"#b9c7e6",14,ring=False,**k)
    active=(5.2,5.0,2.9)
    ax,ay=iso(*active,**k)
    b+=f"<circle cx='{ax:.1f}' cy='{ay:.1f}' r='40' fill='none' stroke='{BLUE}' stroke-width='2' stroke-dasharray='4 6'/>"
    b+=f"<circle cx='{ax:.1f}' cy='{ay:.1f}' r='54' fill='none' stroke='{BLUE}' stroke-width='1' opacity='0.4'/>"
    b+=person(6.8,7.6,reach_to=(ax+8,ay+12),**k)
    b+=gaze(6.8,7.6,ax,ay,**k)
    b+=target(*active,BLUE,20,**k)
    b+=text(ax+62,ay-30,"active target",15,BLUE,700)
    b+=text(ax+62,ay-12,"spawn at t = 0",14,MUTE)
    b+=text(iso(1.0,7.5,2.2,**k)[0]-20,iso(1.0,7.5,2.2,**k)[1]-28,"previous spawns",13,MUTE,anchor="middle")
    # inset: fingertip collision
    ix,iy,iw,ih=880,170,280,360
    b+=f"<rect x='{ix}' y='{iy}' width='{iw}' height='{ih}' rx='18' fill='white' stroke='{INK}' stroke-width='2'/>"
    b+=text(ix+20,iy+34,"COLLISION",13,MUTE,700,extra="letter-spacing='2'")
    b+=text(ix+20,iy+56,"index tip joint vs target",15)
    hs,tip=hand_skeleton(ix+120,iy+320,1.0)
    tx,ty=tip[0]+26,tip[1]-14
    b+=f"<circle cx='{tx}' cy='{ty}' r='34' fill='{BLUE}' opacity='0.9' stroke='{INK}' stroke-width='2'/>"
    b+=f"<circle cx='{tx}' cy='{ty}' r='48' fill='none' stroke='{BLUE}' stroke-width='1.5' stroke-dasharray='3 5'/>"
    b+=hs
    b+=text(ix+iw-16,iy+ih-20,"hit when d(tip, center) &lt; r",13,MUTE,anchor="end")
    b+=line((ax+20,ay-10),(ix,iy+150),MUTE,1,"2 4")
    # caption strip
    b+=legend_item(60,775,BLUE,"active")+legend_item(170,775,"#b9c7e6","earlier trials")+text(340,781,"dashed lines drop to the floor to show height",15,MUTE)
    save("fig01_reaction.svg",svg(b))

# ---------- FIG 2: choice ----------
def fig2():
    b=title("Choice reaction","Several targets appear at once. Touch only the blue ones.",2)
    k=dict(s=42,cx=470,cy=330)
    b+=room(**k)
    blues=[(4.5,4.5,3.1),(1.8,0.6,3.5),(8.6,2.5,2.4)]
    oranges=[(6.6,1.4,3.6),(1.2,6.8,2.5),(3.4,6.4,1.5)]
    for t in oranges: b+=target(*t,ORANGE,16,**k)
    for t in blues: b+=target(*t,BLUE,18,**k)
    a=iso(*blues[0],**k)
    b+=person(6.8,7.6,reach_to=(a[0]+6,a[1]+12),**k)
    for t in blues:
        x,y=iso(*t,**k); b+=f"<path d='M{x-7},{y} l5,6 l10,-12' stroke='white' stroke-width='3.5' fill='none' stroke-linecap='round'/>"
    for t in oranges:
        x,y=iso(*t,**k); b+=f"<path d='M{x-6},{y-6} l12,12 M{x+6},{y-6} l-12,12' stroke='white' stroke-width='3.5' stroke-linecap='round'/>"
    # rule card
    ix,iy=880,180
    b+=f"<rect x='{ix}' y='{iy}' width='280' height='300' rx='18' fill='white' stroke='{INK}' stroke-width='2'/>"
    b+=text(ix+20,iy+34,"RULE",13,MUTE,700,extra="letter-spacing='2'")
    b+=f"<circle cx='{ix+48}' cy='{iy+82}' r='20' fill='{BLUE}' stroke='{INK}' stroke-width='2'/>"+text(ix+84,iy+80,"touch",20,INK,700)+text(ix+84,iy+100,"counts as a hit",14,MUTE)
    b+=f"<circle cx='{ix+48}' cy='{iy+150}' r='20' fill='{ORANGE}' stroke='{INK}' stroke-width='2'/>"+text(ix+84,iy+148,"ignore",20,INK,700)+text(ix+84,iy+168,"touching = commission error",14,MUTE)
    b+=line((ix+20,iy+200),(ix+260,iy+200),GRID,1.5)
    b+=text(ix+20,iy+230,"missed blue after 2.0 s",15)+text(ix+20,iy+250,"= omission error",14,MUTE)
    b+=text(ix+20,iy+280,"ratio blue : orange varies",14,MUTE)
    b+=legend_item(60,775,BLUE,"go")+legend_item(140,775,ORANGE,"no-go")
    save("fig02_choice.svg",svg(b))

# ---------- FIG 3: Corsi ----------
def cube(x,y,z,lit,n=None,sz=0.6,**k):
    if lit: top,s1,s2=GOLD,"#f0b020","#e09e10"
    else: top,s1,s2="#ffffff","#e2e5ea","#d3d7de"
    o=box(x,y,z,sz,sz,sz,top,s1,s2,**k)
    if lit:
        cx,cy=iso(x+sz/2,y+sz/2,z+sz,**k)
        o=f"<circle cx='{cx:.1f}' cy='{cy-6:.1f}' r='38' fill='{GOLD}' opacity='0.25'/>"+o
    if n is not None:
        cx,cy=iso(x+sz/2,y+sz/2,z+sz+0.9,**k)
        o+=f"<circle cx='{cx:.1f}' cy='{cy:.1f}' r='14' fill='{INK}'/>"+text(cx,cy+5,str(n),15,"white",700,"middle")
    return o
def fig3():
    b=title("3D Corsi blocks","Cubes on real surfaces light in sequence. The user repeats the order by touch.",3)
    k=dict(s=42,cx=470,cy=330)
    b+=room(**k)
    cubes=[(4.0,2.5,1.48),(5.4,3.0,1.48),(1.6,0.0,2.94),(3.4,0.0,2.94),(0.8,2.0,1.0),(0.8,3.8,1.0),(7.8,5.5,0),(5.0,7.0,0),(9.0,1.0,0)]
    seq=[2,0,6,4,8]
    path=[]
    for i,c in enumerate(cubes):
        n=seq.index(i)+1 if i in seq else None
        b+=cube(*c,lit=(n==3),n=n,**k)
    for i in seq:
        x,y,z=cubes[i]; path.append(iso(x+0.3,y+0.3,z+0.6+0.9,**k))
    d="M"+" L".join(f"{p[0]:.1f},{p[1]:.1f}" for p in path)
    b+=f"<path d='{d}' fill='none' stroke='{INK}' stroke-width='1.5' stroke-dasharray='5 6' opacity='0.55'/>"
    # phase panel
    ix,iy=880,170
    b+=f"<rect x='{ix}' y='{iy}' width='280' height='380' rx='18' fill='white' stroke='{INK}' stroke-width='2'/>"
    b+=text(ix+20,iy+34,"TRIAL",13,MUTE,700,extra="letter-spacing='2'")
    steps=[("1","Show","cubes light one at a time, 1 s each"),("2","Hold","short blank, cubes all dim"),("3","Repeat","user touches cubes in order"),("4","Adapt","2 correct: span +1. 2 wrong: stop")]
    for j,(n,h,s) in enumerate(steps):
        y=iy+80+j*72
        b+=f"<circle cx='{ix+38}' cy='{y}' r='15' fill='{GOLD if j==0 else INK}'/>"+text(ix+38,y+5,n,14,INK if j==0 else "white",700,"middle")
        b+=text(ix+66,y+2,h,18,INK,700)+text(ix+66,y+22,s,13,MUTE)
    b+=line((ix+20,iy+330),(ix+260,iy+330),GRID,1.5)
    b+=text(ix+20,iy+360,"Corsi span = longest correct run",15,INK,700)
    # sequence strip
    sx=60
    b+=text(sx,762,"sequence",14,MUTE,700)
    for j in range(5):
        x=sx+100+j*56
        b+=f"<rect x='{x}' y='745' width='38' height='38' rx='6' fill='{GOLD if j==2 else 'white'}' stroke='{INK}' stroke-width='2'/>"+text(x+19,770,str(j+1),15,INK,700,"middle")
        if j<4: b+=line((x+42,764),(x+52,764),MUTE,2)
    b+=text(sx+400,770,"step 3 lit now, span length 5",15,MUTE)
    save("fig03_corsi.svg",svg(b))

# ---------- FIG 4: metrics ----------
def fig4():
    b=title("Measured features","Every trial yields timing and accuracy. Reach time is split by eccentricity.",4)
    tiles=[("Reaction time","312","ms","onset to hand start",BLUE),("Movement time","486","ms","hand start to touch",TEAL),("Error rate","4.2","%","commission + omission",ORANGE),("Corsi span","6","items","longest correct run",GOLD)]
    for i,(h,v,u,s,c) in enumerate(tiles):
        x=48+i*282; y=170
        b+=f"<rect x='{x}' y='{y}' width='262' height='150' rx='16' fill='white' stroke='{INK}' stroke-width='2'/>"
        b+=f"<rect x='{x}' y='{y}' width='8' height='150' rx='4' fill='{c}'/>"
        b+=text(x+26,y+36,h.upper(),13,MUTE,700,extra="letter-spacing='1.5'")
        b+=text(x+26,y+96,v,52,INK,700)+text(x+26+len(v)*30+8,y+96,u,18,MUTE)
        b+=text(x+26,y+128,s,14,MUTE)
    # timeline
    tx,ty=48,370
    b+=f"<rect x='{tx}' y='{ty}' width='540' height='380' rx='16' fill='white' stroke='{INK}' stroke-width='2'/>"
    b+=text(tx+24,ty+38,"ONE TRIAL",13,MUTE,700,extra="letter-spacing='2'")
    y0=ty+200; x0=tx+50; x1=x0+130; x2=x1+190; x3=x2+40
    b+=line((x0,y0),(tx+500,y0),INK,2)
    b+=f"<rect x='{x0}' y='{y0-26}' width='{x1-x0}' height='26' fill='{BLUE}' opacity='0.85'/>"
    b+=f"<rect x='{x1}' y='{y0-26}' width='{x2-x1}' height='26' fill='{TEAL}' opacity='0.85'/>"
    for x,l1,l2 in [(x0,"target","onset"),(x1,"hand","velocity &gt; thr"),(x2,"fingertip","contact")]:
        b+=line((x,y0-60),(x,y0+14),INK,1.5)+text(x,y0+40,l1,14,INK,700,"middle")+text(x,y0+58,l2,13,MUTE,anchor="middle")
    b+=text((x0+x1)/2,y0-36,"RT",16,BLUE,700,"middle")+text((x1+x2)/2,y0-36,"MT",16,TEAL,700,"middle")
    # velocity profile
    vp=[]
    for i in range(61):
        t=i/60; x=x1+t*(x2-x1); v=math.sin(math.pi*t)**2
        vp.append((x,y0-80-v*60))
    b+=f"<path d='M{x0},{y0-80} L{x1},{y0-80} "+" ".join(f"L{p[0]:.1f},{p[1]:.1f}" for p in vp)+f" L{tx+500},{y0-80}' fill='none' stroke='{INK}' stroke-width='2'/>"
    b+=text(tx+500,y0-90,"hand speed",13,MUTE,anchor="end")
    b+=text(tx+24,ty+350,"RT + MT = total response time",14,MUTE)
    # eccentricity bars
    bx,by=612,370
    b+=f"<rect x='{bx}' y='{by}' width='540' height='380' rx='16' fill='white' stroke='{INK}' stroke-width='2'/>"
    b+=text(bx+24,by+38,"REACH TIME BY ECCENTRICITY",13,MUTE,700,extra="letter-spacing='2'")
    cats=[("0–30°",640),("30–60°",720),("60–90°",830),("90°+",1010)]
    base=by+320; scale=0.2
    for i,(c,v) in enumerate(cats):
        x=bx+60+i*112; h=v*scale
        b+=f"<rect x='{x}' y='{base-h:.1f}' width='70' height='{h:.1f}' rx='6' fill='{BLUE}' opacity='{0.35+i*0.2:.2f}'/>"
        b+=text(x+35,base-h-10,f"{v}",15,INK,700,"middle")+text(x+35,base+24,c,14,MUTE,anchor="middle")
    b+=line((bx+44,base),(bx+510,base),INK,2)
    b+=text(bx+510,by+60,"ms, illustrative",13,MUTE,anchor="end")
    save("fig04_metrics.svg",svg(b))

# ---------- FIG 5: aging ----------
def fig5():
    b=title("Why it tracks age","Processing speed and spatial working memory fall steadily from early adulthood.",5)
    px,py,pw,ph=120,190,980,480
    b+=f"<rect x='{px-70}' y='{py-30}' width='{pw+110}' height='{ph+110}' rx='16' fill='white' stroke='{INK}' stroke-width='2'/>"
    X=lambda a: px+(a-20)/60*pw
    Y=lambda v: py+ph-(v/100)*ph
    for a in range(20,81,10):
        b+=line((X(a),py),(X(a),py+ph),GRID,1)+text(X(a),py+ph+28,str(a),15,MUTE,anchor="middle")
    for v in range(0,101,25):
        b+=line((px,Y(v)),(px+pw,Y(v)),GRID,1)
    b+=text(px+pw/2,py+ph+60,"age (years)",15,MUTE,anchor="middle")
    b+=text(px-40,py+ph/2,"relative performance",15,MUTE,anchor="middle",extra=f"transform='rotate(-90 {px-40} {py+ph/2})'")
    def curve(f,col):
        ps=[(X(a),Y(f(a))) for a in range(20,81)]
        band="M"+" L".join(f"{x:.1f},{y-16:.1f}" for x,y in ps)+" L"+" L".join(f"{x:.1f},{y+16:.1f}" for x,y in reversed(ps))+" Z"
        return f"<path d='{band}' fill='{col}' opacity='0.12'/>"+f"<path d='M"+" L".join(f"{x:.1f},{y:.1f}" for x,y in ps)+f"' fill='none' stroke='{col}' stroke-width='4' stroke-linecap='round'/>"
    sp=lambda a: 90-0.9*(a-20)-0.004*(a-20)**2
    wm=lambda a: 82-0.55*(a-20)-0.006*(a-20)**2
    b+=curve(sp,BLUE)+curve(wm,GOLD)
    b+=text(X(66),Y(sp(66))-26,"processing speed",17,BLUE,700)
    b+=text(X(60),Y(wm(60))-26,"spatial working memory",17,"#c48a00",700)
    # sample person dot
    a=47; b+=f"<circle cx='{X(a)}' cy='{Y(sp(a))+18}' r='10' fill='{INK}'/>"
    b+=line((X(a),Y(sp(a))+18),(X(a),py+ph),INK,1.5,"3 4")
    b+=text(X(a)+16,Y(sp(a))+46,"one session",15,INK,700)+text(X(a)+16,Y(sp(a))+64,"maps to a predicted age",14,MUTE)
    b+=text(px+pw,py-6,"shape illustrative, not fitted data",13,MUTE,anchor="end")
    save("fig05_aging.svg",svg(b))

# ---------- FIG 6: protocol + demo ----------
def fig6():
    b=title("Session and demo view","A fixed warm-up absorbs practice effects. The audience watches a mirrored view.",6)
    blocks=[("Familiarize","8 trials","not scored","#c9ced6",150),("Simple RT","30 trials","scored",BLUE,230),("Choice RT","40 trials","scored",ORANGE,260),("Corsi 3D","span 2 → 9","scored",GOLD,240)]
    x=60; y=190
    b+=text(60,180,"SESSION, ABOUT 6 MIN",13,MUTE,700,extra="letter-spacing='2'")
    for i,(h,n,s,c,w) in enumerate(blocks):
        dash="stroke-dasharray='6 5'" if i==0 else ""
        b+=f"<rect x='{x}' y='{y+16}' width='{w}' height='110' rx='14' fill='{c}' fill-opacity='{0.18 if i else 0.4}' stroke='{INK}' stroke-width='2' {dash}/>"
        b+=text(x+18,y+52,h,19,INK,700)+text(x+18,y+78,n,15,MUTE)+text(x+18,y+106,s.upper(),12,INK if i else MUTE,700,extra="letter-spacing='1.5'")
        if i<3: b+=f"<path d='M{x+w+6},{y+71} l14,0 m-6,-6 l6,6 l-6,6' stroke='{INK}' stroke-width='2' fill='none'/>"
        x+=w+26
    b+=f"<path d='M60,{y+142} L210,{y+142}' stroke='{MUTE}' stroke-width='1.5'/>"+text(60,y+164,"scores start after this line",14,MUTE)
    # demo: headset user and mirrored screen
    k=dict(s=34,cx=330,cy=470)
    P=lambda x,y,z: iso(x,y,z,**k)
    b+=poly([P(0,0,0),P(7,0,0),P(7,6,0),P(0,6,0)],FLOOR)
    for i in range(1,7): b+=line(P(i,0,0),P(i,6,0),GRID,1)
    for j in range(1,6): b+=line(P(0,j,0),P(7,j,0),GRID,1)
    t1=(2.5,1.5,3.6); a=iso(*t1,**k)
    b+=target(*t1,BLUE,16,**k)
    b+=target(5.2,1.2,2.8,ORANGE,13,**k)
    b+=person(4.4,4.4,reach_to=(a[0]+6,a[1]+10),**k)
    # stream arrow
    b+=f"<path d='M560,560 C640,520 700,520 760,540' stroke='{INK}' stroke-width='2' fill='none' stroke-dasharray='6 6'/>"
    b+=f"<path d='M752,532 l10,8 l-12,4' stroke='{INK}' stroke-width='2' fill='none'/>"
    b+=text(660,505,"mirror stream",14,MUTE,700,"middle")
    # screen
    sx,sy,sw,sh=780,400,380,240
    b+=f"<rect x='{sx}' y='{sy}' width='{sw}' height='{sh}' rx='14' fill='{INK}'/>"
    b+=f"<rect x='{sx+12}' y='{sy+12}' width='{sw-24}' height='{sh-24}' rx='6' fill='#24324a'/>"
    b+=f"<rect x='{sx+sw/2-40}' y='{sy+sh}' width='80' height='30' fill='{INK}'/><rect x='{sx+sw/2-90}' y='{sy+sh+30}' width='180' height='10' rx='5' fill='{INK}'/>"
    # screen contents
    b+=f"<circle cx='{sx+150}' cy='{sy+110}' r='26' fill='{BLUE}' stroke='white' stroke-width='2'/>"
    b+=f"<circle cx='{sx+260}' cy='{sy+150}' r='18' fill='{ORANGE}' stroke='white' stroke-width='2'/>"
    b+=f"<path d='M{sx+90},{sy+228} Q{sx+110},{sy+160} {sx+142},{sy+124}' stroke='#d9b99b' stroke-width='12' stroke-linecap='round' fill='none'/>"
    b+=text(sx+28,sy+44,"RT 298 ms",16,"white",700)+text(sx+sw-28,sy+44,"SPAN 6",16,GOLD,700,"end")
    b+=f"<rect x='{sx+28}' y='{sy+196}' width='{sw-56}' height='8' rx='4' fill='#3b4b66'/><rect x='{sx+28}' y='{sy+196}' width='{(sw-56)*0.62:.0f}' height='8' rx='4' fill='{TEAL}'/>"
    b+=text(sx+sw/2,sy+sh+70,"audience display",15,MUTE,anchor="middle")
    save("fig06_session.svg",svg(b))

# ---------- cover art ----------
def cover():
    w,h=1200,900
    k=dict(s=58,cx=600,cy=300)
    b=room(**k)
    b+=cube(4.0,2.5,1.48,True,None,**k)+cube(1.6,0.0,2.94,False,None,**k)+cube(7.8,5.5,0,False,None,**k)+cube(0.8,3.8,1.0,True,None,**k)
    for t,c in [((6.4,1.6,3.4),BLUE),((2.6,6.2,2.6),ORANGE),((8.8,3.2,2.2),BLUE)]: b+=target(*t,c,18,**k)
    a=iso(5.0,5.2,3.0,**k)
    b+=target(5.0,5.2,3.0,BLUE,22,**k)
    b+=person(7.0,7.8,reach_to=(a[0]+8,a[1]+14),**k)
    save("cover.svg",svg(b,w,h))

for f in (fig1,fig2,fig3,fig4,fig5,fig6,cover): f()
print("ok")
