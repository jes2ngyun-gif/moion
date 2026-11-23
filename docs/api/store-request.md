# 4. 매장 수락 요청과 직원 응답

[API 명세](../api.md)의 공통 계약(응답 형식·인증·공통 오류·값 형식)을 함께 적용한다. 정책 ID는 [비즈니스 정책](../policy.md), 테이블은 [ERD](../erd.md)를 따른다.

<a id="api-4-1"></a>

## API · 매장 수락 요청


**Method**: POST

**Path**: `/api/gatherings/{gatheringId}/store-requests`

예약자가 최종 확인 화면에서 버튼을 한 번 누르면 메뉴 확정(주문서 생성)과 매장 수락 요청이 한 트랜잭션으로 함께 저장된다. 이 단계에서는 좌석을 확보하지 않는다.

### 인증

- 세션 로그인 회원 + 상태 변경 요청용 CSRF 헤더 `X-XSRF-TOKEN`
- 요청자 = 해당 모임의 예약자(\[POL-016\] 역할과 예약별 권한)

| 위치 | 이름 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- | --- |
| Path | gatheringId | Long | O | 모임 ID |
| Header | X-XSRF-TOKEN | String | O | CSRF 토큰 |

### Request

```json
{
  "draftRevision": 7
}
```

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| draftRevision | Integer | O | 예약자가 화면에서 본 분담안 버전. 새 요청일 때 서버의 현재 버전과 다르면 거부 |

### Response 201 Created · 요청 생성

```json
{
  "success": true,
  "code": "STORE_REQUEST_CREATED",
  "message": "매장에 수락을 요청했습니다.",
  "data": {
    "storeRequestId": 31,
    "orderSheetId": 18,
    "orderSheetVersion": 2,
    "requestStatus": "PENDING",
    "requestedAt": "2026-11-28T16:00:00+09:00",
    "responseDeadline": "2026-11-28T17:00:00+09:00",
    "timeSlot": { "timeSlotId": 5, "startsAt": "2026-11-28T19:00:00+09:00", "endsAt": "2026-11-28T20:30:00+09:00" },
    "visitorCount": 6,
    "totalAmount": 100000
  }
}
```

### Response 200 OK · 같은 요청 재시도

- 같은 모임·같은 draftRevision으로 이미 만든 요청이 있으면 새로 만들지 않고 그 요청을 돌려준다. `code`는 `STORE_REQUEST_ALREADY_CREATED`.
- 모임이 이미 매장 응답 대기여도, 그 요청이 이후 거절·철회·만료로 끝났어도 같다. 현재 결과는 `requestStatus`로 보여 준다.

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| storeRequestId | Long | 수락 요청 ID |
| orderSheetId / orderSheetVersion | Long / Integer | 이번에 확정한 주문서 |
| requestStatus | Enum | 수락 요청의 현재 결과. 새로 만들면 PENDING |
| responseDeadline | String | 요청 시각 + 60분. 매장 응답이 이 시각과 같거나 늦으면 만료 |
| visitorCount | Integer | 분담 제외 동반인을 포함한 방문 인원 |
| totalAmount | Long | 주문서 총액(원) |
| requestedAt | String | 최초 접수 시각 |
| timeSlot.timeSlotId | Long | 주문서에 고정된 회차 ID |
| timeSlot.startsAt / endsAt | String | 회차 시작·종료 시각 |

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
| --- | --- | --- |
| 422 | `PAYER_AMOUNT_TOO_LOW` | 최종 청구액이 0원이거나 선택 채널에서 확인한 양수 하한보다 작은 회원이 있음. 새 주문서·요청·업무함 0건, 좌석 변화 0 |
| 422 | `EMPTY_CART` | 주문서에 담을 품목이 없음 |
| 401 | AUTH\_REQUIRED | 세션 없음 |
| 403 | CSRF\_INVALID | CSRF 토큰 없음·불일치 |
| 404 | `GATHERING_NOT_FOUND` | 모임이 없거나 현재 참여자가 아닌 계정. 두 경우 같은 응답 |
| 403 | `NOT_GATHERING_HOST` | 해당 모임의 현재 참여자이나 예약자가 아닌 회원 |
| 409 | GATHERING\_NOT\_EDITABLE | 새 요청인데 모임이 메뉴 편집 상태가 아님(종료 포함) |
| 409 | ACTIVE\_REQUEST\_EXISTS | 같은 모임에 응답 대기 요청 또는 결제 대기·확정 예약이 있음 |
| 409 | DRAFT\_REVISION\_MISMATCH | 새 요청의 draftRevision이 현재 버전과 다름 |
| 409 | CONFIRMATION\_INCOMPLETE | 유효한 금액 확인 또는 필요한 분담 제외 동의가 없는 참여자가 있음. 주문서·요청·업무함 0건, 미확인자에게만 확인 요청 알림 |
| 409 | DUPLICATE\_SLOT\_PARTICIPATION | 계정 참여자 중 같은 회차의 다른 진행 중 모임에 속한 사람이 있음 |
| 422 | REQUEST\_WINDOW\_CLOSED | 마지막 요청 가능 시각이 지남, 요청 시각이 영업시간 밖, 응답 기한이 영업 종료를 넘음, 예약 가능 기간 밖 |
| 422 | PARTY\_SIZE\_OUT\_OF\_RANGE | 방문 인원이 매장의 1건당 최소·최대 방문 인원 밖 |

