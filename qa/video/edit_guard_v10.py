"""Render recorded gameplay: a competent shared AI, then Jev's additional choice."""
from pathlib import Path
from functools import lru_cache
import json, math, bisect, subprocess, sys
from PIL import Image, ImageDraw, ImageFont
P=Path(__file__).resolve().parent
Q=P/'guard-v10-release'
data=json.loads((Q/'recording.json').read_text(encoding='utf-8'))
W,H,FPS=1600,900,20
INK='#163345'; ORANGE='#d35b22'; RED='#c72c37'; BLUE='#0878bf'; GREEN='#19715f'; BG='#f3f5f2'
fonts={n:ImageFont.truetype('C:/Windows/Fonts/YuGothB.ttc',n) for n in [20,23,25,28,30,34,40,44,48,56,68]}
results={r['mode']:r for r in data['passes']}
times={m:[f['time'] for f in fs] for m,fs in data['frames'].items()}
DURATION=36

def txt(d,xy,s,size=28,fill=INK):d.text(xy,s,font=fonts[size],fill=fill)
def pt(p):return (70+(p[0]+15)*31,222+(p[1]+10)*23.5)
def sample(m,t):
 i=max(0,min(len(times[m])-1,bisect.bisect_right(times[m],t)-1));return i,data['frames'][m][i]
def actual(m,i):
 return Image.open(Q/m/f'{i:05d}.jpg').convert('RGB').crop((90,180,1060,705))
def events(m,k):return [e for e in results[m]['objective_events'] if e['kind']==k]
def trail(d,m,key,t,start,colour,width=5):
 points=[]
 for f in data['frames'][m]:
  if start<=f['time']<=t:
   p=f['player'] if key=='player' else next(g['pos'] for g in f['guards'] if g['id']==key)
   points.append(pt(p))
 if len(points)>1:d.line(points,fill=colour,width=width,joint='curve')
def box(d,pos,label,below=False):
 x,y=pt(pos);d.rounded_rectangle((x-34,y-32,x+34,y+32),8,outline=RED,width=5)
 tw=d.textbbox((0,0),label,font=fonts[23])[2]+20
 lx=max(42,min(1020-tw,x-tw/2));ly=min(700,y+39) if below else max(214,y-78)
 d.rounded_rectangle((lx,ly,lx+tw,ly+36),6,fill=RED);txt(d,(lx+10,ly),label,23,'white')
