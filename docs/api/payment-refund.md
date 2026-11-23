# 5. 결제·예약 결과·환불

[API 명세](../api.md)의 공통 계약(응답 형식·인증·공통 오류·값 형식)을 함께 적용한다. 정책 ID는 [비즈니스 정책](../policy.md), 테이블은 [ERD](../erd.md)를 따른다.

<a id="api-5-1"></a>

## API · 결제 시작

`POST /api/reservations/{reservationId}/payments`

### 인증

예약의 원래 주문서에서 본인 몫을 가진 결제 예정자 · CSRF

### Request

Path reservationId. 본문 없음. 브라우저에서 가격·결제자·결제 성공 상태를 지정하지 않는다.

### Response

**201 Created · 새 결제 / 200 OK · 기존 사용 가능 결제**. paymentId는 모이온 숫자 ID, portonePaymentId는 결제창 SDK의 paymentId에 넘기는 문자열. amount를 SDK totalAmount에 전달한다.

```json
{
  "paymentId": 301,
  "reservationId": 22,
  "payerShareId": 54,
  "portonePaymentId": "moion-pay-example-301",
  "amount": 20000,
  "storeId": "store-example",
  "channelKey": "channel-key-example",
  "orderName": "모이온 단체 선주문",
  "currency": "CURRENCY_KRW",
  "payMethod": "CARD",
  "paymentStartDeadline": "2026-11-28T16:45:00+09:00",
  "paymentDeadline": "2026-11-28T16:50:00+09:00",
  "returnPath": "/payments/301/return"
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `RESERVATION_NOT_FOUND` | 접근 권한 없는 예약 |
| 403 | `NOT_RESERVATION_PAYER` | 본인 결제 예정 몫 없음 |
| 409 | `RESERVATION_NOT_PAYABLE` | 결제 대기 상태가 아님 |
| 409 | `PAYMENT_ALREADY_COUNTED` | 이미 성공 반영된 몫 |
| 422 | `PAYMENT_START_CLOSED` | 서버 시작 기록이 시작 마감과 같거나 늦음 |

### 비즈니스 규칙

- 시작 시 원래 예약·주문서·결제자 몫을 묶어 금액을 고정한다. 같은 몫에 진행 중인 사용 가능 시도는 재사용하며 결과 불명인 시도는 조회로 안내한다.
- 테스트 카드 결제창을 사용한다. 시작 응답만으로 결제 성공·예약 확정은 일어나지 않는다. 주문서가 바뀐 뒤 옛 시도로 새 결제를 시작할 수 없다.
- 시작 마감 이후에는 새 결제창을 여는 응답을 주지 않는다. 이미 시작한 건의 결과 확인은 완료 확인·웹훅 경로에서 계속 받는다.

### 복귀와 재요청

- 브라우저는 `returnPath`를 서비스의 복귀 주소로 사용한다. 복귀 페이지는 경로의 내부 숫자 ID로 결제 완료 확인을 호출한다. 포트원이 돌려준 문자열 ID는 서버 대조에 쓴다.
- 결과가 불명인 기존 시도가 있으면 202와 기존 ID를 반환한다. 이 응답으로 새 결제창을 열지 않는다. 실패·무승인이 확정되고 시작 기한 전인 경우에만 새 시도를 발급한다.

```json
{"paymentId":301,"reservationId":22,"nextAction":"CHECK_PAYMENT","checkPath":"/api/payments/301/complete"}
```

<a id="api-5-2"></a>

## API · 결제 완료 확인

`POST /api/payments/{paymentId}/complete`

### 인증

원결제 소유 회원 · CSRF

### Request

Path paymentId는 모이온 내부 ID. 본문 없음. 브라우저는 귀환 후 확인을 요청한다.

### Response

**200 OK · 확인 / 202 Accepted · PG 확인 또는 환불 처리 중**. counted는 이 원결제가 해당 예약의 몫에 인정된 이력. 늦은 승인은 원결제 상태와 연결된 환불 상태를 따로 표시한다.

```json
{
  "paymentId": 301,
  "pgStatus": "PAID",
  "counted": true,
  "recordedPaidAt": "2026-11-28T16:43:10+09:00",
  "reservationId": 22,
  "reservationStatus": "PAYMENT_PENDING",
  "refundStatus": null
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `PAYMENT_NOT_FOUND` | 본인 소유 결제 없음 |
| 409 | `PAYMENT_FAILED` | PG에서 실패·승인 없는 종료가 확정됨 |
| 409 | `PAYMENT_VERIFICATION_MISMATCH` | PG 상점·식별자·통화·금액 등이 당시 주문서와 불일치 |
| 503 | `PG_UNAVAILABLE` | 단건 조회 일시 불가 |

### 비즈니스 규칙

- PG 단건 조회는 업무 잠금 밖에서 한다. 원결제 ID·상점·주문서 연결·원화 금액·상태를 검증한 뒤 모임 → 예약 순으로 잠가 웹훅과 같은 반영 로직을 실행한다. 대기 중인 외부 결과는 202로 표시한다.
- 최초 유효 완료 기록 시각을 보존한다. 결제 대기이며 전원 각각의 몫이 마감 전이면 예약을 1회 확정한다. 이미 만료·종료됐거나 완료 기록이 마감과 같거나 늦으면 옛 금액으로 전액 환불을 접수하고 예약을 다시 열지 않는다.
- 같은 승인 재통지는 성공을 재반영하지 않는다. 다른 원결제가 같은 몫에 또 승인되면 추가분만 환불한다. 불일치가 실제 수납을 동반하면 대조 대상으로 남긴다.

### 늦은 승인 응답 예시 · 202 Accepted

옛 20,000원 승인이 조기 종료 후 발견된 경우다. 새 주문서의 18,000원 결제는 별개로 진행할 수 있다.

```json
{
  "paymentId": 401,
  "pgStatus": "PAID",
  "counted": false,
  "recordedPaidAt": "2026-11-28T16:46:00+09:00",
  "reservationId": 32,
  "reservationStatus": "EARLY_CLOSED",
  "refundStatus": "RECEIVED"
}
```

PG가 아직 승인 여부를 확정하지 않았으면 같은 응답에서 pgStatus는 조회된 진행 상태, recordedPaidAt과 refundStatus는 null이다. 조회 자체가 일시적으로 실패하면 503으로 재조회를 안내한다.

- 확정 시 예약·결제자 전원 알림·매장 준비 확정 항목을 함께 저장한다. 실제 수납과 주문 내용이 다르면 미대조 결제 이력을 남긴다. 늦은 승인 반영 중 좌석 해제가 필요하면 결제 잠금을 끝낸 뒤 만료 작업이 모임 → 회차 → 예약 순서로 잠그고 상태를 다시 검사한다.

<a id="api-5-3"></a>

## API · PortOne 웹훅 수신

`POST /api/webhooks/portone`

### 인증

PortOne 서버 · 원문 서명 검증

### Request

Header webhook-id, webhook-timestamp, webhook-signature. 원본 본문 바이트로 검증한 후 해석한다. 예시는 결제 승인 이벤트.

```json
{
  "type": "Transaction.Paid",
  "timestamp": "2026-11-28T07:43:10.000Z",
  "data": {
    "storeId": "store-example",
    "paymentId": "moion-pay-example-301",
    "transactionId": "tx-example"
  }
}
```

### Response

**200 OK · 정상 수신 또는 이미 저장한 이벤트**. 외부 콜백은 HTTP 200 빈 본문을 반환한다. 업무 성공은 서버 재조회·반영 결과에서 확인한다.

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 400 | `WEBHOOK_INVALID` | 유효하지 않은 이벤트 형식 |
| 401 | `WEBHOOK_SIGNATURE_INVALID` | 원문 서명 또는 시각 검증 실패 |
| 503 | `WEBHOOK_NOT_STORED` | 재처리 가능한 상태로 저장하지 못함 |

### 비즈니스 규칙

- 유효한 이벤트를 유일한 webhook-id로 내구성 있게 저장한 뒤 응답한다. 이 지점의 200은 수신 확인이다. 서명 실패 시 결제 인원·예약·환불 변화 0건이다.
- `Transaction.CancelPending`은 비동기 취소 접수 사실을 기록한다. 이 이벤트만으로 환불 완료 알림을 생성하지 않는다. PG 재조회에서 원결제와 해당 취소 ID를 대조하여 그 취소의 상태가 `SUCCEEDED`로 확인된 때만 환불 완료와 완료 알림을 같은 트랜잭션에 한 번 저장한다. `REQUESTED`면 재조회하고, 이미 완료한 뒤 늦게 온 접수 통지는 상태를 되돌리지 않는다.
- 결제 승인·취소 관련 이벤트를 처리할 때 PG를 재조회한다. 성공 처리는 브라우저 귀환과 동일하고 취소 성공은 특정된 환불 건에 1회 반영한다. 이미 처리한 이벤트의 첫 결과는 보존한다.
- 처리 전 중단되면 RECEIVED에서 재개한다. 확인할 수 없는 원결제·취소는 사유와 함께 대조 대상으로 남기고 서명이 유효한 미지원 유형은 IGNORED로 마친다.

<a id="api-5-4"></a>

## API · 결제 대기 조기 종료

`POST /api/reservations/{reservationId}/early-close`

### 인증

해당 예약의 예약자 · CSRF

### Request

Path reservationId. 본문 없음. 화면에서 조기 종료 시 좌석 해제·환불·메뉴 편집 복귀를 안내한다.

### Response

**202 Accepted · 환불 진행 중 / 200 OK · 남은 환불 없음**. releasedSeats와 refundCount는 이 결정으로 처리한 수량. 반복 응답의 금액과 좌석은 누적하지 않는다.

```json
{
  "reservationId": 42,
  "reservationStatus": "EARLY_CLOSED",
  "gatheringStatus": "EDITING",
  "releasedSeats": 6,
  "refundCount": 4
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `RESERVATION_NOT_FOUND` | 예약이 없거나 당시 주문서의 결제 예정 명단에 없는 계정. 두 경우 같은 응답 |
| 403 | `NOT_GATHERING_HOST` | 해당 예약의 결제 예정 명단에 있으나 예약자가 아닌 회원 |
| 409 | `RESERVATION_NOT_EARLY_CLOSABLE` | 확정·만료·다른 종료 결정 선행 |

### 비즈니스 규칙

- 모임 → 회차 → 예약 잠금에서 종료 기록·좌석 해제·기존 주문서 보존·편집 복귀·분담안 버전 증가·환불 접수·알림을 함께 저장한다. 현재 모임 참여자는 같은 회차 중복 검사 대상에 계속 포함된다.
- 마지막 결제 유효 기록이 마감 전이고 조기 종료 기록보다 빠르면 전원 결제 확정, 두 기록이 같으면 조기 종료다. 이미 만료 조건이 먼저 성립했다면 결제 기한 만료로 처리한다.
- 남은 4건 중 PG 취소 2건이 끝났어도 모이온 DB 완료가 1건일 수 있다. 고객에게 접수와 완료를 구분해 표시한다.

- 응답의 예약 ID로 종료 후에도 본인 결과를 조회할 수 있다. 환불 접수와 완료 사이에는 PG 상태를 대조한다. 조기 종료 결과는 사건 직전 명단 전원과 좌석을 확보했던 매장에 알린다.

<a id="api-5-5"></a>

## API · 예약 결과·결제·환불 조회

`GET /api/reservations/{reservationId}`

### 인증

해당 예약에 고정된 주문서의 결제 예정자(`payer_share.member_id` 일치). 개인 결제·환불 내역은 원결제자 본인에게만 제공.

### Request

Path reservationId. 본문 없음. 현재 모임의 최신 주문서 대신 해당 예약에 고정된 주문서를 조회한다.

### Response

**200 OK**. 미결제자도 종료와 집계 결과를 보며, myPayments는 빈 배열이다. countedPayerCount는 이 예약에 유효하게 반영됐던 사람 수다.

```json
{
  "reservationId": 22,
  "orderSheetId": 28,
  "reservationStatus": "EXPIRED",
  "visitorCount": 6,
  "payerCount": 6,
  "countedPayerCount": 4,
  "paymentStartDeadline": "2026-11-28T16:45:00+09:00",
  "paymentDeadline": "2026-11-28T16:50:00+09:00",
  "myPayments": [
    {
      "paymentId": 301,
      "amount": 20000,
      "refunds": [
        {
          "refundId": 71,
          "amount": 20000,
          "status": "RECEIVED",
          "completedAt": null
        }
      ],
      "paymentStatus": "PAID"
    }
  ]
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `RESERVATION_NOT_FOUND` | 예약이 없거나 이력을 조회할 권한 없음 |

### 비즈니스 규칙

- 같은 사람이 새 주문서에서 결제할 18,000원과 옛 예약의 20,000원 환불을 예약 ID·주문서 ID별로 구분한다.
- PG가 완료한 건만 COMPLETED로 표시하고 처리 중·보류 건을 완료 금액에 포함하지 않는다. 조회는 새 PG 요청을 만들지 않는다.

- 이미 나간 원결제자도 본인의 옛 예약·환불을 조회한다. 같은 모임의 새 주문서에만 참여한 사람은 옛 예약에 접근할 수 없다. `myPayments[].paymentStatus`는 결제 시도의 표시 상태(`PENDING`, `PAID`, `FAILED`, `UNKNOWN`)이며 환불 상태는 `refunds[]`에서 각각 확인한다.