### 비즈니스 규칙

1. 검사 순서
   - ① 세션·CSRF → 모임 참여 관계(404) → 예약자 역할(403) → ② 모임 한 행 잠금 → ③ 같은 모임·같은 draftRevision의 기존 요청 조회(있으면 200, 모임 상태와 무관) → ④ 새 요청일 때만 모임 상태·진행 중 요청/예약·버전·같은 회차 중복·요청 가능 조건·인원 범위 → ⑤ 빈 장바구니·주문서 합계·회원별 최종 카드 청구액 검사 → ⑥ 전원 금액 확인·분담 제외 동의
   - ③을 ④보다 먼저 둬야, 성공 응답이 끊긴 뒤 다시 보낸 같은 요청이 409가 아니라 200을 받는다.
2. 성공 시 한 트랜잭션에 저장
   - 주문서(새 버전, 품목 사본, 결제자별 몫과 각자의 확인 기록)
   - 수락 요청(PENDING, 응답 기한 = 요청 시각 + 60분)
   - 모임 상태 매장 응답 대기, 초대 링크 닫힘
   - 참여자 전원에게 응답 마감 안내 알림, 매장 업무함 새 요청 1건(\[POL-017\] 필수 알림과 기한)
3. 금액 검사
   - 품목 금액 합 = 주문서 총액 = 결제자 몫 합
   - 각 몫의 확인 기록이 같은 모임·같은 회원·현재 회차·현재 금액의 유효한 확인인지(\[POL-001\] 참여자별 결제 금액 산정 방식, \[POL-006\] 참여 확정의 정의)
4. 좌석
   - 이 API는 좌석을 확보하지 않는다. 좌석은 매장 직원이 수락할 때 확보한다(\[POL-002\] 매장 수락 절차와 결제 제한 시간).
5. 동시 요청·재시도
   - 같은 분담안으로 동시에 두 번 눌러도 모임 잠금으로 줄을 서므로 주문서 1장·수락 요청 1건·매장 업무함 1건이다.
6. 편집 복귀 때 분담안 버전 올림
   - 요청이 거절·철회·응답 만료로 끝나거나, 수락 뒤 예약자가 결제 대기를 조기 종료해 메뉴 편집으로 돌아갈 때 draftRevision을 1 올린다.
   - 예전 화면이 보낸 옛 버전은 옛 요청을 돌려받고, 새 화면의 재요청은 새 주문서·새 수락 요청이 된다.
   - 버전만 올라서는 전원 재확인이 생기지 않는다. 금액과 회차가 같은 사람의 확인은 그대로 쓴다.
7. 미확인자가 있을 때
   - 주문서·수락 요청은 만들지 않고, 현재 분담안을 확인하지 않은 참여자에게만 확인 요청 알림을 저장해 커밋한 뒤 409를 응답한다(\[POL-006\] 참여 확정의 정의, \[POL-017\] 필수 알림과 기한).
   - 알림 중복 방지 키: 업무 사건(모임·분담안 버전) + 알림 종류 + 수신자. 같은 분담안으로 다시 눌러도 한 사람당 1건이다.
   - 예: 6명 중 2명 미확인으로 두 번 요청 → 주문서 0장, 요청 0건, 알림은 그 두 사람에게 총 2건.
   - 구현: 서비스는 예외 대신 결과(미확인자 목록)를 반환하고, 커밋 뒤 컨트롤러가 409로 바꾼다. 예외를 던지면 기본 설정에서 알림까지 롤백된다.
