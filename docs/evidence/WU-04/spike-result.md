# WU-04 근거 — 파이프라인 시험 운전 (Spike)

- 실행일: 2026-09-28
- 시험 코드 위치: 세션 임시 폴더 (버리는 코드, 저장소에 넣지 않음)
- 결론: **Blender 스크립트 → .glb → Godot → Android APK → 실기기 실행까지 전 구간 명령줄로 동작 확인**

## 1. 단계별 결과
| 단계 | 명령 | 결과 | 근거 |
|---|---|---|---|
| Blender 모델 생성 | `blender -b --factory-startup -P make_spike.py -- <out>` | 상자+기둥 합친 모델, 삼각형 56개 | - |
| .glb 내보내기 | `bpy.ops.export_scene.gltf(export_format="GLB", export_yup=True)` | `spike_model.glb` 5.4KB | - |
| 미리보기 렌더 | EEVEE, 4방향 PNG | 비율·원점(발밑) 정상 | `1_blender_preview_front.png`, `1_blender_preview_top.png` |
| Godot 가져오기 | `godot --headless --path . --import` | 정상 (.scn 생성) | - |
| Mac 실행 스크린샷 | `godot --path . -- --shot=<png>` | Metal 4.0 / Forward Mobile, 거리 안개 동작 | `2_godot_mac_19.5x9.png` |
| Android APK 빌드 | `godot --headless --path . --export-debug "Android" <apk>` | 28MB, 디버그 서명 완료 (Gradle 빌드 없이 기본 템플릿) | - |
| 폰 설치 | `adb install -r <apk>` | Success (Incremental Install, 약 2.3초) | - |
| 폰 실행 | `adb shell am start -n <패키지>/com.godot.game.GodotAppLauncher` | **Vulkan 1.3 / Forward Mobile / Adreno 750**, 2340×1080 전체 화면 | `3_phone_s24ultra.png` |

## 2. 확인된 사실 (본 개발에 반영)
| # | 내용 | 반영 위치 |
|---|---|---|
| 1 | Blender 5.2의 렌더 엔진 식별자는 `BLENDER_EEVEE` (4.x의 `BLENDER_EEVEE_NEXT` 아님) | WU-11 `render_preview.py` |
| 2 | glTF 내보내기는 `bpy.ops.export_scene.gltf(export_format="GLB")` 그대로 동작. 연산자 enum은 동적이라 `bl_rna`로는 목록이 비어 보임 | WU-11 `export_glb.py` |
| 3 | 빈 장면 시작은 `bpy.ops.wm.read_factory_settings(use_empty=True)` | WU-11 공통 라이브러리 |
| 4 | Godot은 `JAVA_HOME`·`ANDROID_HOME`을 읽어 에디터 설정의 SDK 경로를 **자동으로 채우고**, 디버그 키스토어도 자동 생성한다 (`~/Library/Application Support/Godot/keystores/debug.keystore`) | WU-35 (릴리스 키는 별도 생성) |
| 5 | 기본 템플릿(비 Gradle) 내보내기로 APK가 만들어진다. 결제 플러그인을 넣는 4단계 전까지는 Gradle 빌드가 필요 없다 | WU-61에서 Gradle 빌드 전환 검토 |
| 6 | 빈 장면 수준의 APK가 28MB → 기본 엔진 크기. 설치 용량 목표 150MB(N-03)의 나머지가 에셋 예산 | WU-33 |
| 7 | 거리 안개(`FOG_MODE_DEPTH`) + 높이 안개가 Mobile 렌더러에서 Mac(Metal)·폰(Vulkan) 모두 동작 | WU-13 |
| 8 | `Camera3D.KEEP_HEIGHT`로 19.5:9 화면이 검은 띠 없이 채워짐 | WU-16 |

## 3. 발견한 문제·주의점
| 문제 | 원인 | 대응 |
|---|---|---|
| 상자의 갈색이 회색처럼 보임 | 파란 달빛 + 안개 색이 섞임 | WU-10 `STYLE.md`에서 달빛·안개 색과 소품 팔레트를 함께 정하고 WU-13에서 폰으로 확인 |
| 내보내기 시 "프로젝트 아이콘 없음" 오류 로그 | 아이콘 미지정 (빌드는 성공) | 본 프로젝트 `project.godot`에 아이콘 지정 |
| 폰이 `unauthorized`로 바뀜 | `adb` 서버 재시작 후 허용 기록이 없었음 | 폰에서 "이 컴퓨터에서 항상 허용" 체크 (완료) |
| `pm list packages`에서 `user 150` 권한 오류 | 삼성 보안 폴더(별도 사용자 공간) | `--user 0` 옵션 사용 |
| `adb shell monkey`로 실행 실패 | 설치 전에 실행 명령이 돌았음 | 설치 성공 확인 후 `am start -n <패키지>/com.godot.game.GodotAppLauncher`로 실행 |

## 4. 아직 확인하지 않은 것
- FPS 실측 (빈 장면이라 의미 없음 → WU-13·WU-33에서 디버그 오버레이로 측정)
- 릴리스 서명 `.aab` (WU-35)
