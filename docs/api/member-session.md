# 1. 회원과 세션

[API 명세](../api.md)의 공통 계약(응답 형식·인증·공통 오류·값 형식)을 함께 적용한다. 정책 ID는 [비즈니스 정책](../policy.md), 테이블은 [ERD](../erd.md)를 따른다.

<a id="api-1-0"></a>

## API · CSRF 토큰 받기

`GET /api/auth/csrf`

### 인증

비로그인 및 로그인 브라우저

### Request

입력 없음. 같은 사이트의 세션 쿠키를 유지한다.

### Response

**200 OK**. headerName과 token은 문자열. 브라우저가 다음 상태 변경 요청의 헤더에 넣는다.

```json
{
  "headerName": "X-XSRF-TOKEN",
  "token": "example-csrf-token"
}
```

### 예외처리

이 API에는 별도 업무 오류를 추가하지 않는다. 적용되는 인증·입력 실패는 공통 계약을 따른다.

### 비즈니스 규칙

- 첫 POST 전에 호출한다. 서버에서 CSRF 토큰을 발행해도 회원 로그인으로 처리하지 않는다.
- 로그인 성공과 로그아웃 성공 후 재조회한다. 응답은 개인별이며 Cache-Control: no-store를 사용한다.

<a id="api-1-1"></a>

## API · 본인인증 시작

`POST /api/identity-verifications`

### 인증

비로그인 브라우저 · CSRF

### Request

본문 없음. 채널·어댑터는 서버 환경 설정에서 결정한다.

### Response

**201 Created**. 본인인증창용 공개 식별 정보다. MOCK 시연 경로에서는 storeId와 channelKey가 null일 수 있다.

```json
{
  "identityVerificationId": "ivExample01",
  "authRoute": "TEST_CHANNEL",
  "storeId": "store-example",
  "channelKey": "channel-key-example"
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 503 | `IDENTITY_PROVIDER_UNAVAILABLE` | 설정된 인증 경로를 시작할 수 없음 |

### 비즈니스 규칙

- 서버가 추측하기 어려운 식별자를 발급하고 가입 전 세션에 묶는다. 새 시도를 시작하면 이 세션의 이전 미사용 시도는 만료시킨다.
- 클라이언트가 인증 성공·DI·인증 경로를 지정할 수 없다. MOCK은 테스트·시연 설정에서 명시적으로 선택한다.

- KCP 경로의 `identityVerificationId`는 서버에서 영문·숫자 1~40자로 생성한다. `TEST_CHANNEL`에는 `storeId`, `channelKey`가 필수다. `MOCK`에서는 두 필드에 `null`을 반환하고 서버의 시연용 인증 결과를 사용한다.

<a id="api-1-2"></a>

## API · 회원 가입

`POST /api/members`

### 인증

본인인증을 시작한 동일한 비로그인 세션 · CSRF

### Request

email·password·identityVerificationId는 필수 문자열. 실명·생년월일·DI는 인증 결과에서 얻는다.

```json
{
  "email": "member@example.com",
  "password": "example-password-only",
  "identityVerificationId": "ivExample01"
}
```

### Response

**201 Created**. 계정 생성 결과. 로그인은 별도 요청이다.

```json
{
  "memberId": 42,
  "identityVerified": true
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 409 | `MEMBER_ALREADY_EXISTS` | 이메일 또는 동일인 식별값이 이미 등록됨 |
| 409 | `IDENTITY_VERIFICATION_INVALID` | 세션 불일치·이미 사용·만료·미완료·필수 본인 정보 누락 |
| 503 | `IDENTITY_PROVIDER_UNAVAILABLE` | 단건 조회 결과를 확인할 수 없음 |

### 비즈니스 규칙

- 서버가 설정된 경로에서 인증 결과를 확인한다. PortOne은 단건 조회 결과의 status=VERIFIED와 verifiedCustomer.di를 사용한다. 같은 세션에 저장한 시도와 대조한다.
- 계정과 동일인 유일성을 DB에서 보장한 뒤 인증 사용을 확정한다. 동시 제출은 계정 최대 1개. 실패 시 자동 모의 성공 전환은 없다.

- `VERIFIED`여도 DI·이름·생년월일 중 필수 정보가 비어 있으면 계정을 만들 수 없다. 가입 응답 유실 뒤에는 먼저 로그인할 수 있다. 재제출이 이미 소비된 시도로 거부되거나 기존 회원으로 확인돼도 새 회원 행은 생성되지 않는다.

<a id="api-1-3"></a>

## API · 로그인

`POST /api/auth/login`

### 인증

비로그인 브라우저 · CSRF

### Request

email·password 필수 문자열.

```json
{
  "email": "member@example.com",
  "password": "example-password-only"
}
```

### Response

**200 OK**. 세션 쿠키는 Set-Cookie로 전달한다.

```json
{
  "memberId": 42
}
```

### 예외처리

| HTTP Status | Error Code | 발생 조건 |
|---|---|---|
| 401 | `LOGIN_FAILED` | 자격 증명이 맞지 않거나 로그인할 수 없는 계정 |

### 비즈니스 규칙

- 로그인 성공 시 인증 세션을 발행하고 세션 식별자를 갱신한다. 이후 새 CSRF 토큰을 받는다.
- 직원 권한은 세션에 고정하지 않는다. 권한 회수는 다음 직원 요청부터 반영한다.

<a id="api-1-4"></a>

## API · 로그아웃

`POST /api/auth/logout`

### 인증

로그인 회원 · CSRF

### Request

본문 없음.

### Response

**200 OK**. 세션이 종료됐음을 알려 준다.

```json
{
  "loggedOut": true
}
```

### 예외처리

이 API에는 별도 업무 오류를 추가하지 않는다. 적용되는 인증·입력 실패는 공통 계약을 따른다.

### 비즈니스 규칙

- 세션을 무효화하고 이전 로그인 쿠키로 보호 자원을 조회하면 401이다. 다음 가입·로그인 POST 전에 비로그인 상태에서 CSRF 토큰을 다시 받는다.

<a id="api-1-5"></a>

## API · 내 정보 조회

`GET /api/members/me`

### 인증

로그인 회원 본인

### Request

입력 없음. 조회 대상은 세션에서 정한다.

### Response

**200 OK**. 화면에 필요한 본인 정보만 반환한다.

```json
{
  "memberId": 42,
  "email": "member@example.com",
  "name": "예시회원",
  "identityVerified": true,
  "activeGatherings": [
    {
      "gatheringId": 10,
      "timeSlotId": 5
    }
  ],
  "staffStores": []
}
```

### 예외처리

이 API에는 별도 업무 오류를 추가하지 않는다. 적용되는 인증·입력 실패는 공통 계약을 따른다.

### 비즈니스 규칙

- 비밀번호 해시·DI·세션 식별자·PG 자격 증명은 응답에서 제외한다. 조회로 회원이나 권한 상태가 바뀌지 않는다.

- `activeGatherings`는 현재 사용자가 참여 중인 모임, `staffStores`는 현재 유효한 직원 소속(`storeId`는 모이온 숫자 ID)이다. 각각 없으면 빈 배열이다. 재로그인 후에도 화면에서 해당 ID를 얻는다.
