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
DURATION=0

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
  if e['time']<=t<=e['time']+2.5:
   x,y=pt(e['position']);d.ellipse((x-39,y-33,x+39,y+33),outline=RED,width=5)
   txt(d,(max(45,x-100),y-76),'ここで発砲',28,RED)
   # This flash stays at the recorded shot origin, never at the later player position.
   d.line((x-27,y,x+27,y),fill=RED,width=3);d.line((x,y-24,x,y+24),fill=RED,width=3)
 if focus:
  gs={g['id']:g for g in f['guards']}
  if events(m,'contact')[0]['time']<=t<1.4:box(d,gs['A']['pos'],'Aが発見')
  elif 1.4<=t<4:box(d,gs['B']['pos'],'Bも連携',True)
  elif 5.22<=t<6.4:box(d,gs['C']['pos'],'Cからも目撃')
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

# Every pass starts at precisely the same captured, unadvanced scene.
import copy
initial=json.loads((P/'guard-v11-start.json').read_text(encoding='utf-8'))
assert initial['time']==0
start_frame=copy.deepcopy(data['frames']['jev'][0])
start_frame.update(time=0,player=initial['player'],player_hp=100,smokes=[],devices=[])
for guard in start_frame['guards']:
 guard.update(next(g for g in initial['guards'] if g['id']==guard['id']))
 guard.update(fire=0,direct_seen_at=-100)
start_image=Image.open(P/'guard-v11-start.jpg').convert('RGB').crop((90,180,1060,705))

segments=[]
def segment(kind,duration,mode=None,start=0,speed=0):
 begin=sum(s['duration'] for s in segments)
 segments.append(dict(kind=kind,duration=duration,begin=begin,end=begin+duration,mode=mode,start=start,speed=speed))

for mode in ['rules','jev']:
 if mode=='jev':segment('divider',2)
 segment('intro',3.5,mode)
 segment('play',10.8/.75,mode,0,.75)
 segment('play',(14.5-10.8)/.5,mode,10.8,.5)
 segment('play',(results[mode]['duration']-14.5)/.75,mode,14.5,.75)
 segment('result',2,mode,results[mode]['duration'])
segment('split_intro',2,start=10.8)
segment('split_move',(14.5-10.8)/.5,start=10.8,speed=.5)
segment('split_hold',3,start=14.5)
segment('split_contact',2,start=14.5,speed=.5)
segment('split_end',4,start=15.5)
segment('closing',4)
DURATION=math.ceil(sum(s['duration'] for s in segments)*FPS)/FPS

def wording(m,t):
 if t<.667:return 'ゲーム開始。まずは保管庫へ向かう。',['青▲がプレイヤー','A・B・Cは警備中','まずはAに注目']
 if t<1.42:return 'Aに見つかった。Bも連携して動く。',['A：発見して追跡','B：仲間を援護','C：保管庫を守る']
 if t<4.05:return '煙幕で視界を切る。敵は追跡を続ける。',['煙幕の間に東へ移動','A・Bが追跡・連携','Cは保管庫を警備']
 if t<5.22:return '姿を見失っても最後に見た場所を調べる。',['通常AIにも記憶がある','A・Bは捜索を続ける','プレイヤーは東側へ']
 if t<7.017:return '今度は東でCに見つかった。再び煙幕を使う。',['東でも目撃される','仲間にも無線で伝わる','煙幕で建物の北へ']
 if t<9.5:return '赤い印の場所で発砲。敵には銃声も伝わる。',['赤い印が発砲した場所','プレイヤーは西へ移動','東の目撃・銃声が残る']
 if t<11:return '建物を回って西へ。次の物音で配置が分かれる。',['東の目撃情報は残る','西でまた音を出す','Aの行き先に注目']
 if m=='rules':
  if t>=contact_time(m):return '保管庫前のCが再発見。通常AIも侵入を止める。',['A・B：応援へ戻る','C：保管庫の前で発見','ケースには届かない']
  return '通常AI：A・Bが西の音を調べる。Cは保管庫を守る。',['A：西へ援護に向かう','B：援護を待って調査','C：保管庫を警備']
 if t<assist_time():return '通常AIがすぐ対応。その間にJevへ問い合わせ。',['まず同じ通常AIが動く','Jevの返答待ちでも','敵は止まらない']
 if t>=contact_time(m):return '東に残ったAが保管庫の手前で再発見。',['A：東の経路で発見','B：西側から合流へ','C：保管庫を警備']
 return 'Jevの返答で配置を見直す。Aは東へ。Bは西へ。',['東の目撃・銃声のあと','西でまた物音がした','→ Aを東の警戒に残す','→ Bが西を見張る']

