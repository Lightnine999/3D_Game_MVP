# WU-32 근거 — 소리 통로 `godot/default_bus_layout.tres` (2026-09-30)

TECH_SPEC 13.3.1: "`Master` / `BGM` / `SFX` / `UI` (`default_bus_layout.tres`, 주인 A)"

## 버스
| 버스 | 흘러가는 소리 | 누가 재생 | 시작 음량 |
|---|---|---|---|
| `Master` | 전체 | — | 0 dB |
| `BGM` | `bgm_field` `bgm_title` | C | **-3 dB** (효과음보다 조금 낮게) |
| `SFX` | 게임 효과음 10종 | B | 0 dB |
| `UI` | UI 효과음 3종 | C | 0 dB |

- 셋 다 `Master` 로 모인다
- Godot 는 프로젝트 맨 위의 `default_bus_layout.tres` 를 저절로 읽는다 → `project.godot`(C) 는 고치지 않았다

## 쓰는 법
```gdscript
player.bus = &"SFX"                                                    # B: 게임 효과음
AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"BGM"), db)   # C: 설정 화면(F-74) 볼륨
```

## 검사 — Godot 4.7.2 (팀 main 의 project.godot 로 불러 봄)
```
BUS 0 Master  0.0 dB  ->
BUS 1 BGM  -3.0 dB  -> Master
BUS 2 SFX  0.0 dB  -> Master
BUS 3 UI  0.0 dB  -> Master
BUS player.bus = SFX  index 2
BUS BGM 볼륨 바꾸기 -> -12.0
```

## 남은 것
- WU-32 완료 조건 "버스(`BGM`/`SFX`/`UI`) 볼륨이 C의 설정 화면과 연결된다" — 연결은 C 의 설정 화면(WU-30/31)에서
