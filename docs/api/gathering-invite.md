# 2. 모임과 초대

[API 명세](../api.md)의 공통 계약(응답 형식·인증·공통 오류·값 형식)을 함께 적용한다. 정책 ID는 [비즈니스 정책](../policy.md), 테이블은 [ERD](../erd.md)를 따른다.

<a id="api-2-1"></a>

## API · 예약 가능 회차 조회

`GET /api/time-slots`

### 인증

로그인 회원

### Request

Query date 필수, 매장 현지 날짜 YYYY-MM-DD. 예: ?date=2026-11-28. 단일 가상 매장 기준.

### Response

**200 OK**. remainingSeats는 조회 시점 좌석, requestableNow는 시간 조건 충족 여부다. 인원 범위는 예시 매장 설정이다.

```json
{
  "date": "2026-11-28",
  "items": [
    {
      "timeSlotId": 5,
      "startsAt": "2026-11-28T19:00:00+09:00",
      "endsAt": "2026-11-28T20:30:00+09:00",
      "capacity": 20,
      "remainingSeats": 6,
      "minParty": 2,
      "maxParty": 8,
      "lastRequestAt": "2026-11-28T17:00:00+09:00",
      "requestableNow": true
    }
  ]
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 422 | `DATE_OUT_OF_RANGE` | 요청일 기준 예약 가능 기간 밖 |

### 비즈니스 규칙

- 시작 120분 전, 매장 영업시간, 60분 응답 가능 시간, 요청일부터 30일 뒤까지의 조건을 매장 수락 요청과 같은 함수로 계산한다. 마지막 허용 시각은 포함한다.
- 영업 11~23시, 낮 12시 회차의 최종 요청은 전날 22:00:00. 당일 09:30은 거부한다. 조회는 좌석을 확보하지 않는다.

<a id="api-2-2"></a>

## API · 모임 생성

`POST /api/gatherings`

### 인증

본인인증 완료 회원 · CSRF

### Request

timeSlotId 필수 Long. 예약자는 로그인 회원 본인이다.

```json
{
  "timeSlotId": 5
}
```

### Response

**201 Created**. 예약자 자신의 참여 1건과 최초 링크 1개를 포함한다.

```json
{
  "gatheringId": 10,
  "hostMemberId": 42,
  "timeSlotId": 5,
  "gatheringStatus": "EDITING",
  "draftRevision": 1,
  "inviteLink": {
    "version": 1,
    "url": "https://example.com/i/example-token"
  }
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `TIME_SLOT_NOT_FOUND` | 회차 없음 |
| 409 | `DUPLICATE_SLOT_PARTICIPATION` | 본인의 같은 회차 진행 중 모임 존재 |
| 422 | `REQUEST_WINDOW_CLOSED` | 선택 회차의 요청 가능 기간 또는 최종 마감 경과 |

### 비즈니스 규칙

- 모임·예약자 참여·최초 링크를 함께 저장한다. 좌석 확보는 매장 수락 시점이다.
- 중복 생성이 경합해도 회원·회차에 활성 참여 1건만 남는다.

- 성공 응답이 끊기면 내 정보의 `activeGatherings`로 진입한다. 중복이면 `details.conflictingGatheringId`에 본인이 이미 참여 중인 모임 ID를 반환한다.

<a id="api-2-3"></a>

## API · 모임 상세 조회

`GET /api/gatherings/{gatheringId}`

### 인증

현재 참여자(예약자 포함)

### Request

Path gatheringId. 본문 없음.

### Response

**200 OK**. menus와 cartItems는 편집 데이터, orderSheet는 현재 시도의 확정 내역이다. 요청·예약 ID는 생성 전 null. 로그인한 참여자에게 유효한 링크만 내려준다. lastInviteVersion은 마지막 발급 버전이며 유효 링크가 없을 때도 조회할 수 있다.

```json
{
  "gatheringId": 10,
  "gatheringStatus": "EDITING",
  "draftRevision": 7,
  "timeSlotId": 5,
  "visitorCount": 6,
  "payerCount": 6,
  "menus": [
    {
      "menuId": 8,
      "name": "고기 1인분",
      "unitPrice": 20000
    }
  ],
  "cartItems": [
    {
      "menuId": 8,
      "quantity": 6
    }
  ],
  "orderSheet": null,
  "inviteLink": {
    "version": 2,
    "url": "https://example.com/i/example-token-v2"
  },
  "storeRequestId": null,
  "reservationId": null,
  "lastInviteVersion": 2,
  "myJoinedAt": "2026-11-28T12:00:00.000001+09:00",
  "blockedMembers": [
    {
      "memberId": 43,
      "blockId": 71,
      "displayName": "차단된 회원 예시"
    }
  ]
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `GATHERING_NOT_FOUND` | 없거나 이 상세에 접근할 수 없는 모임 |

### 비즈니스 규칙

- 메뉴 편집에서는 해당 매장의 판매 중 선주문 가능 메뉴와 현재 가격을 조회한다. 확정 상태에서는 주문서 품목·단가·총액을 읽는다.
- 확정으로 닫힌 초대 링크는 null. 거절·철회 후 다시 편집해도 예약자가 새로 발급하기 전까지 닫힌 옛 링크는 돌아오지 않는다.
- 이전 주문서에 연결된 결제·환불 상세는 해당 예약 결과에서 조회한다.
- 편집 화면에 새 가격이 반영돼 본인 금액이 바뀌면 해당 참여자 재확인을 요구한다. 저장 시 금액 확인과 매장 수락 요청 시 서버의 금액·회차를 다시 대조한다.

### 응답 예시 2 · 주문서 확정 뒤 가격 변경

매장이 현재 단가를 22,000원으로 바꿨어도 주문서 118의 6인분은 120,000원이다. 편집용 메뉴와 장바구니는 잠긴 화면에서 빈 배열로 반환한다.

```json
{
  "gatheringId": 10,
  "gatheringStatus": "EDIT_LOCKED",
  "draftRevision": 7,
  "timeSlotId": 5,
  "visitorCount": 6,
  "payerCount": 6,
  "menus": [],
  "cartItems": [],
  "orderSheet": {
    "orderSheetId": 118,
    "version": 2,
    "items": [
      {
        "menuId": 8,
        "name": "고기 1인분",
        "unitPrice": 20000,
        "quantity": 6,
        "lineAmount": 120000
      }
    ],
    "totalAmount": 120000
  },
  "inviteLink": null,
  "lastInviteVersion": 2,
  "storeRequestId": 131,
  "reservationId": null,
  "myJoinedAt": "2026-11-28T12:00:00.000001+09:00"
}
```

- 편집 중인 예약자에게만 `blockedMembers`를 제공한다. 첫 예시는 예약자 화면이다. `myJoinedAt`은 본인의 현재 참여 시작 시각이다. 링크 폐기 후에도 `lastInviteVersion`은 마지막 발급 번호를 유지하고 `inviteLink`는 `null`이다.

<a id="api-2-4"></a>

## API · 초대 링크 미리보기

`GET /api/invites/{token}`

### 인증

로그인 회원

### Request

Path token 필수 문자열. 본문 없음.

### Response

**200 OK**. 참여 판단에 필요한 최소 정보. 명단·개인 결제액은 전달하지 않는다.

```json
{
  "gatheringId": 10,
  "timeSlotId": 5,
  "startsAt": "2026-11-28T19:00:00+09:00",
  "visitorCount": 5,
  "canJoin": true,
  "lastRequestAt": "2026-11-28T17:00:00+09:00"
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `INVITE_UNAVAILABLE` | 무효 링크이거나 접근할 수 없음 |

### 비즈니스 규칙

- 단톡방 미리보기와 링크 열람은 참여·알림·좌석 변동 0건이다. canJoin은 조회 당시 안내이며 실제 참여 요청에서 재검사한다.

<a id="api-2-5"></a>

## API · 초대 링크로 참여

`POST /api/invites/{token}/participants`

### 인증

본인인증 완료 회원 · CSRF

### Request

Path token. 참여할 회원은 세션에서 정한다. 본문 없음.

### Response

**201 Created · 신규 / 200 OK · 이미 참여**. 같은 계정의 유효한 재요청은 현재 참여 결과를 반환한다.

```json
{
  "gatheringId": 10,
  "memberId": 43,
  "participantStatus": "JOINED",
  "visitorCount": 6,
  "draftRevision": 7
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `INVITE_UNAVAILABLE` | 무효 링크 |
| 403 | `PARTICIPATION_BLOCKED` | 해당 모임에서 차단됨 |
| 409 | `DUPLICATE_SLOT_PARTICIPATION` | 같은 회차 다른 진행 중 모임에 참여 |
| 409 | `GATHERING_NOT_EDITABLE` | 메뉴 편집 종료 |
| 422 | `PARTY_SIZE_OUT_OF_RANGE` | 참여 시 최대 인원 초과 |
| 422 | `REQUEST_WINDOW_CLOSED` | 참여 마감 경과 |

### 비즈니스 규칙

- 신규 참여를 기록할 때 링크·차단·편집 상태·시간·자리·중복을 함께 검사한다. 마지막 방문 인원 1자리 경쟁 시 한 명만 성공한다.
- 반복 클릭으로 인원·분담안 버전이 또 증가하지 않는다. 참여만으로 매장 좌석을 확보하지 않는다.
- 나간 뒤 다시 참여하면 기존 참여 행을 활성화하고 재확인 기준을 갱신한다. 이전 금액 확인은 재사용하지 않는다.

- 본인의 중복 참여 거부는 `details.conflictingGatheringId`로 안내한다. 유효하지 않은 옛 토큰으로는 재참여할 수 없다.

<a id="api-2-6"></a>

## API · 모임 나가기

`DELETE /api/gatherings/{gatheringId}/participants/me`

### 인증

현재 참여자 본인 · CSRF

### Request

Path gatheringId. 예약자는 종료 안내를 보고 확인한 뒤 호출한다. 본문 없음.

### Response

**200 OK · 처리 완료 / 202 Accepted · 환불 진행 중**. 예시는 결제 대기 중 예약자 이탈. 일반 참여자의 편집 중 이탈은 EDITING 유지.

```json
{
  "gatheringId": 50,
  "gatheringStatus": "CLOSED",
  "refundCount": 4,
  "reservationId": 52
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 409 | `PARTICIPATION_CHANGED` | 화면에서 확인한 참여·단계·대상이 변경됨 |
| 404 | `GATHERING_NOT_FOUND` | 접근할 수 없는 모임 |
| 409 | `LEAVE_NOT_ALLOWED` | 일반 참여자의 편집 종료 후 이탈 또는 확정 예약의 이탈 |

### 비즈니스 규칙

- 일반 참여자는 메뉴 편집 중 자기 동반인과 함께 나간다. 예약자는 편집 중이면 모임 종료, 매장 응답 대기면 요청 철회와 종료, 결제 대기면 좌석 해제·결제별 전액 환불 접수·모임 종료를 함께 처리한다. 종료 결과는 참여자 전원에게 알린다.
- 마지막 결제 완료와 예약자 이탈이 겹치면 최초 유효 기록 시각을 비교하고 동률은 이탈 우선. 예약 확정 이후에는 ‘예약 전체 취소’로 처리한다. 같은 이탈로 좌석·환불을 두 번 처리하지 않는다.
- 예약자가 편집에서 실수로 이탈하는 것을 막도록 화면에서 모임 전체 종료와 전원 알림을 확인받는다.

- Query `expectedJoinedAt`(오프셋 포함 시각)과 `expectedGatheringStatus`(Enum)는 필수다. 예약자의 이탈은 상세 화면에서 확인한 `expectedStoreRequestId`, `expectedReservationId`도 있으면 전송한다. 해당 상태에서 생성 전인 대상은 생략한다. 모임 잠금 뒤 단계와 대상이 같을 때만 실행한다. 다시 참여했거나 새 요청·예약으로 넘어갔다면 `409 PARTICIPATION_CHANGED` 후 다시 조회한다. 이미 떠난 일반 참여자는 404를 받을 수 있고 같은 종료로 새 효과가 생기지 않는다.

<a id="api-2-7"></a>

## API · 참여자 내보내기

`DELETE /api/gatherings/{gatheringId}/participants/{memberId}`

### 인증

예약자 · CSRF

### Request

Path gatheringId, memberId(내보낼 참여자). 본문 없음.

### Response

**200 OK**. 선택한 참여자와 그 동반인을 제외한 뒤 분담안을 갱신한다.

```json
{
  "gatheringId": 10,
  "memberId": 43,
  "blocked": true,
  "draftRevision": 8
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 409 | `PARTICIPATION_CHANGED` | 대상이 다시 참여해 참여 시점이 달라짐 |
| 404 | `GATHERING_NOT_FOUND` | 모임이 없거나 현재 참여자가 아닌 계정. 두 경우 같은 응답 |
| 403 | `NOT_GATHERING_HOST` | 해당 모임의 현재 참여자이나 예약자가 아닌 회원 |
| 409 | `GATHERING_NOT_EDITABLE` | 편집 종료 |
| 409 | `HOST_REMOVAL_FORBIDDEN` | 대상이 예약자 |
| 404 | `PARTICIPANT_NOT_FOUND` | 이 모임의 대상 없음 |

### 비즈니스 규칙

- 모임 잠금 아래 참여 종료와 차단을 함께 저장한다. 같은 차단을 반복해도 인원을 다시 빼지 않는다. 새 링크로도 이 계정의 차단은 유지된다.

- Query `expectedJoinedAt`은 필수다. 예약자의 최종 확인 명단에서 읽은 참여 시작 시각을 보낸다. 서버는 재참여마다 구별되는 값을 기록하고 직렬화할 때 원래 정밀도를 보존한다. 옛 요청은 새 참여를 내보낼 수 없다.

<a id="api-2-8"></a>

## API · 초대 링크 재발급

`POST /api/gatherings/{gatheringId}/invite-link/reissue`

### 인증

예약자 · CSRF

### Request

Path gatheringId. expectedVersion 필수 정수. 편집 화면에서 본 마지막 발급 버전으로 동시 재발급을 구분한다.

```json
{
  "expectedVersion": 1
}
```

### Response

**201 Created · 새 버전 발급**. 상태 변경 전에 화면이 본 링크 버전을 비교한다. 폐기된 뒤에도 모임 상세에서 마지막 버전을 확인할 수 있게 한다.

```json
{
  "gatheringId": 10,
  "version": 2,
  "url": "https://example.com/i/example-token-v2"
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `GATHERING_NOT_FOUND` | 모임이 없거나 현재 참여자가 아닌 계정. 두 경우 같은 응답 |
| 403 | `NOT_GATHERING_HOST` | 해당 모임의 현재 참여자이나 예약자가 아닌 회원 |
| 409 | `INVITE_VERSION_MISMATCH` | 다른 요청이 이미 새 버전을 발급 |
| 409 | `GATHERING_NOT_EDITABLE` | 편집 종료 |
| 422 | `REQUEST_WINDOW_CLOSED` | 마지막 참여 시각 지남 |

### 비즈니스 규칙

- 기존 유효 링크를 닫고 새 링크 하나를 같은 트랜잭션에 저장한다. 네트워크 오류 뒤 버전 충돌이면 모임 상세에서 현재 버전을 확인한다. 기존 참여자는 유지된다.

- `expectedVersion`은 모임 상세의 `lastInviteVersion`에서 읽는다. 폐기 이후에도 값을 얻을 수 있다.

<a id="api-2-9"></a>

## API · 회차 변경

`PATCH /api/gatherings/{gatheringId}/time-slot`

### 인증

예약자 · CSRF

### Request

Path gatheringId. timeSlotId(Long), draftRevision(Integer) 필수.

```json
{
  "timeSlotId": 6,
  "draftRevision": 7
}
```

### Response

**200 OK**. 실제 회차가 바뀐 경우 현재 참여자 전원이 다시 확인한다.

```json
{
  "gatheringId": 10,
  "timeSlotId": 6,
  "draftRevision": 8,
  "reconfirmationRequired": true
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 409 | `DRAFT_REVISION_MISMATCH` | 옛 화면 |
| 409 | `GATHERING_NOT_EDITABLE` | 편집 종료 |
| 409 | `DUPLICATE_SLOT_PARTICIPATION` | 한 명 이상 새 회차의 다른 모임에 이미 참여 |
| 404 | `TIME_SLOT_NOT_FOUND` | 회차 없음 |
| 422 | `REQUEST_WINDOW_CLOSED` | 선택할 수 없는 회차 |
| 404 | `GATHERING_NOT_FOUND` | 모임이 없거나 현재 참여자가 아닌 계정. 두 경우 같은 응답 |
| 403 | `NOT_GATHERING_HOST` | 해당 모임의 현재 참여자이나 예약자가 아닌 회원 |

### 비즈니스 규칙

- 예약자 포함 모든 현재 참여자의 회차와 활성 참여 키를 함께 갱신한다. 한 건이라도 충돌하면 회차·확인·버전 모두 롤백한다.
- 19시 → 20시 → 19시로 돌아와도 옛 확인은 되살리지 않는다. 같은 회차로 실제 변경이 없으면 전원 재확인을 만들지 않는다.

- 충돌 시 `details.conflictingMemberIds`에는 현재 모임에서 예약자가 볼 수 있는 참여자 ID만 반환한다. 다른 모임의 ID는 본인의 모임일 때만 안내한다. 예전 버전 재전송은 409로 처리하고 모임 상세를 다시 읽는다.

<a id="api-2-10"></a>

## API · 초대 링크 폐기

`DELETE /api/gatherings/{gatheringId}/invite-link`

### 인증

예약자 · CSRF

### Request

Path gatheringId. Query version 필수 정수. 예: ?version=2. 본문 없음.

### Response

**200 OK**. 대상 버전의 링크를 폐기한다.

```json
{
  "gatheringId": 10,
  "version": 2,
  "inviteLink": null
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `GATHERING_NOT_FOUND` | 모임이 없거나 현재 참여자가 아닌 계정. 두 경우 같은 응답 |
| 403 | `NOT_GATHERING_HOST` | 해당 모임의 현재 참여자이나 예약자가 아닌 회원 |
| 409 | `GATHERING_NOT_EDITABLE` | 편집 종료 |
| 409 | `INVITE_VERSION_MISMATCH` | 이미 더 새 링크가 발급됨 |

### 비즈니스 규칙

- 같은 버전의 폐기 재요청은 같은 결과. 늦게 도착한 옛 폐기 요청은 새로 발급된 링크를 닫지 않는다. 참여자·좌석·금액은 그대로다.

- 같은 버전이 이미 폐기됐고 이후 발급이 없으면 200이다. 더 새 버전이 있으면 409를 먼저 적용하고 현재 유효 링크는 유지한다.

<a id="api-2-11"></a>

## API · 차단 해제

`DELETE /api/gatherings/{gatheringId}/blocks/{memberId}`

### 인증

예약자 · CSRF

### Request

Path gatheringId, memberId(차단 대상). 본문 없음.

### Response

**200 OK**. 활성 차단만 풀며 참여 결과는 생성하지 않는다.

```json
{
  "gatheringId": 10,
  "memberId": 43,
  "blocked": false,
  "blockId": 71
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `BLOCK_NOT_FOUND` | 지정한 모임·회원의 차단 이력이 아님 |
| 404 | `GATHERING_NOT_FOUND` | 모임이 없거나 현재 참여자가 아닌 계정. 두 경우 같은 응답 |
| 403 | `NOT_GATHERING_HOST` | 해당 모임의 현재 참여자이나 예약자가 아닌 회원 |
| 409 | `GATHERING_NOT_EDITABLE` | 편집 종료 |

### 비즈니스 규칙

- 재호출해도 해제 이력은 한 번만 남긴다. 당사자가 유효한 링크로 다시 참여할 때 정원·회차 중복·마감을 새로 검사한다.

- Query `blockId`(필수 Long)는 예약자의 모임 상세에 표시된 차단 이력 ID다. 모임·대상 회원·차단 이력의 소속을 대조한다. 이미 해제한 이력은 200이며 새로 생성된 차단에는 영향을 주지 않는다.