def diagram(m,f,t,focus=True):
 im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
 d.rounded_rectangle((30,150,1035,790),20,fill='#e5eeef')
 txt(d,(60,164),'西',28);txt(d,(842,164),'東・保管庫',28)
 for x,y,w,h in data['obstacles']:
  d.rectangle((*pt((x,y)),*pt((x+w,y+h))),fill='#9caeb6',outline='#8a9da6',width=2)
 txt(d,(440,460),'中央の建物',25,'#334f5b')
 for p in [(-11,8),(11,8)]:
  x,y=pt(p);d.rectangle((x-32,y-20,x+32,y+20),fill='#bfd5b1');txt(d,(x-25,y-16),'出口',23,GREEN)
 x,y=pt((10,-6));d.rectangle((x-15,y-11,x+15,y+11),fill='#aa841c');txt(d,(x-37,y-44),'ケース',23)
 for p in f['smokes']:
  x,y=pt(p);d.ellipse((x-74,y-56,x+74,y+56),fill='#c7dce2');txt(d,(x-28,y-14),'煙幕',20,'#476370')
 for p in f['devices']:
  x,y=pt(p);d.ellipse((x-13,y-13,x+13,y+13),fill='#b89017',outline='white',width=2)
  txt(d,(max(44,x-43),min(705,y+20)),'音の装置',20,'#856012')
 trail(d,m,'player',t,max(0,t-3.5),'#68b3dc',4)
 if t<5:
  for key in ['A','B']:trail(d,m,key,t,0,ORANGE,5)
 elif t>=11:
  trail(d,m,'A',t,11,RED,7);trail(d,m,'B',t,11,'#de9976',4)
 for g in f['guards']:
  x,y=pt(g['pos']);fx,fy=g['face'];d.line((x,y,x+fx*37,y+fy*29),fill=ORANGE,width=5)
  close=[h for h in f['guards'] if h['id']!=g['id'] and math.dist(pt(h['pos']),(x,y))<44]
  if close:
   mate=close[0]
   if g['id']<mate['id']:
    mx,my=pt(mate['pos']);cx,cy=(x+mx)/2,(y+my)/2
    d.rounded_rectangle((cx-40,cy-23,cx+40,cy+23),20,fill=ORANGE,outline='white',width=3)
    txt(d,(cx-32,cy-17),g['id']+'・'+mate['id'],25,'white')
  else:
   d.ellipse((x-23,y-23,x+23,y+23),fill=ORANGE,outline='white',width=3);txt(d,(x-11,y-22),g['id'],30,'white')
  if g['fire']>.12 and g['direct_seen_at']>=t-.08:d.line((x,y,*pt(f['player'])),fill=RED,width=3)
 x,y=pt(f['player']);d.polygon([(x,y-19),(x-17,y+14),(x+17,y+14)],fill=BLUE,outline='white',width=3)
 for e in events(m,'shot'):
  if e['time']-.15<=t<=e['time']+2.5:
   x,y=pt(e['position']);d.ellipse((x-39,y-33,x+39,y+33),outline=RED,width=5)
   txt(d,(max(45,x-100),y-76),'ここで発砲',28,RED)
   # This flash stays at the recorded shot origin, never at the later player position.
   d.line((x-27,y,x+27,y),fill=RED,width=3);d.line((x,y-24,x,y+24),fill=RED,width=3)
 if focus:
  gs={g['id']:g for g in f['guards']}
  if t<1.4:box(d,gs['A']['pos'],'Aが発見')
  elif t<4:box(d,gs['B']['pos'],'Bも連携',True)
  elif 5.1<t<6.4:box(d,gs['C']['pos'],'Cからも目撃')
  elif 11<=t<contact_time(m):
   box(d,gs['A']['pos'],('A・B：西へ調査' if math.dist(gs['A']['pos'],gs['B']['pos'])<1.5 else 'A：西へ援護') if m=='rules' else ('A：作戦を見直し中' if t<assist_time() else 'A：東の警戒'))
  elif t>=contact_time(m) and m=='rules':box(d,gs['C']['pos'],'Cが再発見')
  if m=='jev' and t>=contact_time(m):box(d,gs['A']['pos'],'Aがここで再発見')
 txt(d,(58,745),'青▲：プレイヤー　 橙●：敵A・B・C　 線：通った道',25)
 return im

def contact_time(m):
 return next(e['time'] for e in events(m,'contact') if e['time']>11 and e.get('guard')==('A' if m=='jev' else 'C'))

def assist_time():
 return next(e['time'] for e in results['jev']['decisions'] if e['time']>10 and e.get('phase')=='assist' and e['choice']=='counter_watch')
def wording(m,t):
 if t<5:return '煙幕で視界を切る。A・Bは最後に見た場所を捜索。',['まず両方式とも同じ対応','A：発見して追跡','B：連携して移動','C：保管庫を守る']
 if t<7:return '東でCにも見つかる。仲間に無線で伝わる。',['保管庫へ向かう途中','東でも姿を見られた','再び煙幕で視界を切る']
 if t<9.5:return 'ここで発砲。銃声の場所も敵に伝わる。',['赤い印が発砲した場所','プレイヤーは西へ移動','敵は東の情報を覚えている']
 if t<11:return '建物を回って西へ。東の目撃情報は残っている。',['敵の視界から離れたあと','西でもう一度、音を出す']
 if m=='rules':
  if t>=contact_time(m):return '保管庫前のCが再発見。通常AIも侵入を止める。',['A・B：西から応援へ戻る','C：保管庫の前で発見','ケースには届かない']
  return '通常AI：援護をつけて、西の音を調べる。',['A：援護に向かう','B：援護を待って調査','C：保管庫を警備']
 if t<assist_time():return '通常AIがすぐ対応。その間にJevへ問い合わせ。',['まず同じ通常AIが動く','Jevの返答待ちでも','敵は止まらない']
 if t>=contact_time(m):return '東に残ったAが、保管庫の手前で再発見。',['A：東の経路で発見','B：西側から合流へ','C：保管庫を警備']
 return 'Jev：Aを東に残し、Bに西を見張らせる。',['Jevに渡した情報','東で目撃・銃声の報告','そのあと、西でまた物音','→ 東西に分かれて警戒']

