-- 제약 검증용 최소 데이터
-- 모임 2개가 같은 회차 1에 있다
--   모임 1: 예약자 회원 1, 참여자 회원 2. 주문서 OS1(id 1)·OS2(id 2), 요청 1(OS1)·2(OS2), 예약 1(요청 1, OS1)
--   모임 2: 예약자 겸 참여자 회원 4. 메뉴 편집 중
-- 제약 확인에 필요한 행만 넣었다
--   주문서 총액 40,000원 중 결제자 몫은 회원 1의 20,000원만 넣었다
--   회차 1의 확보 14석은 다른 모임의 예약으로 이미 확보된 좌석이라고 가정한 값이다

-- 회원 1(모임 1 예약자), 2(모임 1 참여자), 3(운영자), 4(모임 2 예약자), 5(매장 1 직원)
INSERT INTO member (id, email, password_hash, name, di_hash, birth_date, auth_route, is_operator, status, created_at)
VALUES (1, 'host@example.com', 'hash-1', '예약자', REPEAT('a', 64), '1993-01-01', 'MOCK', FALSE, 'ACTIVE', '2026-11-28 09:00:00'),
       (2, 'guest@example.com', 'hash-2', '참여자', REPEAT('b', 64), '1993-01-02', 'MOCK', FALSE, 'ACTIVE', '2026-11-28 09:00:00'),
       (3, 'operator@example.com', 'hash-3', '운영자', REPEAT('c', 64), '1993-01-03', 'MOCK', TRUE, 'ACTIVE', '2026-11-28 09:00:00'),
       (4, 'host2@example.com', 'hash-4', '두번째예약자', REPEAT('d', 64), '1993-01-04', 'MOCK', FALSE, 'ACTIVE', '2026-11-28 09:00:00'),
       (5, 'staff@example.com', 'hash-5', '매장직원', REPEAT('e', 64), '1993-01-05', 'MOCK', FALSE, 'ACTIVE', '2026-11-28 09:00:00');

INSERT INTO store (id, name, open_time, close_time, min_party, max_party, created_at)
VALUES (1, '모이온 시연 매장', '11:00:00', '23:00:00', 2, 8, '2026-11-28 09:00:00');

-- 직원 51: 회원 5, 매장 1, 운영자 3이 부여
INSERT INTO store_staff (id, member_id, store_id, status, granted_by, granted_at)
VALUES (51, 5, 1, 'ACTIVE', 3, '2026-11-28 09:30:00');

-- 회차 1: 정원 20, 확보 14
INSERT INTO time_slot (id, store_id, starts_at, ends_at, capacity, secured_count)
VALUES (1, 1, '2026-11-28 19:00:00', '2026-11-28 20:30:00', 20, 14);

INSERT INTO menu (id, store_id, name, price, is_preorderable, is_alcohol, status)
VALUES (1, 1, '고기 1인분', 20000, TRUE, FALSE, 'ON_SALE');

INSERT INTO gathering (id, host_member_id, time_slot_id, status, draft_revision, next_version, created_at, closed_at)
VALUES (1, 1, 1, 'EDIT_LOCKED', 7, 3, '2026-11-28 12:00:00', NULL),
       (2, 4, 1, 'EDITING', 1, 1, '2026-11-28 12:30:00', NULL);

INSERT INTO participant (id, gathering_id, member_id, time_slot_id, status, reconfirm_from_revision, joined_at, left_at, active_slot_id)
VALUES (1, 1, 1, 1, 'JOINED', 1, '2026-11-28 12:00:00', NULL, 1),
       (2, 1, 2, 1, 'JOINED', 1, '2026-11-28 12:10:00', NULL, 1),
       (3, 2, 4, 1, 'JOINED', 1, '2026-11-28 12:30:00', NULL, 1);

INSERT INTO amount_confirmation (id, gathering_id, member_id, draft_revision, time_slot_id, amount, share_units,
                                 full_refund_minutes_before, cancel_penalty_rate, noshow_penalty_rate, confirmed_at)
VALUES (1, 1, 1, 7, 1, 20000, 1, 60, 15, 20, '2026-11-28 15:50:00'),
       (2, 1, 2, 7, 1, 20000, 1, 60, 15, 20, '2026-11-28 15:51:00');

-- OS1은 조기 종료로 무효, OS2는 다시 확정한 유효 주문서
INSERT INTO order_sheet (id, gathering_id, version, time_slot_id, visitor_count, share_count, total_amount, status,
                         confirmed_at, voided_at, void_reason)
VALUES (1, 1, 1, 1, 2, 2, 40000, 'VOIDED', '2026-11-28 16:00:00', '2026-11-28 16:30:00', '조기 종료'),
       (2, 1, 2, 1, 2, 2, 40000, 'VALID', '2026-11-28 17:00:00', NULL, NULL);

-- 결제자 몫: 11(OS1, 회원 1), 21(OS2, 회원 1)
INSERT INTO payer_share (id, order_sheet_id, member_id, share_units, amount, is_host, amount_confirmation_id, share_exclusion_consent_id)
VALUES (11, 1, 1, 1, 20000, TRUE, 1, NULL),
       (21, 2, 1, 1, 20000, TRUE, 1, NULL);

-- 요청 1은 직원 51이 수락, 요청 2는 응답 대기
INSERT INTO store_request (id, order_sheet_id, requested_at, response_deadline, result, responded_at, responded_by, reject_reason)
VALUES (1, 1, '2026-11-28 16:00:00', '2026-11-28 17:00:00', 'ACCEPTED', '2026-11-28 16:20:00', 51, NULL),
       (2, 2, '2026-11-28 17:00:00', '2026-11-28 18:00:00', 'PENDING', NULL, NULL, NULL);

-- 예약 1: 요청 1, OS1. 조기 종료로 끝남
INSERT INTO reservation (id, store_request_id, order_sheet_id, secured_visitor_count, payment_start_deadline,
                         payment_deadline, status, confirmed_at, ended_at)
VALUES (1, 1, 1, 2, '2026-11-28 16:45:00', '2026-11-28 16:50:00', 'EARLY_CLOSED', NULL, '2026-11-28 16:30:00');