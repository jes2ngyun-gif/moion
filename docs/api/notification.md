# 6. 손님 알림함

[API 명세](../api.md)의 공통 계약(응답 형식·인증·공통 오류·값 형식)을 함께 적용한다. 정책 ID는 [비즈니스 정책](../policy.md), 테이블은 [ERD](../erd.md)를 따른다.

<a id="api-6-1"></a>

## API · 알림함 조회

`GET /api/notifications`

### 인증

로그인 회원 본인

### Request

Query page·size, unreadOnly(Boolean) 선택. createdAt·notificationId 내림차순.

### Response

**200 OK**. 수신자 본인의 앱 알림함. 기한이 걸린 안내는 저장된 deadlineAt을 반환한다.

```json
{
  "items": [
    {
      "notificationId": 81,
      "type": "REFUND_RECEIVED",
      "reservationId": 22,
      "refundId": 71,
      "summary": "20,000원 환불을 접수했어요.",
      "createdAt": "2026-11-28T16:50:00+09:00",
      "deadlineAt": null,
      "readAt": null
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
| 400 | `INVALID_INPUT` | 페이지 범위·필터 값 오류 |

### 비즈니스 규칙

- 이 API의 조회는 읽음을 표시하지 않는다. 업무 결과와 필수 알림은 같은 트랜잭션에 저장한다. 업무 사건 또는 개별 환불 ID·알림 종류·수신자로 중복을 막는다.
- 결제 마감은 예약 결과와 같은 값을 쓴다. 만료 6 + 환불 접수 4 + 완료 4 = 손님 14건, 매장 업무함은 별도 1건이다.

- 화면 이동에 필요한 대상 ID는 사건 종류별로 반환한다. 확인 요청은 `gatheringId`, 매장 수락 요청의 결과는 `gatheringId`, `storeRequestId`, 결제 시작·결과는 `reservationId`, 환불은 당시 `reservationId`, `refundId`를 제공한다. 결제 시작 안내는 `paymentStartDeadline`과 `paymentDeadline`을 함께 반환한다. 해당하지 않는 대상 ID·마감은 생략한다.

<a id="api-6-2"></a>

## API · 알림 읽음 표시

`PATCH /api/notifications/{notificationId}/read`

### 인증

알림 수신자 본인 · CSRF

### Request

Path notificationId. 본문 없음.

### Response

**200 OK**. 최초 읽은 서버 시각을 반환한다.

```json
{
  "notificationId": 81,
  "readAt": "2026-11-28T17:05:00+09:00"
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `NOTIFICATION_NOT_FOUND` | 본인 소유 알림이 아님 |

### 비즈니스 규칙

- 두 번 눌러도 처음의 readAt을 보존한다. 읽음 처리는 예약·환불 상태 또는 마감을 바꾸지 않는다.
