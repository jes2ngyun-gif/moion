# 3. 장바구니와 금액 확인

[API 명세](../api.md)의 공통 계약(응답 형식·인증·공통 오류·값 형식)을 함께 적용한다. 정책 ID는 [비즈니스 정책](../policy.md), 테이블은 [ERD](../erd.md)를 따른다.

<a id="api-3-1"></a>

## API · 장바구니 수량 지정

`PUT /api/gatherings/{gatheringId}/cart-items/{menuId}`

### 인증

현재 참여자 · CSRF

### Request

Path gatheringId, menuId. quantity(양의 정수), draftRevision 필수.

```json
{
  "quantity": 6,
  "draftRevision": 6
}
```

### Response

**200 OK**. quantity는 최종 수량, totalAmount는 전체 공동 장바구니 합계다.

```json
{
  "gatheringId": 10,
  "menuId": 8,
  "quantity": 6,
  "unitPrice": 20000,
  "totalAmount": 120000,
  "draftRevision": 7
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `MENU_NOT_FOUND` | 매장에 없는 메뉴 |
| 422 | `MENU_NOT_PREORDERABLE` | 주류·판매 중지·선주문 제외 메뉴 |
| 409 | `DRAFT_REVISION_MISMATCH` | 분담안 변경 |
| 409 | `GATHERING_NOT_EDITABLE` | 편집 종료 |

### 비즈니스 규칙

- 로그인한 참여자의 모임과 메뉴의 매장을 대조하고 서버 가격으로 다시 계산한다. 같은 수량을 반복해도 누적 합산하지 않는다. 금액이 달라진 사람은 다시 확인한다.

- `draftRevision`은 모임 상세 또는 최종 확인 화면에서 읽은 정수다. 옛 버전은 409와 함께 재조회를 안내한다. 현재 버전에서 실제 변경이 없으면 기존 버전을 반환하고 재확인 기준도 유지한다.

<a id="api-3-2"></a>

## API · 장바구니 메뉴 삭제

`DELETE /api/gatherings/{gatheringId}/cart-items/{menuId}`

### 인증

현재 참여자 · CSRF

### Request

Path gatheringId, menuId. Query draftRevision 필수. 본문 없음.

### Response

**200 OK**. 마지막 품목을 지우면 빈 장바구니를 편집할 수 있다.

```json
{
  "gatheringId": 10,
  "removedMenuId": 8,
  "totalAmount": 0,
  "draftRevision": 8
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 409 | `GATHERING_NOT_EDITABLE` | 편집 종료 |
| 409 | `DRAFT_REVISION_MISMATCH` | 낡은 편집 |
| 404 | `GATHERING_NOT_FOUND` | 모임 접근 불가 |

### 비즈니스 규칙

- 항목 삭제와 재계산을 함께 저장한다. 낡은 화면의 재시도는 재조회로 안내하고 삭제·금액 변경을 중복 적용하지 않는다. 빈 주문서는 확정할 수 없다.
- 품목 1개 이상이고 참여자별 확정액 합과 주문서 총액이 맞을 때만 매장 수락을 요청한다.

- `draftRevision`은 모임 상세 또는 최종 확인 화면에서 읽은 정수다. 옛 버전은 409와 함께 재조회를 안내한다. 현재 버전에서 실제 변경이 없으면 기존 버전을 반환하고 재확인 기준도 유지한다.

<a id="api-3-3"></a>

## API · 내 동반인 구성

`PUT /api/gatherings/{gatheringId}/participants/me/companions`

### 인증

현재 참여자 본인 · CSRF

### Request

Path gatheringId. draftRevision과 companions 배열 필수. 각 shareUnits는 0 또는 1. 빈 배열은 동반인 0명.

```json
{
  "draftRevision": 7,
  "companions": [
    {
      "shareUnits": 0
    }
  ]
}
```

### Response

**200 OK**. 예시에서는 계정 6명에 0몫 동반인 1명을 추가한다. 본인의 1몫은 유지된다.

```json
{
  "gatheringId": 10,
  "memberId": 42,
  "companionCount": 1,
  "myShareUnits": 1,
  "visitorCount": 7,
  "draftRevision": 8
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 422 | `INVALID_SHARE_UNITS` | 동반인 몫이 0·1 밖 |
| 422 | `PARTY_SIZE_OUT_OF_RANGE` | 최대 방문 인원 초과 |
| 409 | `DRAFT_REVISION_MISMATCH` | 옛 분담안 |
| 409 | `GATHERING_NOT_EDITABLE` | 편집 종료 |

### 비즈니스 규칙

- 로그인 회원이 데려올 동반인 구성을 통째로 지정한다. 0몫도 방문 인원 1명이며 이름·나이로 분담 제외를 자동 판정하지 않는다.
- 분담 제외로 부담이 늘어나는 사람에게 변경 전후 금액·이유를 보여 주고 별도 동의를 받는다.

- `draftRevision`은 모임 상세 또는 최종 확인 화면에서 읽은 정수다. 옛 버전은 409와 함께 재조회를 안내한다. 현재 버전에서 실제 변경이 없으면 기존 버전을 반환하고 재확인 기준도 유지한다.

<a id="api-3-4"></a>

## API · 최종 확인 화면 조회

`GET /api/gatherings/{gatheringId}/final-check`

### 인증

현재 참여자. 예약자는 최종 참여자 명단과 동반인 수도 조회한다.

### Request

Path gatheringId. 본문 없음.

### Response

**200 OK**. 일반 참여자 예시. 예약자 응답에는 participants[{memberId,name,companionCount,confirmed}]를 추가한다. 동의가 필요하면 exclusionConsent={beforeAmount,afterAmount,reason}이다.

```json
{
  "gatheringId": 10,
  "draftRevision": 7,
  "timeSlotId": 5,
  "startsAt": "2026-11-28T19:00:00+09:00",
  "visitorCount": 6,
  "shareCount": 6,
  "totalAmount": 120000,
  "myShareUnits": 1,
  "myAmount": 20000,
  "confirmed": false,
  "exclusionConsent": null,
  "refundTerms": {
    "freeUntilMinutesBefore": 60,
    "latePenaltyPercent": 15,
    "noShowPercent": 20,
    "noShowPenalty": 4000,
    "noShowRefund": 16000
  },
  "notice": "예약 확정 후 한 사람만 불참해도 그 사람의 결제만 따로 취소할 수 없어요. 예약 전체 취소는 예약자만 신청할 수 있어요.",
  "myAmountEligible": true,
  "minimumChargeAmount": null
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `GATHERING_NOT_FOUND` | 조회 권한 없음 |
| 409 | `GATHERING_NOT_EDITABLE` | 확정 이후에는 당시 주문서·예약 결과 조회 |

### 비즈니스 규칙

- 조회로 확인·동의를 기록하지 않는다. 개별 취소 제한은 단순 불참에 적용한다. 중복 결제나 매장 오처리에 대한 문의는 접수할 수 있다. 본인 금액, 방문 일시·인원, 분담 몫, 확정 후 환불·노쇼 기준을 화면 하나에서 보여 준다.
- 12만원을 6명이 각 2만원씩 부담하면 시연용 노쇼 20%는 4천원, 환불 예정액은 1만6천원이다. 위약금 수치는 모이온 가상 매장 기준이다.

### 부담이 늘어나는 결제자의 예

120,000원을 8몫으로 나누면 1몫 15,000원이다. 동반인 2명의 몫을 제외해 6몫이 되면 1몫은 20,000원이다. 이 변경으로 부담이 늘어난 결제자의 화면에는 `exclusionConsent: {"beforeAmount":15000,"afterAmount":20000,"reason":"동반인 2명 분담 제외"}`를 표시한다. 금액 확인 시 그 사람이 동의했는지 따로 기록한다.

- 예약자용 `participants`에는 `memberId`, `name`, `companionCount`, `confirmed`, `joinedAt`을 제공한다. `joinedAt`은 현재 참여 이력을 식별하는 시각이다. 개인 화면에는 본인의 청구액 판정 `myAmountEligible`를, 예약자 화면에는 금액 조정이 필요한 현재 참여자 ID 목록 `ineligibleMemberIds`도 표시한다. `minimumChargeAmount`는 해당 채널에서 확인된 양수 하한(원)이며 미확인 시 `null`이다. 이때도 최종 청구액 0원은 거부한다.

<a id="api-3-5"></a>

## API · 금액 확인·분담 제외 동의

`POST /api/gatherings/{gatheringId}/confirmations`

### 인증

현재 참여자 본인 · CSRF

### Request

Path gatheringId. draftRevision·timeSlotId·amount(화면에 표시된 원화)·confirmAmount 필수. 부담 증가 시 agreeToShareExclusion=true도 필수.

```json
{
  "draftRevision": 7,
  "timeSlotId": 5,
  "amount": 20000,
  "confirmAmount": true,
  "agreeToShareExclusion": false
}
```

### Response

**201 Created · 최초 / 200 OK · 이미 같은 확인**. 제외 동의가 필요 없는 사람의 shareExclusionConsentId는 null.

```json
{
  "amountConfirmationId": 51,
  "shareExclusionConsentId": null,
  "draftRevision": 7,
  "confirmed": true
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 409 | `DRAFT_REVISION_MISMATCH` | 낡은 버전·회차·금액 |
| 422 | `CONSENT_REQUIRED` | 필요한 동의를 하지 않음 |
| 409 | `GATHERING_NOT_EDITABLE` | 편집 종료 |
| 422 | `CONFIRMATION_REQUIRED` | 본인 확인 미선택 |

### 비즈니스 규칙

- 모임 잠금 안에서 서버가 금액·회차·분담 제외 필요 여부를 다시 계산한다. 확인 금액·회차·환불 기준 사본과 별도의 동의 기록을 연결해 저장한다.
- 이미 유효한 확인을 같은 내용으로 보내도 행이 늘지 않는다. 편집 복귀로 버전만 바뀌었고 재확인 대상이 아닌 사람의 유효한 확인은 다시 사용한다. 메뉴 확정과 요청 생성은 매장 수락 요청에서 한다.

- 확인 대상은 현재 서버가 계산한 금액과 회차다. 분담 제외로 부담이 늘어나는 사람은 이번 변경 전후 금액과 이유에 동의해야 한다. 이 내용이 바뀐 뒤에는 과거 동의를 재사용하지 않는다. 0몫 동반인도 방문 인원 1명으로 계산한다.
