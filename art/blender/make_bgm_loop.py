"""긴 배경음에서 원하는 길이만 잘라, 끝과 처음이 끊김 없이 이어지는 반복(loop) 음악으로 만든다.
Blender 에 들어 있는 오디오 도구(aud)만 쓴다 — 따로 설치할 것이 없다.

사용:
  blender -b --factory-startup --python art/blender/make_bgm_loop.py -- \
      --src art/source/audio/juhani_junkala_post_apocalyptic_wastelands_loop.ogg \
      --length 150 --crossfade 3 --bitrate 96000 --out godot/assets/audio/bgm_field.ogg

반복 이음 방법:
  [0, length] 구간을 쓰고, length 뒤에 이어지는 crossfade 초를 서서히 줄이며 곡 시작에 겹친다.
  시작 부분은 같은 시간 동안 서서히 키운다. → 끝(length)에서 처음(0)으로 넘어갈 때 소리가 그대로 이어진다.
  (처음 한 번 재생할 때는 crossfade 초 동안 부드럽게 커지며 시작한다)
결과: TECH_SPEC 13.3.1 ①-5 경로·이름 `godot/assets/audio/bgm_<이름>.ogg`
"""
import argparse
import struct
import sys

import aud


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--start", type=float, default=0.0, help="원본에서 자르기 시작할 초")
    p.add_argument("--length", type=float, required=True, help="반복 한 바퀴 길이(초)")
    p.add_argument("--crossfade", type=float, default=3.0)
    p.add_argument("--bitrate", type=int, default=96000)
    p.add_argument("--even", type=float, default=0.0,
                   help="조용한 곳은 키우고 큰 곳은 줄여 크기를 고르게 (0 = 원본 그대로, 1 = 최대). 게임에서 효과음에 묻히지 않게")
    p.add_argument("--target-db", type=float, default=-20.0, help="--even 이 맞추는 평균 크기 (dBFS)")
    return p.parse_args(argv)


def ogg_seconds(path):
    """Ogg Vorbis 파일의 실제 재생 시간 (마지막 페이지의 샘플 위치 ÷ 샘플레이트)."""
    data = open(path, "rb").read()
    i = data.find(b"\x01vorbis")
    rate = struct.unpack("<I", data[i + 12:i + 16])[0]
    j = data.rfind(b"OggS")
    return struct.unpack("<q", data[j + 6:j + 14])[0] / rate


def even_out(sound, rate, amount, target_db):
    """크기 고르게 하기 (느린 자동 음량 조절).
    0.25초마다 소리 크기를 재고, 목표보다 작으면 키우고 크면 줄인다 (최대 +20 dB / -14 dB).
    큰 소리 앞뒤 1초는 미리 줄이고(그 구간에서 가장 작은 조절값), 그다음 앞뒤 1초로 부드럽게 한다.
    곡이 반복되므로 끝과 처음을 이어서 계산한다 → 이음새에서도 음량이 튀지 않는다."""
    import numpy as np
    x = sound.data().astype(np.float64)                 # (샘플, 채널)
    mono = x.mean(axis=1)
    hop = int(rate * 0.25)
    n = int(np.ceil(len(mono) / hop))
    pad = np.concatenate([mono, mono[: n * hop - len(mono)]])
    env = np.sqrt(np.mean(pad.reshape(n, hop) ** 2, axis=1)) + 1e-6
    gain = (10 ** (target_db / 20) / env) ** amount
    gain = np.clip(gain, 0.2, 10.0)
    k = 4                                                # 앞뒤 4칸 = 1초
    idx = (np.arange(n)[:, None] + np.arange(-k, k + 1)[None, :]) % n     # 끝과 처음을 이어서
    gain = gain[idx].min(axis=1)                         # 큰 소리 앞뒤는 미리 줄임
    gain = gain[idx].mean(axis=1)                        # 부드럽게
    t = (np.arange(n) + 0.5) * hop                       # 칸 가운데
    per_sample = np.interp(np.arange(len(mono)), np.concatenate([[t[-1] - n * hop], t, [t[0] + n * hop]]),
                           np.concatenate([[gain[-1]], gain, [gain[0]]]))
    y = x * per_sample[:, None]
    y = np.tanh(y / 0.85) * 0.85                         # 튀는 곳만 살짝 눌러 찌그러짐 방지 (압축 뒤에도 1 을 넘지 않게)
    print("BGM_LOOP even: 조절 %.1f dB - %.1f dB, 평균 %.1f → %.1f dBFS" % (
        20 * np.log10(gain.min()), 20 * np.log10(gain.max()),
        20 * np.log10(np.sqrt(np.mean(x ** 2))), 20 * np.log10(np.sqrt(np.mean(y ** 2)))))
    return aud.Sound.buffer(y.astype(np.float32), rate)


def main():
    a = parse_args()
    src = aud.Sound(a.src)
    rate, channels = int(src.specs[0]), int(src.specs[1])
    s0, L, X = a.start, a.length, a.crossfade

    head = src.limit(s0, s0 + L).fadein(0.0, X)
    tail = src.limit(s0 + L, s0 + L + X).fadeout(0.0, X)
    loop = head.mix(tail)

    if a.even > 0:
        loop = even_out(loop, rate, a.even, a.target_db)
    loop.write(a.out, rate, channels, aud.FORMAT_S16, aud.CONTAINER_OGG, aud.CODEC_VORBIS, a.bitrate)

    # 검사: 길이, 이음새(끝 → 처음)가 튀지 않는지, 전체 크기
    out = aud.Sound(a.out)
    data = out.data()                       # (샘플 수, 채널)
    import numpy as np
    n = int(rate * 0.05)                    # 50 ms
    end_rms = float(np.sqrt(np.mean(data[-n:] ** 2)))
    start_rms = float(np.sqrt(np.mean(data[:n] ** 2)))
    jump = float(np.max(np.abs(data[0] - data[-1])))
    peak = float(np.max(np.abs(data)))
    rms = float(np.sqrt(np.mean(data ** 2)))
    print("BGM_LOOP 길이 %.2f 초 (목표 %.0f), %d Hz %dch" % (ogg_seconds(a.out), L, rate, channels))
    print("BGM_LOOP 이음새: 끝 50ms 세기 %.4f / 처음 50ms 세기 %.4f / 끝→처음 샘플 차 %.4f" % (end_rms, start_rms, jump))
    print("BGM_LOOP 전체: 최고 %.3f, 평균 세기 %.4f (%.1f dBFS)" % (peak, rms, 20 * np.log10(max(rms, 1e-9))))
    print("BGM_LOOP out " + a.out)


main()