def split():
 im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
 txt(d,(45,30),'両方とも侵入を止めた。違いは、途中の配置。',48)
 for m,x in [('rules',35),('jev',825)]:
  _,f=sample(m,14);part=diagram(m,f,14).crop((30,150,1035,790)).resize((740,472),Image.Resampling.LANCZOS);im.paste(part,(x,200))
  txt(d,(x+10,140),'通常AI' if m=='rules' else '同じAI ＋ Jev',40,GREEN)
  txt(d,(x+10,690),'A・Bは西へ。Cが保管庫を守る。' if m=='rules' else 'Aは東を警戒。Bは西、Cは保管庫。',30)
  txt(d,(x+10,741),f"この操作では {results[m]['duration']:.1f}秒でプレイヤーを撃破",28)
 txt(d,(45,825),'Jevが変えるのは作戦の選択。移動・視界・無線・射撃は、同じゲームAI。',30)
 return im

def render(t):
 divider=21<=t<23;ending=t>=31
 if t<11:m='rules';st=t
 elif t<13:m='rules';st=11.05
 elif t<21:m='rules';st=min(11+t-13,results['rules']['duration'])
 else:m='jev';st=min(11+max(0,t-23),results['jev']['duration'])
 i,f=sample(m,st);im=diagram(m,f,st);d=ImageDraw.Draw(im);title,lines=wording(m,st)
 if 11<=t<13:title='西でまた物音。東の目撃・銃声も、まだ残っている。';lines=['ここが作戦の分かれ目','通常AIとJev追加で','同じ情報を受け取る']
 txt(d,(35,14),'RELAY / '+('ここまでは両方同じ動き' if t<11 else '通常AI' if m=='rules' else '同じAI ＋ Jev'),28,GREEN)
 txt(d,(35,60),title,40)
 txt(d,(1290,19),f"ゲーム内 {f['time']:04.1f} 秒",23)
 txt(d,(1070,158),'敵は何をする？',30,GREEN)
 for j,line in enumerate(lines):txt(d,(1070,216+j*49),line,28)
 txt(d,(1070,435),f"プレイヤーの耐久：{int(f['player_hp'])} / 100",25)
 txt(d,(1070,479),'実画面・図と同じ時刻',23)
 txt(d,(35,818),'目的：保管庫のケースを回収して、南の出口から脱出',28)
 txt(d,(35,862),'通常の耐久で収録／敵の能力・プレイヤーの操作は両方式で共通',23,'#536b77')
 image=actual(m,i)
 if t<3:
  im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
  txt(d,(65,27),'保管庫のケースを取り、出口へ。でも、すぐ見つかる。',44)
  txt(d,(65,819),'まず通常AI。その後、同じAIにJevを足して比べます。',34)
  x,y,w=200,135,1200
 else:
  u=max(0,min(1,(t-3)/.7));u=u*u*(3-2*u);x=round(200+870*u);y=round(135+390*u);w=round(1200-700*u)
 im.paste(image.resize((w,round(w*525/970)),Image.Resampling.LANCZOS),(x,y));d=ImageDraw.Draw(im);d.rectangle((x,y,x+w,y+round(w*525/970)),outline='#526c79',width=2)
 if divider:
  im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im);txt(d,(100,240),'同じAIに、Jevを追加',68);txt(d,(105,380),'11秒の判断から、もう一度。',48);txt(d,(105,500),'今度は、Aがどこへ向かうかに注目。',40)
 if ending:im=split()
 return im,{'output_time':t,'mode':m,'sample':i,'simulation_time':f['time'],'divider':divider,'ending':ending,'caption':title}

if __name__=='__main__':
 for t in [0,3.4,5.7,7.5,11.5,16,20,22,24,26,29,33]:render(t)[0].save(P/f'guard-v10-check-{t:04.1f}.jpg',quality=94)
 split().save(P/'guard-v10-poster.jpg',quality=95)
 if '--stills' in sys.argv:raise SystemExit(0)
 out=P/'RELAY-Jev-guard-v10.mp4'
 proc=subprocess.Popen(['ffmpeg','-y','-v','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(out)],stdin=subprocess.PIPE)
 timeline=[]
 for i in range(DURATION*FPS):
  im,meta=render(i/FPS);timeline.append(meta);proc.stdin.write(im.tobytes())
 proc.stdin.close()
 if proc.wait():raise SystemExit('Encoding failed')
 (P/'guard-v10-timeline.json').write_text(json.dumps(timeline,ensure_ascii=False,indent=2),encoding='utf-8')
 print(out)