def draw_pass(m,t,kind,elapsed,speed):
 if kind=='intro':i=-1;f=start_frame;im=diagram(m,f,0,False);picture=start_image
 else:i,f=sample(m,t);im=diagram(m,f,t);picture=actual(m,i)
 d=ImageDraw.Draw(im)
 title,lines=wording(m,t)
 if kind=='result':
  stopper='C' if m=='rules' else 'A'
  title=f'ケース回収前に{stopper}が侵入を止めた。'
  lines=['C：保管庫前で再発見','A・B：西から応援へ', 'Cの射撃でプレイヤーが倒れる'] if m=='rules' else ['A：東の経路で再発見','B：西側から合流へ','Aの射撃でプレイヤーが倒れる']
 txt(d,(35,14),'① 通常AI' if m=='rules' else '② 同じAI ＋ Jev',28,GREEN)
 txt(d,(35,60),title,40)
 txt(d,(1240,16),f"ゲーム内 {f['time']:04.1f} 秒",25)
 txt(d,(1070,158),'敵は何をする？',30,GREEN)
 for j,line in enumerate(lines):txt(d,(1070,216+j*49),line,28)
 txt(d,(1070,435),f"プレイヤーの耐久：{int(f['player_hp'])} / 100",25)
 txt(d,(1070,480),'実画面・図と同じ時刻',23)
 txt(d,(35,818),'目的：保管庫のケースを回収して南の出口から脱出',28)
 label='ゲーム開始' if kind=='intro' else '結果・一時停止' if kind=='result' else f'{speed:g}倍速'
 txt(d,(35,861),label+' ／ 敵の能力・プレイヤーの操作は両方式で共通',23,'#536b77')
 if kind=='intro':
  # Hold 0.0 s throughout the shrink. Movement starts only after it settles.
  u=max(0,min(1,(elapsed-1.8)/1.0));u=u*u*(3-2*u)
  x,y,w=round(200+870*u),round(135+390*u),round(1200-700*u)
  if elapsed<1.8:
   im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
   txt(d,(65,27),'① 通常AI' if m=='rules' else '② 同じAI ＋ Jev',44)
   txt(d,(65,811),'ゲーム開始。まずは保管庫へ向かう。',34)
 else:x,y,w=1070,525,500
 h=round(w*525/970);im.paste(picture.resize((w,h),Image.Resampling.LANCZOS),(x,y))
 ImageDraw.Draw(im).rectangle((x,y,x+w,y+h),outline='#526c79',width=2)
 return im,dict(mode=m,sample=i,simulation_time=f['time'],caption=title,initial_still=kind=='intro')

# Both panels use the same fixed world crop, about 1.5x larger than v10.
# No tracking camera hides the separation.
ZOOM=(300,328,950,691)
def split(t,kind):
 im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
 heading='③ 同じ時刻で比較。Aの行き先に注目。'
 if t>=contact_time('jev'):heading='東に残ったAが戻ってきたプレイヤーを発見。'
 txt(d,(35,22),heading,44)
 txt(d,(35,88),'同じ範囲を拡大 ／ 赤い線は11秒以降にAが通った道',28)
 for m,x in [('rules',35),('jev',825)]:
  _,f=sample(m,t)
  part=diagram(m,f,t,False).crop(ZOOM).resize((740,413),Image.Resampling.LANCZOS)
  im.paste(part,(x,205))
  d=ImageDraw.Draw(im)
  d.rectangle((x,205,x+740,618),outline='#8a9da6',width=2)
  txt(d,(x,145),'通常AI' if m=='rules' else '同じAI ＋ Jev',40,GREEN)
  txt(d,(x+440,159),f'ゲーム内 {t:04.1f} 秒',25)
  g=next(g for g in f['guards'] if g['id']=='A');px,py=pt(g['pos'])
  ax=x+(px-ZOOM[0])*740/(ZOOM[2]-ZOOM[0]);ay=205+(py-ZOOM[1])*413/(ZOOM[3]-ZOOM[1])
  mate=next((g2 for g2 in f['guards'] if g2['id']!='A' and math.dist(pt(g2['pos']),pt(g['pos']))<44),None)
  half=35
  if mate:
   mx,my=pt(mate['pos']);ax=x+((px+mx)/2-ZOOM[0])*740/(ZOOM[2]-ZOOM[0]);ay=205+((py+my)/2-ZOOM[1])*413/(ZOOM[3]-ZOOM[1]);half=52
  d.rounded_rectangle((ax-half,ay-34,ax+half,ay+34),8,outline=RED,width=5)
  if t<11:
   label='まだ同じ配置。西で物音がする直前。'
  elif m=='rules':label='Aは西へ移動してBの調査を援護。'
  elif t<assist_time():label='同じ対応を開始。Jevの返答待ち。'
  elif t<contact_time(m):label='Aは東に残る。Bは西を見張る。'
  else:label='Aが東で再発見。すぐに攻撃。'
  txt(d,(x,649),label,30)
  detail='保管庫はCが引き続き警備。' if m=='rules' else 'Cも引き続き保管庫を警備。'
  if t>=contact_time('jev'):detail='この時点ではまだ見つけていない。' if m=='rules' else '青▲が戻ってきたところを捉えた。'
  txt(d,(x,704),detail,28)
 txt(d,(35,785),'Jevが見直したのは作戦と配置。移動・視界・無線・射撃は共通。',34)
 txt(d,(35,847),('0.5倍速' if kind in ['split_move','split_contact'] else '一時停止')+' ／ 青▲：プレイヤー　 橙●：敵A・B・C',25,'#536b77')
 return im,dict(simulation_time=t,mode='split',crop=list(ZOOM),caption=heading)

