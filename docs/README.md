# 문서 목차

루트 [README](../README.md)는 서비스 소개와 현재 상태를, 이 문서는 설계 문서의 위치와 읽는 순서를 안내한다.

문서 상태와 구현 상태는 따로 적는다. 아래 문서는 모두 1단계 설계 확정본이다. 구현은 ERD의 Flyway V1과 DB 제약 테스트까지 진행했다(PR #2).

## 설계 문서

| 문서 | 확인할 내용 | 기준 | 문서 상태 | 구현 상태 |
|---|---|---|---|---|
| [비즈니스 정책](policy.md) | POL-001~POL-017 정책·예외 흐름·검증 조건, 보류 정책, 외부 확인 항목 | v31 · 2026-11-23 | 확정 | 구현 전 |
| [역할별 권한](permissions.md) | 예약자·참여자·원결제자·매장 직원·운영자별 허용 행위 | [POL-016] 역할과 예약별 권한 | 확정 | 구현 전 |
| [상태 전이표](state-transitions.md) | 예약·확정 주문서·결제·환불·이의·매장 지급·초대 링크의 상태 변화와 조건 | POL-001~POL-017 | 확정 | 구현 전 |
| [ERD](erd.md) | 25개 테이블의 관계·컬럼·키·잠금 순서, [전체 도면](erd/moion-erd-v0.4.png), [DBML 원본](erd.dbml), [도면 SVG](erd/moion-erd-v0.4.svg) | v0.4 · 2026-11-23 | 확정 | MySQL 8.4.13 DDL·제약 검증 완료(PR #2), 동시성 검증 전 |
| [API 명세](api.md) | 공통 계약(응답 형식·세션·CSRF·공통 오류)과 API 37개 목록 | 1단계 · 2026-11-23 | 확정 | 구현 전 |
| [개발 컨벤션](convention.md) | 코드 책임, 예약별 권한, 결제 반영, 트랜잭션, 재시도·복구, 동시성 테스트, PR 기준 | v0.1 · 2026-11-23 | 확정 | 구현 전 |
| [검산 사례](verification-cases.md) | 금액·시각·정원·재배포 복구·알림 건수·권한·본인인증의 기대 결과 | 정책 v31 | 확정(기대 결과) | 테스트 실행 전 

정책 ID(`POL-001`~`POL-017`)는 [비즈니스 정책](policy.md)의 정책 번호다. 이슈·PR·테스트에서 이 번호와 정책 이름으로 근거 정책을 가리킨다.

## API 상세

공통 계약은 [API 명세](api.md)에 한 번만 두고, 기능별 상세는 아래 문서에 둔다. [API 목록](api.md#api-목록)의 각 행에서 해당 API 상세로 바로 이동한다.

| 묶음 | 상세 문서 | API 수 |
|---|---|---|
| 1. 회원과 세션 | [api/member-session.md](api/member-session.md) | 6 |
| 2. 모임과 초대 | [api/gathering-invite.md](api/gathering-invite.md) | 11 |
| 3. 장바구니와 금액 확인 | [api/cart-confirmation.md](api/cart-confirmation.md) | 5 |
| 4. 매장 수락 요청과 직원 응답 | [api/store-request.md](api/store-request.md) | 5 |
| 5. 결제·예약 결과·환불 | [api/payment-refund.md](api/payment-refund.md) | 5 |
| 6. 손님 알림함 | [api/notification.md](api/notification.md) | 2 |
| 7. 운영 조회와 직원 권한 | [api/admin.md](api/admin.md) | 3 |

## 읽는 순서

1. [비즈니스 정책](policy.md)의 요약표로 서비스 규칙을 파악한다.
2. [역할별 권한](permissions.md)과 [상태 전이표](state-transitions.md)로 누가 무엇을 언제 바꿀 수 있는지 확인한다.
3. [ERD](erd.md)에서 상태와 돈이 어느 테이블에 남는지 확인한다.
4. [API 명세](api.md)의 공통 계약을 읽은 뒤 기능별 상세로 이동한다.
5. 구현 전에는 [개발 컨벤션](convention.md)을, 테스트를 만들 때는 [검산 사례](verification-cases.md)를 기준값으로 쓴다.

## 대표 장애 시나리오

6명 중 4명이 결제한 상태에서 예약이 만료되고, 환불 도중 서버가 중단되는 상황이다. 관련 규칙은 다음 위치에 있다.

- 정책: [[POL-002] 매장 수락 절차와 결제 제한 시간](policy.md#pol-002), [[POL-017] 필수 알림과 기한](policy.md#pol-017)
- 테이블: [ERD](erd.md)의 refund·business_event·notification
- API: [미완료 환불 조회](api/admin.md#api-7-1), [첫 배포에서 이어서 검증할 사례](api.md#첫-배포에서-이어서-검증할-사례-기대-결과)
- 기대 결과: [검산 사례 9. 재배포 복구](verification-cases.md#9-재배포-복구)

## 작성·갱신 원칙

- 정책을 바꾸면 정책 문서의 변경과 함께 권한·상태 전이·ERD·API·검산 사례의 관련 위치를 같은 변경에서 갱신한다.
- 구현·테스트 결과는 문서 상태와 구분해 커밋·테스트 이름과 함께 적는다. 실행하지 않은 사례는 기대 결과로 둔다.
- 비밀 값과 실제 개인정보는 문서에 넣지 않는다. 예시는 가상의 ID·금액·식별자를 쓴다.
