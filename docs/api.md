# 모이온(MOION) 1단계 API 명세

2026-11-23 확정 · API 37개 · 기준: [비즈니스 정책](policy.md) v31 · [ERD](erd.md) v0.4 · [개발 컨벤션](convention.md) v0.1

1단계 API 계약이다. 이 문서에는 모든 API에 적용하는 공통 계약과 전체 목록을 두고, 각 API의 인증·요청·응답·오류·업무 규칙은 기능별 상세 문서에 둔다. 예시는 가상의 ID·금액이다. 선택한 카드 테스트 채널의 양수 하한값은 아직 확인하지 않았다.

- 문서 상태: 확정. 구현 상태: 구현 전(코드·테스트 없음).
- 읽는 순서: 공통 계약 → API 목록 → 기능별 상세.

## 목차

- [공통 계약](#공통-계약)
- [[POL-001] 참여자별 결제 금액 산정 방식](#pol-001-참여자별-결제-금액-산정-방식)
- [API 목록](#api-목록)
- [첫 배포에서 이어서 검증할 사례 (기대 결과)](#첫-배포에서-이어서-검증할-사례-기대-결과)

## 공통 계약


- API는 JSON을 사용한다. 별도 언급이 없으면 성공은 `{success, code, message, data}`로 응답한다. `success`가 있는 JSON은 전체 응답이고, 나머지 성공 응답 예시는 `data` 내부다. 요청 및 웹훅 본문은 전송 원형이다. 일반 성공 코드는 `OK`, 비동기 접수는 `PROCESSING`이다. 매장 수락 요청과 직원 수락은 상세에 명시된 업무 코드를 사용한다. 웹훅의 수신 확인은 별도 응답이다.
- 모이온 내부 자원의 숫자 ID는 양의 Long이다. 초대 토큰과 직원 권한 부여 요청 ID(grantRequestId, UUID)는 문자열이다. PortOne에 주고받는 식별자의 타입은 각 API 상세에 따른다. 모든 경로 변수는 필수다. 시각은 ISO 8601, 모이온 응답은 Asia/Seoul 기준 오프셋을 포함한다. 금액은 원 단위 정수이며 서버가 계산한다. 최초 분담 기본 단가는 총액을 전체 분담 몫으로 나눈 정수 몫이다. 각 결제자는 본인과 동반인의 몫만큼 부담하고, 원 단위 나머지는 예약자가 부담한다. 100,000원을 각 1몫인 6명이 나누면 예약자 16,670원, 나머지 5명은 각 16,666원이다.
- 회원 API는 세션 쿠키를 쓴다. 브라우저의 POST·PUT·PATCH·DELETE에는 가입·로그인을 포함해 `X-XSRF-TOKEN`이 필요하다. `GET /api/auth/csrf`로 받아 로그인·로그아웃 성공 후 새로 조회한다. PortOne 웹훅 한 경로는 원문 서명으로 인증한다.
- 공통 오류는 입력 검증 `400 INVALID_INPUT`, 보호 API의 세션 없음·만료 `401 AUTH_REQUIRED`, 브라우저 쓰기 요청의 CSRF 실패 `403 CSRF_INVALID`다. 요청마다 자원과 사용자의 관계를 확인한다. 예약자 전용 처리에서는 세션·CSRF 확인 후 모임 또는 당시 예약과 요청자의 관계를 먼저 확인한다. 존재하지 않는 자원과 무관한 계정에는 같은 404 코드·메시지를 반환한다. 접근 자격이 있지만 예약자 역할이 없는 참여자에게는 403을 반환한다. 권한 거부로 업무 상태·좌석·돈·알림이 바뀌는 건수는 0이다.
- 목록의 page는 0부터, size는 기본 20·최대 50이다. 페이지가 필요한 목록은 `{items, page, size, hasNext}` 형태다. 동률 정렬은 고유 ID로 결정한다. 단일 날짜 회차 목록은 시간순으로 한 번에 반환한다.
- 예시 숫자는 JSON 정수, true/false는 Boolean이다. 필수 입력은 각 Request에 표시했다. 조회로 좌석을 확보하거나 결제·환불·가입·참여를 확정하는 경로는 없다.

성공 예시

```json
{"success":true,"code":"OK","message":"조회했습니다.","data":{"memberId":42}}
```

오류 예시

```json
{"success":false,"code":"DRAFT_REVISION_MISMATCH","message":"분담안이 바뀌었습니다. 최신 내용을 확인해 주세요.","errors":[],"timestamp":"2026-11-28T16:00:00+09:00"}
```

입력 오류의 errors에는 `{field, reason}` 목록을 담고, 나머지는 빈 배열을 쓴다. 추가 안내가 있는 오류에는 `details` 객체를 포함한다. 명시한 경우에만 필드 생략 또는 null을 허용한다.

## [POL-001] 참여자별 결제 금액 산정 방식

원 단위 나머지를 예약자에게 배정한 뒤, **실제로 카드를 낼 회원별 최종 청구액**을 검사한다. 최종 확인 화면에서 안내하고 새 수락 요청을 저장하기 직전에 서버가 다시 계산한다. 한 명이라도 0원이면 거부한다. 선택한 테스트 채널에서 양수 하한이 확인되면 그 값 미만도 거부한다. 하한과 같은 금액은 이 검사를 통과한다. 0몫 동반인은 방문 인원에 포함하며 별도의 결제 예정자가 되지 않는다.

## API 목록

| 묶음 | 상세 문서 |
|---|---|
| 1. 회원과 세션 | [api/member-session.md](api/member-session.md) |
| 2. 모임과 초대 | [api/gathering-invite.md](api/gathering-invite.md) |
| 3. 장바구니와 금액 확인 | [api/cart-confirmation.md](api/cart-confirmation.md) |
| 4. 매장 수락 요청과 직원 응답 | [api/store-request.md](api/store-request.md) |
| 5. 결제·예약 결과·환불 | [api/payment-refund.md](api/payment-refund.md) |
| 6. 손님 알림함 | [api/notification.md](api/notification.md) |
| 7. 운영 조회와 직원 권한 | [api/admin.md](api/admin.md) |

| 번호 | API | Method | Path | 인증 |
|---|---|---|---|---|
| 1-0 | [CSRF 토큰 받기](api/member-session.md#api-1-0) | GET | `/api/auth/csrf` | 비로그인 및 로그인 브라우저 |
| 1-1 | [본인인증 시작](api/member-session.md#api-1-1) | POST | `/api/identity-verifications` | 비로그인 브라우저 · CSRF |
| 1-2 | [회원 가입](api/member-session.md#api-1-2) | POST | `/api/members` | 본인인증을 시작한 동일한 비로그인 세션 · CSRF |
| 1-3 | [로그인](api/member-session.md#api-1-3) | POST | `/api/auth/login` | 비로그인 브라우저 · CSRF |
| 1-4 | [로그아웃](api/member-session.md#api-1-4) | POST | `/api/auth/logout` | 로그인 회원 · CSRF |
| 1-5 | [내 정보 조회](api/member-session.md#api-1-5) | GET | `/api/members/me` | 로그인 회원 본인 |
| 2-1 | [예약 가능 회차 조회](api/gathering-invite.md#api-2-1) | GET | `/api/time-slots` | 로그인 회원 |
| 2-2 | [모임 생성](api/gathering-invite.md#api-2-2) | POST | `/api/gatherings` | 본인인증 완료 회원 · CSRF |
| 2-3 | [모임 상세 조회](api/gathering-invite.md#api-2-3) | GET | `/api/gatherings/{gatheringId}` | 현재 참여자(예약자 포함) |
| 2-4 | [초대 링크 미리보기](api/gathering-invite.md#api-2-4) | GET | `/api/invites/{token}` | 로그인 회원 |
| 2-5 | [초대 링크로 참여](api/gathering-invite.md#api-2-5) | POST | `/api/invites/{token}/participants` | 본인인증 완료 회원 · CSRF |
| 2-6 | [모임 나가기](api/gathering-invite.md#api-2-6) | DELETE | `/api/gatherings/{gatheringId}/participants/me` | 현재 참여자 본인 · CSRF |
| 2-7 | [참여자 내보내기](api/gathering-invite.md#api-2-7) | DELETE | `/api/gatherings/{gatheringId}/participants/{memberId}` | 예약자 · CSRF |
| 2-8 | [초대 링크 재발급](api/gathering-invite.md#api-2-8) | POST | `/api/gatherings/{gatheringId}/invite-link/reissue` | 예약자 · CSRF |
| 2-9 | [회차 변경](api/gathering-invite.md#api-2-9) | PATCH | `/api/gatherings/{gatheringId}/time-slot` | 예약자 · CSRF |
| 2-10 | [초대 링크 폐기](api/gathering-invite.md#api-2-10) | DELETE | `/api/gatherings/{gatheringId}/invite-link` | 예약자 · CSRF |
| 2-11 | [차단 해제](api/gathering-invite.md#api-2-11) | DELETE | `/api/gatherings/{gatheringId}/blocks/{memberId}` | 예약자 · CSRF |
| 3-1 | [장바구니 수량 지정](api/cart-confirmation.md#api-3-1) | PUT | `/api/gatherings/{gatheringId}/cart-items/{menuId}` | 현재 참여자 · CSRF |
| 3-2 | [장바구니 메뉴 삭제](api/cart-confirmation.md#api-3-2) | DELETE | `/api/gatherings/{gatheringId}/cart-items/{menuId}` | 현재 참여자 · CSRF |
| 3-3 | [내 동반인 구성](api/cart-confirmation.md#api-3-3) | PUT | `/api/gatherings/{gatheringId}/participants/me/companions` | 현재 참여자 본인 · CSRF |
| 3-4 | [최종 확인 화면 조회](api/cart-confirmation.md#api-3-4) | GET | `/api/gatherings/{gatheringId}/final-check` | 현재 참여자 |
| 3-5 | [금액 확인·분담 제외 동의](api/cart-confirmation.md#api-3-5) | POST | `/api/gatherings/{gatheringId}/confirmations` | 현재 참여자 본인 · CSRF |
| 4-1 | [매장 수락 요청](api/store-request.md#api-4-1) | POST | `/api/gatherings/{gatheringId}/store-requests` | 예약자 · CSRF |
| 4-2 | [수락 요청 철회](api/store-request.md#api-4-2) | POST | `/api/gatherings/{gatheringId}/store-requests/{storeRequestId}/cancel` | 요청이 속한 모임의 예약자 · CSRF |
| 4-3 | [매장 업무함 조회](api/store-request.md#api-4-3) | GET | `/api/store/inbox` | 유효한 매장 직원. 요청마다 현재 소속을 조회한다. |
| 4-4 | [직원 수락](api/store-request.md#api-4-4) | POST | `/api/store/requests/{storeRequestId}/accept` | 현재 소속 매장 직원, 본인의 모임 제외 · CSRF |
| 4-5 | [직원 거절](api/store-request.md#api-4-5) | POST | `/api/store/requests/{storeRequestId}/reject` | 현재 소속 매장 직원, 본인의 모임 제외 · CSRF |
| 5-1 | [결제 시작](api/payment-refund.md#api-5-1) | POST | `/api/reservations/{reservationId}/payments` | 예약의 원래 주문서에서 본인 몫을 가진 결제 예정자 · CSRF |
| 5-2 | [결제 완료 확인](api/payment-refund.md#api-5-2) | POST | `/api/payments/{paymentId}/complete` | 원결제 소유 회원 · CSRF |
| 5-3 | [PortOne 웹훅 수신](api/payment-refund.md#api-5-3) | POST | `/api/webhooks/portone` | PortOne 서버 · 원문 서명 |
| 5-4 | [결제 대기 조기 종료](api/payment-refund.md#api-5-4) | POST | `/api/reservations/{reservationId}/early-close` | 해당 예약의 예약자 · CSRF |
| 5-5 | [예약 결과·결제·환불 조회](api/payment-refund.md#api-5-5) | GET | `/api/reservations/{reservationId}` | 해당 예약의 결제 예정자 |
| 6-1 | [알림함 조회](api/notification.md#api-6-1) | GET | `/api/notifications` | 로그인 회원 본인 |
| 6-2 | [알림 읽음 표시](api/notification.md#api-6-2) | PATCH | `/api/notifications/{notificationId}/read` | 알림 수신자 본인 · CSRF |
| 7-1 | [미완료 환불 조회](api/admin.md#api-7-1) | GET | `/api/admin/refunds` | 운영자 |
| 7-2 | [직원 권한 부여](api/admin.md#api-7-2) | POST | `/api/admin/store-staff` | 운영자 · CSRF |
| 7-3 | [직원 권한 회수](api/admin.md#api-7-3) | DELETE | `/api/admin/store-staff/{storeStaffId}` | 운영자 · CSRF |

## 첫 배포에서 이어서 검증할 사례 (기대 결과)

아래 표는 구현 전에 계산한 기대 결과다. 아직 테스트로 실행하지 않았다.

| 장면 | 기대 결과 |
|---|---|
| 6명 중 2명 미확인, 동일 분담안으로 수락 요청 2회 | 주문서·매장 요청·업무함 0건, 미확인자 두 명에게 각 1건 |
| 수락 요청 재시도 뒤 직원 두 명이 같은 요청 수락 | 주문서 1장·요청 1건·예약 1건, 6석 확보 1회, 6명에게 결제 시작 알림 6건 |
| 마지막 6석에 6명 모임 두 개 수락 | 20석 중 14석 확보 상태에서 정확히 한 모임 성공, 최종 20석 |
| 결제 마감 19:30 | 결제 시작은 19:24:59 허용·19:25:00 거부. 마지막 유효 완료 기록 19:29:59면 확정, 19:30:00이면 만료. 이때 실제 승인된 여섯 번째 건까지 전액 환불 |
| 6명 중 4명 결제 후 만료, 두 번째 PG 취소 성공 직후 재배포 | 중단 직후 PG 성공 2건·DB 완료 1건. 두 번째 취소는 조회로 복구, 나머지 처리 뒤 원결제별 취소 1건씩, DB 완료 4건·좌석 해제 1회·손님 알림 14건·매장 업무함 결과 별도 1건. 재실행 시 추가 취소·좌석 해제·알림 0건 |
| 같은 몫에 20,000원짜리 서로 다른 두 승인 | 결제 완료 인원 1명. 중복 승인 20,000원 환불 후 예약 만료 시 원래 승인분만 추가 환불. 두 원결제 합계 40,000원, 재실행 추가 0원 |
| 옛 주문서 20,000원 승인이 새 주문서 18,000원 생성 후 도착 | 옛 예약에서 20,000원 환불. 새 예약의 결제 완료 인원·금액 변화 0 |
| 권한 회수 후 같은 세션 / 일반 참여자 조기 종료 | 다음 직원 업무 요청 거부 / 조기 종료 거부. 두 경우 업무 상태·환불·좌석·알림 변화 0 |
| 0원 청구 회원·검증된 양수 하한 M의 경계 | 0원은 항상 거부. M이 확인된 경우 M보다 작은 청구액은 거부하고 정확히 M원은 하한 검사 통과. 거부 시 새 주문서·매장 요청·업무함·좌석 확보 각 0건. 0몫 동반인은 방문 인원에 포함 |
| 부여 요청 A로 권한 생성(201) → 다른 ID B로 이미 활성인 같은 권한 반환(200) → 회수 → B 재시도 | B가 처음 연결된 부여 이력의 현재 상태 REVOKED로 200. 활성 권한 0건, 해당 세션의 다음 매장 요청 403 |
| 비동기 취소 접수 → PG 재조회 REQUESTED → SUCCEEDED → 늦은 접수 재수신 | 접수 시 완료 알림 0건. 성공 확인 후 환불 완료 1건·완료 알림 1건. 재수신 뒤에도 동일 |
| 예약자 전용 처리에 미참여자·일반 참여자가 각각 접근 | 기존 자원 미참여자와 없는 자원은 같은 404·코드·메시지. 접근 가능한 일반 참여자는 403. 좌석·환불·업무 알림 추가 0건 |
| 6명 전원 기한 전 결제 | 예약 확정 1건, 손님 확정 알림 6건·매장 준비 확정 결과 1건. 웹훅 재전송 뒤 추가 0건 |
| 웹훅·브라우저 통보가 누락된 실제 승인 | 종료 예약의 미확정 원결제 대조로 발견. 당시 주문서 확인 후 원결제별 잔액만 환불 접수 |

결제 기한 만료, PG 취소 실행, 미완료 환불 대조는 서버 내부 작업이다. 만료·좌석 해제·환불 접수·필수 알림은 한 번에 커밋하고 PG 호출은 그 뒤에 실행한다. 같은 결정·원결제 조합의 환불은 최대 1건이다. 아직 결과를 모르는 금액도 누적 한도에 포함한다. 같은 키로 재전송할 수 있는 기간이 지나면 PG의 기존 취소를 식별할 수 있는지부터 확인한다.

## 근거 문서

- 저장소 문서: [비즈니스 정책](policy.md) · [역할별 권한](permissions.md) · [상태 전이표](state-transitions.md) · [ERD](erd.md)
- [PortOne 카드 결제창](https://developers.portone.io/opi/ko/integration/start/v2/checkout) · [웹훅](https://developers.portone.io/opi/ko/integration/webhook/readme-v2) · [REST API·멱등 키](https://developers.portone.io/api/rest-v2) · [본인인증 상태와 DI](https://developers.portone.io/opi/ko/extra/identity-verification/readme-v2)
- [KCP 본인인증 ID 형식](https://developers.portone.io/opi/ko/integration/pg/v2/kcp-v2-identity-verification)
- [Spring Security 세션 기반 CSRF](https://docs.spring.io/spring-security/reference/servlet/exploits/csrf.html)
