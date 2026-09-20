"""Original, quiet 88 BPM instrumental bed. No external samples."""
from pathlib import Path
import numpy as np
import wave, subprocess, json
P=Path(__file__).resolve().parent / "audio"
P.mkdir(exist_ok=True)
SR=48000; D=86.25; BPM=88; beat=60/BPM
rng=np.random.default_rng(14)
mix=np.zeros((round(SR*D),2),np.float64)
def note(midi,start,length,amp=.09,pan=0,kind='pluck'):
 n=min(round(length*SR),len(mix)-round(start*SR))
 if n<=0:return
 t=np.arange(n)/SR;f=440*2**((midi-69)/12)
 if kind=='pad':
  env=np.minimum(t/.45,1)*np.minimum((length-t)/.8,1)
  x=(np.sin(2*np.pi*f*t)+.22*np.sin(2*np.pi*(f*1.002)*t)+.09*np.sin(2*np.pi*2*f*t))*env
 else:
  env=(1-np.exp(-t/.009))*np.exp(-t/(1.1 if kind=='bass' else .55))*np.minimum((length-t)/.12,1)
  x=(np.sin(2*np.pi*f*t)+.20*np.sin(2*np.pi*2*f*t)+.04*np.sin(2*np.pi*3*f*t))*env
 x*=amp
 i=round(start*SR);mix[i:i+n,0]+=x*np.sqrt((1-pan)/2);mix[i:i+n,1]+=x*np.sqrt((1+pan)/2)
def hit(start,kind):
 n=min(int(SR*.25),len(mix)-round(start*SR))
 if n<=0:return
 t=np.arange(n)/SR
 if kind=='kick':x=np.sin(2*np.pi*(48*t+28*.025*(1-np.exp(-t/.025))))*np.exp(-t/.065)*.07
 else:
  noise=rng.standard_normal(n);noise=np.concatenate(([0],np.diff(noise)))
  x=noise*np.exp(-t/(.012 if kind=='hat' else .034))*(.0025 if kind=='hat' else .004)
 x*=np.minimum(t/.002,1);i=round(start*SR);mix[i:i+n]+=x[:,None]*.7
chords=[([57,60,64,71],45),([53,57,60,64],41),([55,60,64,71],36),([55,59,62,64],43)]
for bar in range(32):
 start=bar*4*beat
 if start>D:break
 chord,bass=chords[(bar//2)%4]
 for j,m in enumerate(chord):note(m,start,4.3*beat,.012,(-.4+.27*j),'pad')
 note(bass,start,1.8*beat,.06,-.1,'bass');note(bass+12,start+2.5*beat,1.2*beat,.024,.1,'bass')
 for j,off in enumerate([.5,1.5,2.75,3.5]):
  m=chord[(j+bar)%4]+12
  note(m,start+off*beat,1.45*beat,.034,(-.4 if j%2 else .4))
 if bar%4==3:note(chord[2]+12,start+3*beat,1.2*beat,.024,0)
 for off in [0,2]:hit(start+off*beat,'kick')
 for off in [1,3]:hit(start+off*beat,'snare')
 for off in [0.5,1.5,2.5,3.5]:hit(start+off*beat,'hat')
# Gentle stereo echoes, no harsh transient or voice.
for delay,gain in [(.19,.11),(.31,.07),(.43,.035)]:
 k=round(delay*SR);mix[k:]+=mix[:-k,::-1].copy()*gain
# Take one complete 8-bar cycle after all voices/echoes have settled.
start=round(32*beat*SR);end=round(64*beat*SR)
mix=mix[start:end]
rms=np.sqrt(np.mean(mix**2));mix*=10**(-27/20)/max(rms,1e-9)
# Make the last few samples meet the next cycle without a click.
n=96;mix[-n:]=mix[-n:]*(1-np.linspace(0,1,n)[:,None])+mix[0]*np.linspace(0,1,n)[:,None]
out=P/'bgm-source.wav'
with wave.open(str(out),'wb') as w:
 w.setnchannels(2);w.setsampwidth(2);w.setframerate(SR);w.writeframes((np.clip(mix,-1,1)*32767).astype('<i2').tobytes())
subprocess.run(['ffmpeg','-y','-v','error','-i',str(out),'-c:a','libvorbis','-q:a','4',str(P/'bgm.ogg')],check=True)
out.unlink()
print('Created',P/'bgm.ogg')