8. 요청 가능 시간
   - 회차 목록 화면의 "마지막 요청 가능 시각"과 이 API의 서버 검사는 같은 계산을 쓴다(\[POL-005\] 서비스 기본 정책).
   - 예: 낮 12시 회차는 요청 마감 10:00이 영업 시작(11:00) 전이므로 전날 22:00:00까지 허용, 전날 22:00:01과 당일 09:30은 거부.

### 상태값

| requestStatus | 의미 |
| --- | --- |
| PENDING | 매장 응답 대기 |
| ACCEPTED | 수락(예약 생성) |
| REJECTED | 매장 거절 |
| CANCELED\_BY\_HOST | 예약자 철회 |
| EXPIRED | 60분 무응답 |

### 재전송과 청구액 검사

- 새 요청 성공 시 `STORE_REQUEST_CREATED:{gatheringId}:{draftRevision}`와 생성한 `storeRequestId`를 같은 트랜잭션에 보존한다. `business_event.dedup_key`와 `store_request_id`로 옛 요청을 찾는다. 확인 알림의 사건 키는 별개다. 주문서 발행 순번은 분담안 버전과 독립적이다.
- `DUPLICATE_SLOT_PARTICIPATION`이면 현재 모임의 충돌 참여자 ID만 안내한다. 새 요청의 금액 검사에서는 서버 단가로 재계산하고, 이미 확정된 주문서는 당시 단가를 유지한다. 금액·회차·부담 증가 사유가 바뀌면 해당 확인과 동의의 유효성을 다시 검사한다.
- 하한을 확인하지 못한 채널은 `minimumChargeAmount:null`이다. 숫자를 임의로 채우지 않는다. 거부 응답은 예약자에게 조정할 참여자를 안내한다.

```json
{"success":false,"code":"PAYER_AMOUNT_TOO_LOW","message":"메뉴나 인원을 조정한 뒤 다시 요청해 주세요.","errors":[],"details":{"ineligibleMemberIds":[43],"minimumChargeAmount":null},"timestamp":"2026-11-28T16:00:00+09:00"}
```

<a id="api-4-2"></a>

## API · 수락 요청 철회

`POST /api/gatherings/{gatheringId}/store-requests/{storeRequestId}/cancel`

### 인증

요청이 속한 모임의 예약자 · CSRF

### Request

Path gatheringId와 storeRequestId. 먼저 모임의 참여 관계와 예약자 역할을 확인한 뒤 요청을 해당 모임 안에서 조회한다. 접근이 허용된 모임에서도 요청이 없거나 다른 모임의 요청이면 같은 404 STORE_REQUEST_NOT_FOUND를 반환한다. 본문 없음.

### Response

**200 OK**. 성공한 철회 재요청은 기존 시도의 결과를 반환한다.

