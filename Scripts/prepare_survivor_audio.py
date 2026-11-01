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


if __name__ == '__main__':
    prepare_audio(Path(__file__).resolve().parents[1]/'App/Resources/SurvivorGameV2/Audio')
