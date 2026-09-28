# WU-03 근거 — 테스트 폰 USB 연결

- 확인일: 2026-09-28
- 연결 방식: USB-C 케이블 (USB 디버깅 허용, "이 컴퓨터에서 항상 허용")

## `adb devices -l`
```
List of devices attached
<시리얼 생략>   device usb:... product:e3qksx model:SM_S928N device:e3q
```

## 기기 정보 (`adb shell getprop` / `wm`)
| 항목 | 값 |
|---|---|
| 모델 | SM-S928N (Galaxy S24 Ultra, 국내판) |
| Android | 16 (API 36) |
| SoC | SM8650 (Snapdragon 8 Gen 3 for Galaxy) |
| ABI | arm64-v8a |
| OpenGL ES | 3.2 (`ro.opengles.version` = 196610) |
| 현재 화면 해상도 | 1080×2340 (설정의 화면 해상도가 FHD+) — 비율 19.5:9 |
| 화면 밀도 | 450 dpi |
| 측정 시 주사율 | 60Hz (가변 주사율, 게임 실행 시 최대 120Hz 가능) |

## 메모
- 기기 최대 해상도는 3120×1440(QHD+)이지만 현재 설정은 FHD+다. 성능 측정은 **기본 설정(FHD+)** 기준으로 한다.
- 기기가 Android 16(API 36)이므로 target API 35로 빌드한 앱도 설치·실행된다. 구글플레이 target API 요구 수준은 WU-35에서 다시 확인한다.