def render(t):
 s=next((s for s in segments if s['begin']<=t<s['end']),segments[-1])
 elapsed=min(s['duration'],max(0,t-s['begin']));st=s['start']+elapsed*s['speed']
 kind=s['kind']
 if kind=='divider':
  im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
  d.rounded_rectangle((70,115,1530,757),24,fill='white',outline='#d5e0df',width=2)
  d.rounded_rectangle((105,156,114,708),4,fill=GREEN)
  txt(d,(150,170),'次は同じAIにJevを追加',56)
  d.rounded_rectangle((150,290,650,400),16,fill='#e9eff0')
  d.rounded_rectangle((850,290,1450,400),16,fill=GREEN)
  txt(d,(328,309),'通常AI',44)
  txt(d,(977,309),'通常AI ＋ Jev',44,'white')
  d.line((704,345,790,345),fill=GREEN,width=7)
  d.polygon([(805,345),(781,329),(781,361)],fill=GREEN)
  txt(d,(150,486),'同じスタート地点から同じ操作で。',44)
  txt(d,(150,591),'最後に配置が分かれる場面を並べて見ます。',44)
  meta=dict(mode='divider',simulation_time=None,caption='同じスタートからJev追加版')
 elif kind=='closing':
  im,_=split(15.5,'split_end');d=ImageDraw.Draw(im)
  sentence='同じAIでも作戦の選び方で守り方が変わる。'
  d.rectangle((30,776,1570,833),fill=BG)
  txt(d,(35,785),sentence,34)
  meta=dict(mode='closing',simulation_time=15.5,caption=sentence)
 elif kind.startswith('split'):im,meta=split(st,kind)
 else:im,meta=draw_pass(s['mode'],st,kind,elapsed,s['speed'])
 meta.update(output_time=t,kind=kind,speed=s['speed'])
 return im,meta

if __name__=='__main__':
 (P/'guard-v13-chapters.json').write_text(json.dumps(segments,ensure_ascii=False,indent=2),encoding='utf-8')
 checks=[0,1.8,2.3,3.3,4.6]+[s['begin']+.5 for s in segments if s['kind']!='intro']
 for n,t in enumerate(checks):render(t)[0].save(P/f'guard-v13-check-{n:02d}.jpg',quality=94)
 split(14.5,'split_hold')[0].save(P/'guard-v13-poster.jpg',quality=95)
 if '--stills' in sys.argv:raise SystemExit(0)
 out=P/'RELAY-Jev-guard-v13.mp4'
 proc=subprocess.Popen(['ffmpeg','-y','-v','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(out)],stdin=subprocess.PIPE)
 timeline=[]
 for i in range(round(DURATION*FPS)):
  im,meta=render(i/FPS);timeline.append(meta);proc.stdin.write(im.tobytes())
 proc.stdin.close()
 if proc.wait():raise SystemExit('Encoding failed')
 (P/'guard-v13-timeline.json').write_text(json.dumps(timeline,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps({'video':str(out),'duration':DURATION,'split_starts':next(s['begin'] for s in segments if s['kind']=='split_intro')}))
