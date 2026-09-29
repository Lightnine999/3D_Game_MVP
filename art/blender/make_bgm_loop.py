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
    return p.parse_args(argv)


def ogg_seconds(path):
    """Ogg Vorbis 파일의 실제 재생 시간 (마지막 페이지의 샘플 위치 ÷ 샘플레이트)."""
    data = open(path, "rb").read()
    i = data.find(b"\x01vorbis")
    rate = struct.unpack("<I", data[i + 12:i + 16])[0]
    j = data.rfind(b"OggS")
    return struct.unpack("<q", data[j + 6:j + 14])[0] / rate


def main():
    a = parse_args()
    src = aud.Sound(a.src)
    rate, channels = int(src.specs[0]), int(src.specs[1])
    s0, L, X = a.start, a.length, a.crossfade

    head = src.limit(s0, s0 + L).fadein(0.0, X)
    tail = src.limit(s0 + L, s0 + L + X).fadeout(0.0, X)
    loop = head.mix(tail)

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
