# 모이온 (MOION)

여러 사람이 하나의 음식점 예약에 함께 참여해 메뉴와 비용을 합의하고 각자 결제하면, 매장은 이를 하나의 예약과 조리 주문으로 받는 단체 모임 공동 선주문·참여자별 개별결제 서비스입니다.

설계 문서는 [문서 목차](docs/README.md)에서 확인할 수 있습니다.

## 현재 상태

| 구분 | 상태 |
|---|---|
| 1단계 설계 문서 | 확정: [비즈니스 정책](docs/policy.md) v31, [ERD](docs/erd.md) v0.4(25개 테이블, [DBML](docs/erd.dbml)), [API 명세](docs/api.md) 37개, [개발 컨벤션](docs/convention.md) v0.1 |
| 구현 | 프로젝트 뼈대만 있음. 테이블·API·테스트는 아직 구현하지 않음 |
| 검증 | [검산 사례](docs/verification-cases.md)는 구현 전 기대 결과이며 테스트로 실행하지 않음 |

## 1단계에서 증명할 것

- 예약별 권한: 손님은 그 예약과의 관계로, 매장 직원은 요청마다 현재 소속 매장으로 판정합니다([역할별 권한](docs/permissions.md)).
- 다중 결제 정합성: 6명 중 4명이 결제한 뒤 예약이 만료되고, 환불 도중 서버가 중단돼도 원결제별 환불이 한 번씩만 완료되도록 복구합니다([상태 전이표](docs/state-transitions.md)).

## 기술

| 기술 | 버전 | 상태 |
|---|---|---|
| Java | 21 (Gradle toolchain) | 적용 |
| Spring Boot | 4.1.3 | 적용 |
| Gradle Wrapper | 9.7.1 | 적용 |
| Spring Data JPA, Flyway, MySQL Connector/J | Spring Boot 관리 버전 | 의존성 추가 |
| Testcontainers (MySQL) | Spring Boot 관리 버전 | 의존성 추가 |
| MySQL | 8.4.13 | 예정 |
| Spring Security 세션·CSRF | Spring Boot 관리 버전 | 예정 |
| PortOne V2 (카드 결제, KCP 본인인증 테스트 채널) | V2 | 예정 |

정확한 의존성은 [build.gradle](build.gradle)을 따릅니다.

## 문서

- [문서 목차](docs/README.md)
- [비즈니스 정책](docs/policy.md) · [역할별 권한](docs/permissions.md) · [상태 전이표](docs/state-transitions.md)
- [ERD](docs/erd.md) · [API 명세](docs/api.md) · [개발 컨벤션](docs/convention.md) · [검산 사례](docs/verification-cases.md)
