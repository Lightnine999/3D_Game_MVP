# 관리자 사용 안내 — C 백엔드 초안

- 작성·확인: 2026-09-30 (KST)
- 대상: `Server 1`(ref `ecqfmaivywgzlbnqxymb`) 본편 관리자 기능
- 상태: **임시 익명 관리자 계정으로 API·DB 권한 일부 Cloud 검증. 영구 관리자 지정·Supabase Studio UI 실사용·팀 검토 전.**

## 권한 경계부터 확인

1. **게임 관리자**는 로그인한 Supabase Auth 사용자의 `profiles.role = 'admin'`인 계정이다. `admin-overview`와 `admin-support-reply`는 서버가 JWT의 사용자 ID를 확인한다. 후자는 DB `admin_reply` 함수에서도 역할을 다시 확인한다. 일반 사용자 API 호출은 Cloud에서 HTTP 403으로 거부됨을 실측했다.
2. **Supabase Studio 프로젝트 멤버**는 별도 운영 권한이다. Studio SQL Editor를 사용할 수 있다는 사실만으로 해당 사람의 게임 계정 `profiles.role`이 관리자라는 뜻이 아니다. Studio 권한은 신뢰하는 운영자에게만 부여하고, 일반 플레이어에게 주지 않는다. Studio 자체에서 앱 관리자 역할이 강제된다고 주장하지 않는다.
3. 일반 `authenticated` 역할에는 `admin_members`·`admin_purchases`·`admin_support` 보기의 직접 SELECT를 허용하지 않는다. 서비스 역할은 서버 함수 내부에서만 사용하고 앱/APK·웹·문서에 키를 넣지 않는다.

## 목록 확인

- 앱 관리자 세션에서 `POST /functions/v1/admin-overview`로 `{ "section": "members" }`, `{ "section": "purchases" }`, `{ "section": "support" }` 중 하나를 보낸다. 응답은 `{ "section": "members", "items": [ ... ] }` 형식이며 최대 100행이다. **페이지 넘김은 아직 없다.** 임의 테이블 이름을 보내도 서버의 허용 목록 외 조회는 거부된다.
- `members`에는 `user_id`, `nickname`, `is_guest`, `email_masked`, `created_at`이 있다. 회원·게스트 수는 `is_guest` 값으로 집계한다. 실제 이메일 연결 후 마스킹 갱신은 아직 실측 전이다.
- `purchases`에는 상품·금액·주문 상태·검증 시점과 `product_total`이 있다. 합성 지급 DB 기록은 검증했지만 **Toss 실제 승인 거래는 아직 없다.**
- `support`에는 `thread_id`, 사용자, 종류, 상태, 일시 및 일부 버그 기기 정보가 있다. **메시지 본문은 이 보기에 포함되지 않는다.** 신뢰하는 운영자는 해당 스레드의 `support_messages`를 별도로 확인해야 한다. 채팅 내용·기기 정보를 외부 문서나 공개 이슈로 복사하지 않는다.
- Studio SQL Editor는 신뢰하는 프로젝트 운영자가 읽기 전용 집계를 할 때만 사용한다. 예: `select count(*) filter (where is_guest) as guests, count(*) filter (where not is_guest) as registered from public.admin_members;`. 이는 **Studio 운영자 권한으로 실행되는 조회**이지 게임 관리자 JWT 검사를 대신하지 않는다.

## 문의 답변·상태 변경

- 게임 관리자 세션의 `POST /functions/v1/admin-support-reply`에 `{ "threadId": "<스레드 UUID>", "reply": "<팀 답변>", "status": "closed" }`를 보낸다. 상태는 `in_progress` 또는 `closed`만 가능하다. 답변 길이는 공백 제외 1~2000자다.
- 성공 시 `{ "threadId": "<같은 UUID>", "status": "closed" }`가 반환되고 `support_messages.role = 'team'` 기록 및 `support_threads.status`를 본인 스레드 조회로 재확인할 수 있다. 임시 관리자/일반 사용자로 권한 차이와 실제 답변·상태 변경을 Cloud에서 확인했다.
- **팀용 관리자 UI는 아직 구현되지 않았다.** Studio에서 테이블을 직접 수정하거나 `p_admin_id`를 임의로 넣어 RPC를 실행하면 앱 관리자 JWT 경계를 시험한 것이 아니다. 운영용 화면과 사용 주체를 팀에서 확정해야 한다.

## 관리자 계정 운영과 미완료

- 테스트 중 임시 익명 관리자 역할을 잠시 지정했으나 테스트 사용자·행은 모두 삭제했다. **현재 영구 관리자 계정이 있다고 가정하지 않는다.** 실제 운영 관리자 지정은 팀에서 계정 소유자를 확인하고 신뢰하는 운영 경로로 수행해야 하며, 이 문서는 역할 변경을 실행하지 않는다.
- Supabase Studio 실제 화면에서의 조회·답변 절차, 영구 관리자 계정, 이메일 마스킹의 실제 주소, 구매 실거래, 회원 수가 100명을 넘을 때의 페이지 넘김은 검증 전이다. PRD의 “Studio만으로 앱 관리자 역할을 강제”한다는 해석과 현재 API 경계는 다르므로 팀 합의가 필요하다.
- 실제 검증과 잔여 위험은 `SECURITY_REVIEW.md`, 프론트 요청·응답 규격은 `../backend/📖백엔드 연동 계약.md`, 원격 적용·정리 증거는 `../📋YH_3D_Game_MVP_현재 진행 현황.md`를 참조한다. 문서의 API 예시·임시 계정 실측을 전체 MVP 완료나 팀 승인으로 확대하지 않는다.
