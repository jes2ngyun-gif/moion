-- 모이온 1단계 스키마: 업무 테이블 25개 (docs/erd.md v0.4, docs/erd.dbml)
-- 부모 테이블을 먼저 만들고 자식 테이블을 뒤에 만든다.
-- 시각은 DATETIME(6), 금액은 BIGINT(원). FK에는 삭제·변경 전파를 두지 않는다.

-- 1. 회원
CREATE TABLE member (
                        id            BIGINT       NOT NULL AUTO_INCREMENT,
                        email         VARCHAR(254) NOT NULL,
                        password_hash VARCHAR(255) NOT NULL,
                        name          VARCHAR(50)  NOT NULL,
                        di_hash       CHAR(64)     NOT NULL,
                        birth_date    DATE         NOT NULL,
                        auth_route    VARCHAR(30)  NOT NULL,
                        is_operator   BOOLEAN      NOT NULL,
                        status        VARCHAR(30)  NOT NULL,
                        created_at    DATETIME(6)  NOT NULL,
                        PRIMARY KEY (id),
                        UNIQUE KEY member_u1 (email),
                        UNIQUE KEY member_u2 (di_hash)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 2. 매장
CREATE TABLE store (
                       id         BIGINT       NOT NULL AUTO_INCREMENT,
                       name       VARCHAR(100) NOT NULL,
                       open_time  TIME         NOT NULL,
                       close_time TIME         NOT NULL,
                       min_party  INT          NOT NULL,
                       max_party  INT          NOT NULL,
                       created_at DATETIME(6)  NOT NULL,
                       PRIMARY KEY (id),
                       CONSTRAINT ck_store_party_range CHECK (min_party >= 1 AND max_party >= min_party)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 3. 직원 소속·부여 이력 (활성 권한은 회원·매장당 1건)
CREATE TABLE store_staff (
                             id         BIGINT      NOT NULL AUTO_INCREMENT,
                             member_id  BIGINT      NOT NULL,
                             store_id   BIGINT      NOT NULL,
                             status     VARCHAR(30) NOT NULL,
                             granted_by BIGINT      NOT NULL,
                             granted_at DATETIME(6) NOT NULL,
                             revoked_by BIGINT      NULL,
                             revoked_at DATETIME(6) NULL,
                             active_key VARCHAR(41) GENERATED ALWAYS AS (
                                 CASE WHEN status = 'ACTIVE' THEN CONCAT(member_id, ':', store_id) ELSE NULL END
                                 ) STORED,
                             PRIMARY KEY (id),
                             UNIQUE KEY store_staff_u1 (active_key),
                             CONSTRAINT fk_store_staff_member FOREIGN KEY (member_id) REFERENCES member (id),
                             CONSTRAINT fk_store_staff_store FOREIGN KEY (store_id) REFERENCES store (id),
                             CONSTRAINT fk_store_staff_granted_by FOREIGN KEY (granted_by) REFERENCES member (id),
                             CONSTRAINT fk_store_staff_revoked_by FOREIGN KEY (revoked_by) REFERENCES member (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 4. 직원 권한 부여 요청 (한 부여 이력에 요청 ID 여러 개가 연결될 수 있어 store_staff_id는 유일하지 않다)
CREATE TABLE store_staff_grant_request (
                                           grant_request_id CHAR(36) NOT NULL,
                                           store_staff_id   BIGINT   NOT NULL,
                                           PRIMARY KEY (grant_request_id),
                                           CONSTRAINT fk_store_staff_grant_request_store_staff FOREIGN KEY (store_staff_id) REFERENCES store_staff (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 5. 예약 회차와 좌석
CREATE TABLE time_slot (
                           id            BIGINT      NOT NULL AUTO_INCREMENT,
                           store_id      BIGINT      NOT NULL,
                           starts_at     DATETIME(6) NOT NULL,
                           ends_at       DATETIME(6) NOT NULL,
                           capacity      INT         NOT NULL,
                           secured_count INT         NOT NULL DEFAULT 0,
                           PRIMARY KEY (id),
                           CONSTRAINT fk_time_slot_store FOREIGN KEY (store_id) REFERENCES store (id),
                           CONSTRAINT ck_time_slot_secured_count CHECK (secured_count >= 0 AND secured_count <= capacity)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 6. 매장 메뉴 (주류는 선주문 불가)
CREATE TABLE menu (
                      id              BIGINT       NOT NULL AUTO_INCREMENT,
                      store_id        BIGINT       NOT NULL,
                      name            VARCHAR(100) NOT NULL,
                      price           BIGINT       NOT NULL,
                      is_preorderable BOOLEAN      NOT NULL,
                      is_alcohol      BOOLEAN      NOT NULL,
                      status          VARCHAR(30)  NOT NULL,
                      PRIMARY KEY (id),
                      CONSTRAINT fk_menu_store FOREIGN KEY (store_id) REFERENCES store (id),
                      CONSTRAINT ck_menu_alcohol_not_preorderable CHECK (NOT (is_preorderable AND is_alcohol))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 7. 모임
CREATE TABLE gathering (
                           id             BIGINT      NOT NULL AUTO_INCREMENT,
                           host_member_id BIGINT      NOT NULL,
                           time_slot_id   BIGINT      NOT NULL,
                           status         VARCHAR(30) NOT NULL,
                           draft_revision INT         NOT NULL,
                           next_version   INT         NOT NULL,
                           created_at     DATETIME(6) NOT NULL,
                           closed_at      DATETIME(6) NULL,
                           PRIMARY KEY (id),
                           CONSTRAINT fk_gathering_host_member FOREIGN KEY (host_member_id) REFERENCES member (id),
                           CONSTRAINT fk_gathering_time_slot FOREIGN KEY (time_slot_id) REFERENCES time_slot (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 8. 초대 링크 (모임별 유효 링크는 최대 1개)
CREATE TABLE invite_link (
                             id                  BIGINT       NOT NULL AUTO_INCREMENT,
                             gathering_id        BIGINT       NOT NULL,
                             version             INT          NOT NULL,
                             token               VARCHAR(100) COLLATE utf8mb4_0900_bin NOT NULL,
                             status              VARCHAR(30)  NOT NULL,
                             issued_at           DATETIME(6)  NOT NULL,
                             ended_at            DATETIME(6)  NULL,
                             active_gathering_id BIGINT GENERATED ALWAYS AS (
                                 CASE WHEN status = 'VALID' THEN gathering_id ELSE NULL END
                                 ) STORED,
                             PRIMARY KEY (id),
                             UNIQUE KEY invite_link_u1 (token),
                             UNIQUE KEY invite_link_u2 (gathering_id, version),
                             UNIQUE KEY invite_link_u3 (active_gathering_id),
                             CONSTRAINT fk_invite_link_gathering FOREIGN KEY (gathering_id) REFERENCES gathering (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 9. 참여자 (같은 회차의 진행 중 모임은 한 사람당 하나: active_slot_id)
CREATE TABLE participant (
                             id                      BIGINT      NOT NULL AUTO_INCREMENT,
                             gathering_id            BIGINT      NOT NULL,
                             member_id               BIGINT      NOT NULL,
                             time_slot_id            BIGINT      NOT NULL,
                             status                  VARCHAR(30) NOT NULL,
                             reconfirm_from_revision INT         NOT NULL,
                             joined_at               DATETIME(6) NOT NULL,
                             left_at                 DATETIME(6) NULL,
                             active_slot_id          BIGINT      NULL,
                             PRIMARY KEY (id),
                             UNIQUE KEY participant_u1 (gathering_id, member_id),
                             UNIQUE KEY participant_u2 (member_id, active_slot_id),
                             CONSTRAINT fk_participant_gathering FOREIGN KEY (gathering_id) REFERENCES gathering (id),
                             CONSTRAINT fk_participant_member FOREIGN KEY (member_id) REFERENCES member (id),
                             CONSTRAINT fk_participant_time_slot FOREIGN KEY (time_slot_id) REFERENCES time_slot (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 10. 모임별 차단 (해제 시각이 없는 차단만 유효, 모임·회원당 1건)
CREATE TABLE gathering_block (
                                 id           BIGINT      NOT NULL AUTO_INCREMENT,
                                 gathering_id BIGINT      NOT NULL,
                                 member_id    BIGINT      NOT NULL,
                                 blocked_by   BIGINT      NOT NULL,
                                 blocked_at   DATETIME(6) NOT NULL,
                                 unblocked_at DATETIME(6) NULL,
                                 active_key   VARCHAR(41) GENERATED ALWAYS AS (
                                     CASE WHEN unblocked_at IS NULL THEN CONCAT(gathering_id, ':', member_id) ELSE NULL END
                                     ) STORED,
                                 PRIMARY KEY (id),
                                 UNIQUE KEY gathering_block_u1 (active_key),
                                 CONSTRAINT fk_gathering_block_gathering FOREIGN KEY (gathering_id) REFERENCES gathering (id),
                                 CONSTRAINT fk_gathering_block_member FOREIGN KEY (member_id) REFERENCES member (id),
                                 CONSTRAINT fk_gathering_block_blocked_by FOREIGN KEY (blocked_by) REFERENCES member (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 11. 동반인 (개인정보 없이 분담 몫만)
CREATE TABLE companion (
                           id             BIGINT NOT NULL AUTO_INCREMENT,
                           participant_id BIGINT NOT NULL,
                           share_units    INT    NOT NULL,
                           PRIMARY KEY (id),
                           CONSTRAINT fk_companion_participant FOREIGN KEY (participant_id) REFERENCES participant (id),
                           CONSTRAINT ck_companion_share_units CHECK (share_units IN (0, 1))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 12. 공동 장바구니
CREATE TABLE cart_item (
                           id           BIGINT      NOT NULL AUTO_INCREMENT,
                           gathering_id BIGINT      NOT NULL,
                           menu_id      BIGINT      NOT NULL,
                           quantity     INT         NOT NULL,
                           updated_by   BIGINT      NOT NULL,
                           updated_at   DATETIME(6) NOT NULL,
                           PRIMARY KEY (id),
                           UNIQUE KEY cart_item_u1 (gathering_id, menu_id),
                           CONSTRAINT fk_cart_item_gathering FOREIGN KEY (gathering_id) REFERENCES gathering (id),
                           CONSTRAINT fk_cart_item_menu FOREIGN KEY (menu_id) REFERENCES menu (id),
                           CONSTRAINT fk_cart_item_updated_by FOREIGN KEY (updated_by) REFERENCES member (id),
                           CONSTRAINT ck_cart_item_quantity CHECK (quantity > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 13. 금액·환불 기준 확인 (모임의 참여자만: participant 복합 FK)
CREATE TABLE amount_confirmation (
                                     id                         BIGINT      NOT NULL AUTO_INCREMENT,
                                     gathering_id               BIGINT      NOT NULL,
                                     member_id                  BIGINT      NOT NULL,
                                     draft_revision             INT         NOT NULL,
                                     time_slot_id               BIGINT      NOT NULL,
                                     amount                     BIGINT      NOT NULL,
                                     share_units                INT         NOT NULL,
                                     full_refund_minutes_before INT         NOT NULL,
                                     cancel_penalty_rate        INT         NOT NULL,
                                     noshow_penalty_rate        INT         NOT NULL,
                                     confirmed_at               DATETIME(6) NOT NULL,
                                     PRIMARY KEY (id),
                                     UNIQUE KEY amount_confirmation_u1 (gathering_id, member_id, draft_revision),
                                     CONSTRAINT fk_amount_confirmation_participant FOREIGN KEY (gathering_id, member_id)
                                         REFERENCES participant (gathering_id, member_id),
                                     CONSTRAINT fk_amount_confirmation_time_slot FOREIGN KEY (time_slot_id) REFERENCES time_slot (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 14. 분담 제외 동의 (모임의 참여자만: participant 복합 FK)
CREATE TABLE share_exclusion_consent (
                                         id             BIGINT       NOT NULL AUTO_INCREMENT,
                                         gathering_id   BIGINT       NOT NULL,
                                         member_id      BIGINT       NOT NULL,
                                         draft_revision INT          NOT NULL,
                                         before_amount  BIGINT       NOT NULL,
                                         after_amount   BIGINT       NOT NULL,
                                         reason         VARCHAR(255) NOT NULL,
                                         consented_at   DATETIME(6)  NOT NULL,
                                         PRIMARY KEY (id),
                                         UNIQUE KEY share_exclusion_consent_u1 (gathering_id, member_id, draft_revision),
                                         CONSTRAINT fk_share_exclusion_consent_participant FOREIGN KEY (gathering_id, member_id)
                                             REFERENCES participant (gathering_id, member_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 15. 확정 주문서 (모임별 버전)
CREATE TABLE order_sheet (
                             id            BIGINT       NOT NULL AUTO_INCREMENT,
                             gathering_id  BIGINT       NOT NULL,
                             version       INT          NOT NULL,
                             time_slot_id  BIGINT       NOT NULL,
                             visitor_count INT          NOT NULL,
                             share_count   INT          NOT NULL,
                             total_amount  BIGINT       NOT NULL,
                             status        VARCHAR(30)  NOT NULL,
                             confirmed_at  DATETIME(6)  NOT NULL,
                             voided_at     DATETIME(6)  NULL,
                             void_reason   VARCHAR(255) NULL,
                             PRIMARY KEY (id),
                             UNIQUE KEY order_sheet_u1 (gathering_id, version),
                             CONSTRAINT fk_order_sheet_gathering FOREIGN KEY (gathering_id) REFERENCES gathering (id),
                             CONSTRAINT fk_order_sheet_time_slot FOREIGN KEY (time_slot_id) REFERENCES time_slot (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 16. 주문 품목 사본 (확정 당시 이름·단가·수량)
CREATE TABLE order_sheet_item (
                                  id             BIGINT       NOT NULL AUTO_INCREMENT,
                                  order_sheet_id BIGINT       NOT NULL,
                                  menu_id        BIGINT       NOT NULL,
                                  menu_name      VARCHAR(100) NOT NULL,
                                  unit_price     BIGINT       NOT NULL,
                                  quantity       INT          NOT NULL,
                                  line_amount    BIGINT       NOT NULL,
                                  PRIMARY KEY (id),
                                  UNIQUE KEY order_sheet_item_u1 (order_sheet_id, menu_id),
                                  CONSTRAINT fk_order_sheet_item_order_sheet FOREIGN KEY (order_sheet_id) REFERENCES order_sheet (id),
                                  CONSTRAINT fk_order_sheet_item_menu FOREIGN KEY (menu_id) REFERENCES menu (id),
                                  CONSTRAINT ck_order_sheet_item_line_amount CHECK (line_amount = unit_price * quantity)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 17. 결제자별 확정 몫 (payer_share_u2는 결제의 복합 FK 대상)
CREATE TABLE payer_share (
                             id                         BIGINT  NOT NULL AUTO_INCREMENT,
                             order_sheet_id             BIGINT  NOT NULL,
                             member_id                  BIGINT  NOT NULL,
                             share_units                INT     NOT NULL,
                             amount                     BIGINT  NOT NULL,
                             is_host                    BOOLEAN NOT NULL,
                             amount_confirmation_id     BIGINT  NOT NULL,
                             share_exclusion_consent_id BIGINT  NULL,
                             PRIMARY KEY (id),
                             UNIQUE KEY payer_share_u1 (order_sheet_id, member_id),
                             UNIQUE KEY payer_share_u2 (id, order_sheet_id),
                             CONSTRAINT fk_payer_share_order_sheet FOREIGN KEY (order_sheet_id) REFERENCES order_sheet (id),
                             CONSTRAINT fk_payer_share_member FOREIGN KEY (member_id) REFERENCES member (id),
                             CONSTRAINT fk_payer_share_amount_confirmation FOREIGN KEY (amount_confirmation_id)
                                 REFERENCES amount_confirmation (id),
                             CONSTRAINT fk_payer_share_share_exclusion_consent FOREIGN KEY (share_exclusion_consent_id)
                                 REFERENCES share_exclusion_consent (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 18. 매장 수락 요청 (주문서 1장에 요청 1건, store_request_u2는 예약의 복합 FK 대상)
CREATE TABLE store_request (
                               id                BIGINT       NOT NULL AUTO_INCREMENT,
                               order_sheet_id    BIGINT       NOT NULL,
                               requested_at      DATETIME(6)  NOT NULL,
                               response_deadline DATETIME(6)  NOT NULL,
                               result            VARCHAR(30)  NOT NULL,
                               responded_at      DATETIME(6)  NULL,
                               responded_by      BIGINT       NULL,
                               reject_reason     VARCHAR(200) NULL,
                               PRIMARY KEY (id),
                               UNIQUE KEY store_request_u1 (order_sheet_id),
                               UNIQUE KEY store_request_u2 (id, order_sheet_id),
                               CONSTRAINT fk_store_request_order_sheet FOREIGN KEY (order_sheet_id) REFERENCES order_sheet (id),
                               CONSTRAINT fk_store_request_responded_by FOREIGN KEY (responded_by) REFERENCES store_staff (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 19. 예약 (요청 1건에 예약 1건, 같은 주문서의 요청만: store_request 복합 FK)
CREATE TABLE reservation (
                             id                     BIGINT      NOT NULL AUTO_INCREMENT,
                             store_request_id       BIGINT      NOT NULL,
                             order_sheet_id         BIGINT      NOT NULL,
                             secured_visitor_count  INT         NOT NULL,
                             payment_start_deadline DATETIME(6) NOT NULL,
                             payment_deadline       DATETIME(6) NOT NULL,
                             status                 VARCHAR(30) NOT NULL,
                             confirmed_at           DATETIME(6) NULL,
                             ended_at               DATETIME(6) NULL,
                             PRIMARY KEY (id),
                             UNIQUE KEY reservation_u1 (store_request_id),
                             UNIQUE KEY reservation_u2 (id, order_sheet_id),
                             CONSTRAINT fk_reservation_store_request FOREIGN KEY (store_request_id, order_sheet_id)
                                 REFERENCES store_request (id, order_sheet_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 20. 원결제 (같은 주문서의 예약·결제자 몫만: 복합 FK 2개, 몫 하나에 반영 인정 결제 1건)
CREATE TABLE payment (
                         id                 BIGINT       NOT NULL AUTO_INCREMENT,
                         portone_payment_id VARCHAR(100) COLLATE utf8mb4_0900_bin NOT NULL,
                         reservation_id     BIGINT       NOT NULL,
                         payer_share_id     BIGINT       NOT NULL,
                         order_sheet_id     BIGINT       NOT NULL,
                         amount             BIGINT       NOT NULL,
                         status             VARCHAR(30)  NOT NULL,
                         started_at         DATETIME(6)  NOT NULL,
                         pg_approved_at     DATETIME(6)  NULL,
                         recorded_paid_at   DATETIME(6)  NULL,
                         counted_share_id   BIGINT       NULL,
                         PRIMARY KEY (id),
                         UNIQUE KEY payment_u1 (portone_payment_id),
                         UNIQUE KEY payment_u2 (counted_share_id),
                         CONSTRAINT fk_payment_reservation FOREIGN KEY (reservation_id, order_sheet_id)
                             REFERENCES reservation (id, order_sheet_id),
                         CONSTRAINT fk_payment_payer_share FOREIGN KEY (payer_share_id, order_sheet_id)
                             REFERENCES payer_share (id, order_sheet_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 21. PortOne 웹훅 수신 기록 (portone_payment_id는 외부 값이라 FK 없음)
CREATE TABLE webhook_event (
                               id                 BIGINT       NOT NULL AUTO_INCREMENT,
                               portone_webhook_id VARCHAR(255) COLLATE utf8mb4_0900_bin NOT NULL,
                               event_type         VARCHAR(100) NOT NULL,
                               portone_payment_id VARCHAR(100) COLLATE utf8mb4_0900_bin NULL,
                               status             VARCHAR(30)  NOT NULL,
                               received_at        DATETIME(6)  NOT NULL,
                               processed_at       DATETIME(6)  NULL,
                               duplicate_count    INT          NOT NULL,
                               PRIMARY KEY (id),
                               UNIQUE KEY webhook_event_u1 (portone_webhook_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 22. 업무 사건 (재실행해도 같은 사건은 1건: dedup_key)
CREATE TABLE business_event (
                                id               BIGINT       NOT NULL AUTO_INCREMENT,
                                event_type       VARCHAR(30)  NOT NULL,
                                dedup_key        VARCHAR(150) NOT NULL,
                                gathering_id     BIGINT       NOT NULL,
                                reservation_id   BIGINT       NULL,
                                store_request_id BIGINT       NULL,
                                payment_id       BIGINT       NULL,
                                recorded_at      DATETIME(6)  NOT NULL,
                                PRIMARY KEY (id),
                                UNIQUE KEY business_event_u1 (dedup_key),
                                CONSTRAINT fk_business_event_gathering FOREIGN KEY (gathering_id) REFERENCES gathering (id),
                                CONSTRAINT fk_business_event_reservation FOREIGN KEY (reservation_id) REFERENCES reservation (id),
                                CONSTRAINT fk_business_event_store_request FOREIGN KEY (store_request_id) REFERENCES store_request (id),
                                CONSTRAINT fk_business_event_payment FOREIGN KEY (payment_id) REFERENCES payment (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 23. 원결제별 환불 (같은 결정·같은 원결제 환불 1건)
CREATE TABLE refund (
                        id                         BIGINT       NOT NULL AUTO_INCREMENT,
                        business_event_id          BIGINT       NOT NULL,
                        payment_id                 BIGINT       NOT NULL,
                        amount                     BIGINT       NOT NULL,
                        current_cancellable_amount BIGINT       NOT NULL,
                        reason                     VARCHAR(255) NOT NULL,
                        idempotency_key            CHAR(36)     COLLATE utf8mb4_0900_bin NOT NULL,
                        status                     VARCHAR(30)  NOT NULL,
                        pg_cancellation_id         VARCHAR(255) COLLATE utf8mb4_0900_bin NULL,
                        fail_reason                VARCHAR(255) NULL,
                        received_at                DATETIME(6)  NOT NULL,
                        first_attempted_at         DATETIME(6)  NULL,
                        completed_at               DATETIME(6)  NULL,
                        last_reconciled_at         DATETIME(6)  NULL,
                        last_reconcile_result      VARCHAR(30)  NULL,
                        PRIMARY KEY (id),
                        UNIQUE KEY refund_u1 (business_event_id, payment_id),
                        UNIQUE KEY refund_u2 (idempotency_key),
                        UNIQUE KEY refund_u3 (pg_cancellation_id),
                        CONSTRAINT fk_refund_business_event FOREIGN KEY (business_event_id) REFERENCES business_event (id),
                        CONSTRAINT fk_refund_payment FOREIGN KEY (payment_id) REFERENCES payment (id),
                        CONSTRAINT ck_refund_amount_positive CHECK (amount > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 24. 손님 알림함 (source_id는 source_type에 따라 business_event 또는 refund를 가리키는 논리 참조)
CREATE TABLE notification (
                              id                  BIGINT       NOT NULL AUTO_INCREMENT,
                              source_type         VARCHAR(30)  NOT NULL,
                              source_id           BIGINT       NOT NULL,
                              notification_type   VARCHAR(30)  NOT NULL,
                              recipient_member_id BIGINT       NOT NULL,
                              summary             VARCHAR(255) NOT NULL,
                              deadline_at         DATETIME(6)  NULL,
                              created_at          DATETIME(6)  NOT NULL,
                              read_at             DATETIME(6)  NULL,
                              PRIMARY KEY (id),
                              UNIQUE KEY notification_u1 (source_type, source_id, notification_type, recipient_member_id),
                              CONSTRAINT fk_notification_recipient_member FOREIGN KEY (recipient_member_id) REFERENCES member (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 25. 매장 업무함 (source_id는 source_type에 따라 store_request 또는 business_event를 가리키는 논리 참조)
CREATE TABLE store_inbox (
                             id          BIGINT      NOT NULL AUTO_INCREMENT,
                             store_id    BIGINT      NOT NULL,
                             source_type VARCHAR(30) NOT NULL,
                             source_id   BIGINT      NOT NULL,
                             item_type   VARCHAR(30) NOT NULL,
                             status      VARCHAR(30) NOT NULL,
                             created_at  DATETIME(6) NOT NULL,
                             handled_by  BIGINT      NULL,
                             handled_at  DATETIME(6) NULL,
                             PRIMARY KEY (id),
                             UNIQUE KEY store_inbox_u1 (store_id, source_type, source_id, item_type),
                             CONSTRAINT fk_store_inbox_store FOREIGN KEY (store_id) REFERENCES store (id),
                             CONSTRAINT fk_store_inbox_handled_by FOREIGN KEY (handled_by) REFERENCES store_staff (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;