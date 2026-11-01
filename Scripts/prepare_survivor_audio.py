"""Original deterministic synthesized game audio; no external recordings."""
from pathlib import Path
import math
import random
import struct
import wave


def prepare_audio(folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    rate = 22050

    def write(name, samples):
        with wave.open(str(folder / (name + '.wav')), 'wb') as out:
            out.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
            out.writeframes(b''.join(struct.pack('<h', round(max(-1, min(1, x))*32767)) for x in samples))

    # 16 bars at 120 BPM, pentatonic arpeggio over four changing chords.
    samples = [0.0] * (rate*32)
    chords = [(48,55,60,64), (45,52,57,60), (41,48,53,57), (43,50,55,62)]
    for beat in range(128):
        chord = chords[(beat//8)%4]
        midi = chord[beat%4]+12
        freq = 440*2**((midi-69)/12)
        for i in range(round(rate*.48)):
            t=i/rate; env=min(1,t/.012)*math.exp(-t*8)
            samples[(round(beat*.25*rate)+i)%len(samples)] += .16*env*(math.sin(2*math.pi*freq*t)+.2*math.sin(4*math.pi*freq*t))
    # Seamless boundary: each note has decayed before the loop wraps.
    write('music', samples)
    rng=random.Random(20261101)
    for name, freq, duration in [('cast',500,.14),('hit',170,.09),('heal',800,.3),('upgrade',660,.5)]:
        values=[]
        for i in range(round(rate*duration)):
            t=i/rate; env=math.sin(math.pi*t/duration)**2
            tone=math.sin(2*math.pi*(freq*t+(freq*.7)*t*t))
            values.append(.22*env*(tone if name in ('heal','upgrade') else .5*tone+.5*rng.uniform(-1,1)))
        write(name,values)
    # Distinct original effects: flame rush, electrical crack, low rock impact,
    # sand hiss and sword swish. Bounded mono clips, no external audio licenses.
    for name in ['fireball','lightning','earth-spikes','stone-fist','boulder','quicksand','orbit-swords','seeking-swords','seeking-merged','lightning-explosion']:
        duration=.42 if name.startswith('lightning') else .32
        values=[];last=0.0
        for i in range(round(rate*duration)):
            t=i/rate;u=t/duration;noise=rng.uniform(-1,1);last=last*.86+noise*.14
            if name.startswith('lightning'): sample=noise*(1 if i%1100<100 else .27)+math.sin(2*math.pi*74*t)*.25
            elif name in ('boulder','stone-fist','earth-spikes'): sample=math.sin(2*math.pi*(65*t-24*t*t))*.7+last*.8
            elif name=='quicksand':sample=last*.9+noise*.12
            elif 'sword' in name or 'seeking' in name:sample=noise*.36+math.sin(2*math.pi*(1400*t-1400*t*t))*.18
            else:sample=last*1.5+noise*.13
            envelope=min(1,t/.007)*pow(1-u,2)
            values.append(.42*sample*envelope)
        write(name,values)


if __name__ == '__main__':
    prepare_audio(Path(__file__).resolve().parents[1]/'App/Resources/SurvivorGameV2/Audio')
