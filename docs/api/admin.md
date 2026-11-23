# 7. 운영 조회와 직원 권한

[API 명세](../api.md)의 공통 계약(응답 형식·인증·공통 오류·값 형식)을 함께 적용한다. 정책 ID는 [비즈니스 정책](../policy.md), 테이블은 [ERD](../erd.md)를 따른다.

<a id="api-7-1"></a>

## API · 미완료 환불 조회

`GET /api/admin/refunds`

### 인증

운영자 전용 조회

### Request

Query status(선택), page·size. 미완료 항목의 receivedAt·refundId 오름차순. 상태값은 RECEIVED/REQUESTED/FAILED/HOLD.

### Response

**200 OK**. summary는 페이지·필터와 관계없는 전체 미완료 기준. 0건이면 oldestAgeSeconds는 null. 최근 대조 결과는 마지막으로 대조한 환불의 기록에서 가져오며 이력이 없으면 null.

```json
{
  "asOf": "2026-11-28T17:00:00+09:00",
  "summary": {
    "incompleteCount": 1,
    "oldestAgeSeconds": 600,
    "lastReconciledAt": "2026-11-28T16:57:00+09:00",
    "lastReconcileResult": "PROCESSING"
  },
  "items": [
    {
      "refundId": 71,
      "paymentId": 301,
      "reservationId": 22,
      "amount": 20000,
      "status": "REQUESTED",
      "firstAttemptedAt": "2026-11-28T16:50:03+09:00",
      "lastReconciledAt": "2026-11-28T16:57:00+09:00",
      "lastReconcileResult": "PROCESSING",
      "holdReason": null
    }
  ],
  "page": 0,
  "size": 20,
  "hasNext": false
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 403 | `OPERATOR_REQUIRED` | 운영자 아님 |
| 400 | `INVALID_INPUT` | 미지원 상태·페이지 |

### 비즈니스 규칙

- 조회만으로 환불을 재전송하지 않는다. 미완료 대조는 주기 작업에서 수행한다. PG 성공 건을 특정하면 DB 완료·알림을 함께 저장한다.
- 진행 중은 재조회, 재시도 안전성이 확인된 경우에만 저장한 키·요청으로 재개한다. 3시간 이후 판별 불명은 HOLD, 운영자에게 원인·마지막 대조 결과를 보여 준다. 금액이 같은 다른 취소를 임의로 연결하지 않는다.

- `firstAttemptedAt`은 첫 PG 시도 전 `null`이다. `lastReconciledAt`과 `lastReconcileResult`는 첫 대조 전 `null`이다. `holdReason`은 보류 시 표시한다. 결과를 모르는 금액은 누적 한도에 포함한다.
- 별도의 내부 조회로 종료 예약의 미확정 원결제도 찾는다. PG 승인과 원주문서가 일치하면 남은 금액만 환불 접수한다. 불일치 수납은 원결제 단위 운영 확인 대상으로 표시한다. 이 API의 미완료 환불 건수와 미확정 결제 건수는 별도로 센다.

<a id="api-7-2"></a>
## API · 직원 권한 부여

`POST /api/admin/store-staff`

### 인증

운영자 · CSRF

### Request

storeId·memberId는 필수 Long이고 `grantRequestId`는 필수 문자열(UUID)이다. 운영 화면은 부여 동작마다 새 ID를 생성하고 응답 유실 시 같은 ID를 사용한다. 부여자는 세션으로 정한다.

```json
{
  "storeId": 1,
  "memberId": 55,
  "grantRequestId": "59c70eec-6067-4b7d-98b8-1813e0e251d4"
}
```

### Response

**201 Created · 신규 부여 / 200 OK · 이미 유효하거나 동일 요청 재전송**. 처리한 부여 이력의 ID와 현재 상태를 반환한다. 다른 매장의 권한을 함께 부여하지 않는다.

```json
{
  "storeStaffId": 61,
  "storeId": 1,
  "memberId": 55,
  "status": "ACTIVE",
  "grantedAt": "2026-11-28T10:00:00+09:00"
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 409 | `GRANT_REQUEST_CONFLICT` | 이미 사용한 부여 요청 ID를 다른 대상 또는 매장으로 재사용 |
| 403 | `OPERATOR_REQUIRED` | 운영자 아님 |
| 404 | `STORE_OR_MEMBER_NOT_FOUND` | 대상이 없음 |
| 409 | `MEMBER_NOT_ACTIVE` | 유효 회원이 아님 |

### 비즈니스 규칙

- 직원·매장당 활성 부여는 1개. 같은 부여 재시도는 기존 행을 반환한다. 회수 후 재부여하면 새 행을 만들어 이전 기록을 보존한다.
- 이 API로 운영자 권한을 부여할 수 없다.

- 요청 ID·대상·매장과 처리된 `storeStaffId`의 연결은 활성 권한과 별도로 보존한다. 같은 ID는 기존 부여 이력의 현재 상태를 200으로 반환한다. 회수 뒤 옛 요청이 와도 `REVOKED`를 반환하고 활성 권한은 0건이다. 명시적 재부여만 새 요청 ID로 실행한다. 운영자는 전용 조회 화면 또는 명령에서 대상 회원·매장·현재 부여 이력을 확인한다.
- ERD 반영: `store_staff_grant_request(grant_request_id PK, store_staff_id NOT NULL FK → store_staff.id)`가 각 성공 요청 ID와 불변 부여 이력의 연결을 보존한다. 한 부여 이력에는 여러 요청 ID가 연결될 수 있다. 운영자 자격을 확인한 뒤 같은 ID의 대상 회원·매장은 연결된 이력과 대조한다. 새 권한 생성 또는 기존 활성 권한 반환과 요청 연결 저장은 같은 트랜잭션으로 처리한다. 활성 권한이 회수돼도 연결은 유지한다.

<a id="api-7-3"></a>

## API · 직원 권한 회수

`DELETE /api/admin/store-staff/{storeStaffId}`

### 인증

운영자 · CSRF

### Request

Path storeStaffId. 부여 이력 하나를 지정한다. 본문 없음.

### Response

**200 OK**. 회수한 최초 시각. 재부여된 권한은 별도 ID다.

```json
{
  "storeStaffId": 61,
  "status": "REVOKED",
  "revokedAt": "2026-11-28T11:00:00+09:00"
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 403 | `OPERATOR_REQUIRED` | 운영자 아님 |
| 404 | `STORE_STAFF_NOT_FOUND` | 지정한 부여 이력이 없음 |

### 비즈니스 규칙

- 회수한 사람·시각을 기록한다. 같은 이력을 다시 회수해도 새 기록을 만들지 않는다. 옛 ID로 새 부여분을 회수할 수 없다.
- 같은 세션에서 회수 직전 업무함 200, 회수 커밋 후 다음 업무함 요청 403. 손님으로서 자기 예약을 조회하는 권한은 예약과의 관계로 판정한다.