```json
{
  "storeRequestId": 41,
  "requestStatus": "CANCELED_BY_HOST",
  "gatheringStatus": "EDITING",
  "draftRevision": 8
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 404 | `GATHERING_NOT_FOUND` | 모임이 없거나 현재 참여자가 아닌 계정. 두 경우 같은 응답 |
| 403 | `NOT_GATHERING_HOST` | 해당 모임의 현재 참여자이나 예약자가 아닌 회원 |
| 404 | `STORE_REQUEST_NOT_FOUND` | 요청이 없거나 모임과 불일치 |
| 409 | `STORE_REQUEST_NOT_PENDING` | 먼저 수락·거절됨 |
| 409 | `STORE_REQUEST_EXPIRED` | 응답 기한이 먼저 도래 |

### 비즈니스 규칙

- 모임 잠금 뒤 같은 요청의 철회 여부와 상태·기한을 비교한다. 대기 중 철회하면 옛 주문서를 보존하고 편집으로 복귀하며 버전을 한 번 올린다. 좌석과 환불은 0건이다.
- 요청과 기존 업무함을 닫고 종료 안내를 당시 참여자에게 한 번 기록한다. 수락과 철회가 경합해도 같은 요청에 둘 다 성립하지 않는다.

- 동일 철회의 응답에서 `gatheringStatus`, `draftRevision`은 그 철회로 저장한 편집 복귀 결과다. 현재 상태는 모임 상세에서 조회한다. 기다리던 매장의 기존 업무 항목을 닫고 철회 결과가 보이게 한다.

<a id="api-4-3"></a>

## API · 매장 업무함 조회

`GET /api/store/inbox`

### 인증

유효한 매장 직원. 요청마다 현재 소속을 조회한다.

### Request

Query storeId 필수 Long, status 선택(OPEN/DONE/EXPIRED), page·size 선택. 최신 생성 시각·ID 내림차순.

### Response

**200 OK**. 수락 여부를 판단할 회차·인원·마감과 기존 업무 항목의 현재 상태. canRespond는 화면 안내다. 업무 판단에 필요한 품목·당시 단가는 해당 요청의 주문서에서 가져온다.

```json
{
  "items": [
    {
      "inboxId": 91,
      "storeRequestId": 31,
      "itemType": "STORE_REQUEST_CREATED",
      "status": "OPEN",
      "visitorCount": 6,
      "startsAt": "2026-11-28T19:00:00+09:00",
      "responseDeadline": "2026-11-28T17:00:00+09:00",
      "canRespond": true,
      "orderSheet": {
        "orderSheetId": 18,
        "items": [
          {
            "name": "고기 모둠",
            "quantity": 2,
            "unitPrice": 50000
          }
        ],
        "totalAmount": 100000
      },
      "reservationId": null
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
| 403 | `STAFF_PERMISSION_DENIED` | 다른 매장·미부여·회수 |
| 400 | `INVALID_INPUT` | 상태·페이지 값 오류 |

### 비즈니스 규칙

- 본인 모임은 직원 자격의 처리 대상에서 제외한다. 시간 경과·권한 변경은 수락·거절 시 다시 검사한다.
- 무응답 요청은 기존 항목을 EXPIRED로 표시한다. 이미 좌석을 잡은 예약의 결제 만료는 별도 업무 사건으로 1건이 생긴다.

- `storeId`는 내 정보의 `staffStores`에서 선택한다. 항목의 `reservationId`는 예약 생성 전 `null`이다. 요청형은 `storeRequestId`가 필수다. 응답할 대상이 없는 예약 결과형은 `canRespond:false`, `responseDeadline:null`이며 좌석을 확보한 예약의 `reservationId`를 제공한다.

<a id="api-4-4"></a>

## API · 직원 수락


**Method**: POST

**Path**: `/api/store/requests/{storeRequestId}/accept`

매장 직원이 응답 대기 중인 수락 요청을 수락하면 예약 1건이 생기고 방문 인원만큼 좌석을 확보하며, 결제 대기(30분)가 시작된다.

### 인증

- 세션 로그인 회원 중 현재 유효한 매장 직원 + CSRF 헤더 `X-XSRF-TOKEN`
- 직원의 소속 매장 = 요청 회차의 매장
- 직원 본인이 그 모임의 참여자가 아님(\[POL-016\] 역할과 예약별 권한)

| 위치 | 이름 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- | --- |
| Path | storeRequestId | Long | O | 수락 요청 ID |
| Header | X-XSRF-TOKEN | String | O | CSRF 토큰 |

### Request

- 본문 없음

### Response 201 Created · 수락·예약 생성

```json
{
  "success": true,
  "code": "STORE_REQUEST_ACCEPTED",
  "message": "수락했습니다. 결제가 시작됩니다.",
  "data": {
    "storeRequestId": 31,
    "reservationId": 12,
    "reservationStatus": "PAYMENT_PENDING",
    "acceptedAt": "2026-11-28T16:20:00+09:00",
    "paymentStartDeadline": "2026-11-28T16:45:00+09:00",
    "paymentDeadline": "2026-11-28T16:50:00+09:00",
    "securedVisitorCount": 6,
    "timeSlot": { "timeSlotId": 5, "capacity": 20, "securedCount": 20 }
  }
}
```

### Response 200 OK · 이미 수락된 요청 재시도

- 요청이 이미 수락됐으면 새 예약을 만들지 않고 처음 만든 예약을 그대로 돌려준다. `code`는 `STORE_REQUEST_ALREADY_ACCEPTED`.
- 다른 직원이 먼저 수락했어도, 응답 기한이 이미 지났어도 같다.
- 마감 시각은 처음 수락 시각 기준 그대로다. 재시도 시각으로 다시 계산하지 않는다.

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| reservationId | Long | 생성된 예약 ID(요청당 최대 1건) |
| reservationStatus | Enum | 예약의 현재 상태 |
| paymentStartDeadline | String | 결제 마감 − 5분. 이 시각과 같거나 늦은 결제 시작은 거부 |
| paymentDeadline | String | 수락 시각 + 30분 |
| securedVisitorCount | Integer | 이 예약이 확보한 좌석 수(분담 제외 동반인 포함) |
| timeSlot.securedCount | Integer | 조회 시점의 회차 확보 인원 |
| storeRequestId | Long | 수락된 요청 ID |
| acceptedAt | String | 최초 수락 시각 |
| timeSlot.timeSlotId / capacity | Long / Integer | 회차 ID 및 현재 정원 |

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
| --- | --- | --- |
| 401 | AUTH\_REQUIRED | 세션 없음 |
| 403 | CSRF\_INVALID | CSRF 토큰 없음·불일치 |
| 403 | STAFF\_PERMISSION\_DENIED | 직원 아님, 다른 매장, 권한 회수됨. 요청·예약·좌석·업무함·알림 변화 0건 |
| 403 | OWN\_GATHERING\_FORBIDDEN | 직원 본인이 그 모임의 참여자 |
| 404 | STORE\_REQUEST\_NOT\_FOUND | 요청 없음 |
| 409 | STORE\_REQUEST\_NOT\_PENDING | 이미 거절되었거나 예약자가 철회한 요청 |
| 409 | STORE\_REQUEST\_EXPIRED | 이미 만료된 요청, 또는 응답 대기인데 서버 기록 시각 ≥ 응답 기한 |
| 409 | SLOT\_CAPACITY\_EXCEEDED | 회차 확보 인원 + 방문 인원 > 회차 정원. 요청은 응답 대기 유지 |
| 422 | PARTY\_SIZE\_OUT\_OF\_RANGE | 요청 뒤 매장이 1건당 인원 범위를 바꿔 현재 범위 밖. 요청은 응답 대기 유지 |

### 비즈니스 규칙

1. 검사 순서
   - ① 세션 → ② 현재 직원 권한·소속 매장·본인 모임 여부 → ③ 모임 → 회차 순서로 잠금 → ④ 요청 결과별 분기 → ⑤ 응답 대기·기한 전일 때만 현재 매장의 1건당 최소·최대 인원과 회차 남은 좌석 검사 → ⑥ 수락
   - 권한을 먼저 보므로, 권한이 회수된 직원은 이미 수락된 요청이라도 결과를 받지 못한다.
2. 요청 결과별 분기
   - 수락됨: 기한과 관계없이 처음 만든 예약으로 200
   - 만료됨: 409 STORE\_REQUEST\_EXPIRED
   - 거절·철회됨: 409 STORE\_REQUEST\_NOT\_PENDING
   - 응답 대기인데 기한 지남: 만료 처리(요청 만료, 업무함 만료 표시, 참여자 만료 알림, 모임 메뉴 편집 복귀)를 한 번 커밋한 뒤 409 STORE\_REQUEST\_EXPIRED
   - 만료 작업이 먼저 처리했든 직원 요청에서 처리했든 만료 알림과 업무함 상태는 같다.
   - 구현: 서비스는 예외 대신 만료 처리 결과를 반환하고, 커밋 뒤 컨트롤러가 409로 바꾼다. 예외를 던지면 기본 설정에서 만료 기록과 알림까지 롤백된다.
3. 성공 시 한 트랜잭션에 저장
   - 요청 수락(처리 직원, 처리 시각)
   - 예약 생성(결제 대기, 결제 마감 = 수락 시각 + 30분)
   - 회차 확보 인원 += 방문 인원
   - 업무함 항목 처리 완료
   - 결제 예정자 한 명당 알림 1건. 본문에 결제 시작 마감과 결제 완료 마감 두 시각을 함께 표시(\[POL-017\] 필수 알림과 기한)
4. 재시도와 동시 수락
   - 같은 요청을 두 번 수락해도 예약 1건, 좌석 확보 1회. 요청당 예약 1건 유일 제약과 잠금 뒤 상태 재확인으로 보장한다.
   - 서로 다른 두 모임의 동시 수락: 회차 잠금으로 줄을 세운다. 정원 20석 중 14석 확보 상태에서 6명 모임 둘이 경합하면 정확히 하나만 수락, 최종 20석.
5. 시각 예시(\[POL-002\] 매장 수락 절차와 결제 제한 시간)
   - 재시도: 16:20에 수락이 저장되고 응답만 끊겼다면, 17:00 이후 다시 눌러도 200, 처음 만든 예약 ID, 결제 시작 마감 16:45·완료 마감 16:50 그대로.
   - 대기 중 만료: 16:00 요청이 17:00:00까지 응답 대기였다면 409 STORE\_REQUEST\_EXPIRED. 16:59:59 수락은 허용.
6. 인원 범위 재검사
   - 6명 요청 뒤 매장이 최대 인원을 5명으로 바꾸면 수락 거부, 예약 0건, 좌석 증가 0명. 직원은 거절할 수 있다(\[POL-005\] 서비스 기본 정책).

### 매장 수락 요청·직원 수락 공동 합격 조건

- 예약자가 요청 버튼을 눌렀는데 응답이 끊긴다 → 다시 누르면 같은 수락 요청 1건이 보인다 → 직원 두 명이 동시에 수락한다 → 예약 1건, 좌석 6석 확보, 결제 시작 알림 6건(결제자 6명 × 1건)만 남는다.

### 상태값

| reservationStatus | 의미 |
| --- | --- |
| PAYMENT\_PENDING | 결제 대기 |
| CONFIRMED | 전원 결제로 확정 |
| EXPIRED | 결제 기한 만료(모임 종료) |
| EARLY\_CLOSED | 예약자 조기 종료(모임 메뉴 편집 복귀) |

- 재시도는 최초 예약 ID·수락 시각·두 결제 마감·당시 확보 방문 인원을 보존한다. `reservationStatus`, `timeSlot.securedCount`는 현재값이다. 예를 들어 수락 뒤 결제 만료가 끝났으면 200 응답의 예약 상태는 `EXPIRED`다.

<a id="api-4-5"></a>

## API · 직원 거절

`POST /api/store/requests/{storeRequestId}/reject`

### 인증

현재 소속 매장 직원, 본인의 모임 제외 · CSRF

### Request

Path storeRequestId. reason 선택 문자열(최대 200자). 빈 본문 또는 {} 허용.

```json
{
  "reason": "해당 회차에 단체 식사를 준비하기 어렵습니다."
}
```

### Response

**200 OK**. 거절 사유 생략 시 reason은 null.

```json
{
  "storeRequestId": 51,
  "requestStatus": "REJECTED",
  "reason": "해당 회차에 단체 식사를 준비하기 어렵습니다."
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 403 | `STAFF_PERMISSION_DENIED` | 현재 소속·권한 없음 |
| 403 | `OWN_GATHERING_FORBIDDEN` | 자기 모임 |
| 404 | `STORE_REQUEST_NOT_FOUND` | 요청 없음 |
| 409 | `STORE_REQUEST_NOT_PENDING` | 이미 수락·철회 |
| 409 | `STORE_REQUEST_EXPIRED` | 응답 마감 도달 |

### 비즈니스 규칙

- 처음 거절할 때만 직원·시각·선택 사유를 기록한다. 같은 결과의 재전송은 첫 사유를 보존한다. 마감 이후 대기 건은 만료로 한 번 처리한다.
- 거절·편집 복귀·버전 증가·업무함 처리·요청 당시 전원 알림을 함께 저장한다. 예약과 좌석 확보는 0건이다.

- 동일한 옛 거절이면 기한 검사보다 먼저 처음 기록한 사유를 반환한다. 대기 건이 기한에 도달하면 요청 만료·기존 업무함 종료·전원 안내를 커밋한 후 409를 반환한다. 거절 결과에는 회차를 표시하고 입력한 사유만 손님에게 보여 준다.
