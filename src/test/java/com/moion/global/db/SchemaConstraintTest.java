package com.moion.global.db;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.moion.TestcontainersConfiguration;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.transaction.annotation.Transactional;

// 서비스 코드 없이 DB 제약만으로 잘못된 연결과 중복을 거부하고, 정상 값은 허용하는지 확인한다
// 데이터는 db/fixture/order-chain.sql 참고. 각 테스트는 트랜잭션 안에서 실행하고 끝나면 롤백한다
@SpringBootTest
@Import(TestcontainersConfiguration.class)
@Transactional
@Sql("/db/fixture/order-chain.sql")
class SchemaConstraintTest {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    // 결제와 주문서 연결

    @Test
    @DisplayName("같은 주문서의 예약과 결제자 몫으로 만든 결제는 저장된다")
    void acceptsPaymentLinkedWithinSameOrderSheet() {
        insertPaidPayment(101L, 1L, 11L, 1L, null);

        assertThat(count("SELECT COUNT(*) FROM payment")).isEqualTo(1);
    }

    @Test
    @DisplayName("OS1 예약의 결제에 OS2 결제자 몫을 연결할 수 없다")
    void rejectsPaymentWithPayerShareOfOtherOrderSheet() {
        // 예약 1(OS1), 몫 21(OS2), 결제에 적은 주문서 OS1
        assertThatThrownBy(() -> insertPaidPayment(102L, 1L, 21L, 1L, null))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("fk_payment_payer_share");
    }

    @Test
    @DisplayName("OS2 결제자 몫의 결제를 OS1 예약에 연결할 수 없다")
    void rejectsPaymentWithReservationOfOtherOrderSheet() {
        // 예약 1(OS1), 몫 21(OS2), 결제에 적은 주문서 OS2
        assertThatThrownBy(() -> insertPaidPayment(107L, 1L, 21L, 2L, null))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("fk_payment_reservation");
    }

    @Test
    @DisplayName("같은 몫의 두 번째 승인은 반영 인정 없이 저장되고, 반영 인정은 한 건뿐이다")
    void keepsDuplicateApprovalButCountsOnlyOne() {
        insertPaidPayment(103L, 1L, 11L, 1L, 11L);
        insertPaidPayment(104L, 1L, 11L, 1L, null);

        assertThat(count("SELECT COUNT(*) FROM payment WHERE payer_share_id = 11")).isEqualTo(2);
        assertThat(count("SELECT COUNT(*) FROM payment WHERE counted_share_id = 11")).isEqualTo(1);

        assertThatThrownBy(() -> jdbcTemplate.update("UPDATE payment SET counted_share_id = 11 WHERE id = 104"))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("payment_u2");
    }

    // 예약과 매장 요청

    @Test
    @DisplayName("같은 매장 요청으로 예약을 두 건 만들 수 없다")
    void rejectsSecondReservationForSameStoreRequest() {
        assertThatThrownBy(() -> insertReservation(1L, 1L))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("reservation_u1");
    }

    @Test
    @DisplayName("OS2 요청으로 OS1 예약을 만들 수 없다")
    void rejectsReservationWithOtherOrderSheet() {
        assertThatThrownBy(() -> insertReservation(2L, 1L))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("fk_reservation_store_request");
    }

    // 회차 정원

    @Test
    @DisplayName("정원 20인 회차의 확보 좌석 0과 20은 저장된다")
    void allowsSecuredCountFromZeroToCapacity() {
        jdbcTemplate.update("UPDATE time_slot SET secured_count = 0 WHERE id = 1");
        assertThat(securedCountOfSlot1()).isEqualTo(0);

        jdbcTemplate.update("UPDATE time_slot SET secured_count = 20 WHERE id = 1");
        assertThat(securedCountOfSlot1()).isEqualTo(20);
    }

    @Test
    @DisplayName("정원 20인 회차의 확보 좌석 -1과 21은 거부되고 기존 값 14가 유지된다")
    void rejectsSecuredCountBelowZeroOrOverCapacity() {
        assertThatThrownBy(() -> jdbcTemplate.update("UPDATE time_slot SET secured_count = -1 WHERE id = 1"))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("ck_time_slot_secured_count");

        assertThatThrownBy(() -> jdbcTemplate.update("UPDATE time_slot SET secured_count = 21 WHERE id = 1"))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("ck_time_slot_secured_count");

        assertThat(securedCountOfSlot1()).isEqualTo(14);
    }

    // 참여·차단·초대 링크

    @Test
    @DisplayName("모임 1에 참여 중인 회원 2는 같은 회차의 모임 2에 참여할 수 없다")
    void rejectsSecondActiveGatheringInSameTimeSlot() {
        assertThatThrownBy(() -> jdbcTemplate.update(
                "INSERT INTO participant (gathering_id, member_id, time_slot_id, status, "
                        + "reconfirm_from_revision, joined_at, active_slot_id) "
                        + "VALUES (2, 2, 1, 'JOINED', 1, '2026-11-28 12:40:00', 1)"))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("participant_u2");
    }

    @Test
    @DisplayName("유효한 차단은 모임·회원당 한 건이고, 해제한 뒤 다시 차단하면 이력이 2건 남는다")
    void keepsOneActiveBlockPerGatheringAndMember() {
        insertBlock(71L);

        assertThatThrownBy(() -> insertBlock(72L))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("gathering_block_u1");

        jdbcTemplate.update("UPDATE gathering_block SET unblocked_at = '2026-11-28 13:30:00' WHERE id = 71");
        insertBlock(73L);

        Map<String, Object> result = jdbcTemplate.queryForMap(
                "SELECT COUNT(*) AS total, SUM(active_key IS NOT NULL) AS active "
                        + "FROM gathering_block WHERE gathering_id = 2 AND member_id = 1");
        assertThat(((Number) result.get("total")).intValue()).isEqualTo(2);
        assertThat(((Number) result.get("active")).intValue()).isEqualTo(1);
    }

    @Test
    @DisplayName("한 모임의 유효한 초대 링크는 하나이고, 폐기한 뒤 새 버전을 발급하면 이력 2건·유효 1건이다")
    void keepsOneValidInviteLinkPerGathering() {
        insertInviteLink(81L, 1, "token-v1", "VALID");

        assertThatThrownBy(() -> insertInviteLink(82L, 2, "token-v2", "VALID"))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("invite_link_u3");

        jdbcTemplate.update("UPDATE invite_link SET status = 'REVOKED', ended_at = '2026-11-28 13:30:00' WHERE id = 81");
        insertInviteLink(83L, 2, "token-v2", "VALID");

        Map<String, Object> result = jdbcTemplate.queryForMap(
                "SELECT COUNT(*) AS total, SUM(active_gathering_id IS NOT NULL) AS valid "
                        + "FROM invite_link WHERE gathering_id = 2");
        assertThat(((Number) result.get("total")).intValue()).isEqualTo(2);
        assertThat(((Number) result.get("valid")).intValue()).isEqualTo(1);
    }

    @Test
    @DisplayName("초대 토큰은 발급한 문자열과 대소문자까지 같을 때만 조회된다")
    void findsInviteLinkOnlyByExactToken() {
        insertInviteLink(84L, 1, "AbC123", "VALID");

        assertThat(count("SELECT COUNT(*) FROM invite_link WHERE token = 'AbC123'")).isEqualTo(1);
        assertThat(count("SELECT COUNT(*) FROM invite_link WHERE token = 'abc123'")).isEqualTo(0);
    }

    // 직원 권한

    @Test
    @DisplayName("활성 직원 권한은 회원·매장당 한 건이고, 회수한 뒤에는 다시 부여할 수 있다")
    void keepsOneActiveStaffGrantPerMemberAndStore() {
        insertStaff(61L, "ACTIVE");

        assertThatThrownBy(() -> insertStaff(62L, "ACTIVE"))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("store_staff_u1");

        jdbcTemplate.update("UPDATE store_staff SET status = 'REVOKED', revoked_by = 3, "
                + "revoked_at = '2026-11-28 11:00:00' WHERE id = 61");
        insertStaff(63L, "ACTIVE");

        Map<String, Object> result = jdbcTemplate.queryForMap(
                "SELECT COUNT(*) AS total, SUM(active_key IS NOT NULL) AS active "
                        + "FROM store_staff WHERE member_id = 2 AND store_id = 1");
        assertThat(((Number) result.get("total")).intValue()).isEqualTo(2);
        assertThat(((Number) result.get("active")).intValue()).isEqualTo(1);
    }

    @Test
    @DisplayName("서로 다른 부여 요청 두 개는 같은 직원 이력을 가리킬 수 있고, 같은 요청 ID는 다시 저장할 수 없다")
    void linksManyGrantRequestsToOneStaffHistory() {
        insertGrantRequest("11111111-1111-1111-1111-111111111111", 51L);
        insertGrantRequest("22222222-2222-2222-2222-222222222222", 51L);

        assertThat(count("SELECT COUNT(*) FROM store_staff_grant_request WHERE store_staff_id = 51")).isEqualTo(2);

        assertThatThrownBy(() -> insertGrantRequest("11111111-1111-1111-1111-111111111111", 51L))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("PRIMARY");
    }

    // 환불

    @Test
    @DisplayName("같은 결정과 같은 원결제의 환불은 한 건뿐이다")
    void rejectsSecondRefundForSameDecisionAndPayment() {
        insertPaidPayment(105L, 1L, 11L, 1L, null);
        insertEarlyCloseEvent();
        insertRefund(105L, 20000L, "00000000-0000-0000-0000-000000000001");

        assertThatThrownBy(() -> insertRefund(105L, 20000L, "00000000-0000-0000-0000-000000000002"))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("refund_u1");
    }

    @Test
    @DisplayName("환불 금액은 0원일 수 없다")
    void rejectsZeroRefundAmount() {
        insertPaidPayment(106L, 1L, 11L, 1L, null);
        insertEarlyCloseEvent();

        assertThatThrownBy(() -> insertRefund(106L, 0L, "00000000-0000-0000-0000-000000000003"))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("ck_refund_amount_positive");
    }

    private Integer count(String sql) {
        return jdbcTemplate.queryForObject(sql, Integer.class);
    }

    private Integer securedCountOfSlot1() {
        return count("SELECT secured_count FROM time_slot WHERE id = 1");
    }

    private void insertReservation(Long storeRequestId, Long orderSheetId) {
        jdbcTemplate.update(
                "INSERT INTO reservation (store_request_id, order_sheet_id, secured_visitor_count, "
                        + "payment_start_deadline, payment_deadline, status) "
                        + "VALUES (?, ?, 2, '2026-11-28 17:45:00', '2026-11-28 17:50:00', 'PAYMENT_PENDING')",
                storeRequestId, orderSheetId);
    }

    // 승인·완료 기록 시각까지 채운 PAID 결제
    private void insertPaidPayment(Long paymentId, Long reservationId, Long payerShareId, Long orderSheetId,
                                   Long countedShareId) {
        jdbcTemplate.update(
                "INSERT INTO payment (id, portone_payment_id, reservation_id, payer_share_id, order_sheet_id, "
                        + "amount, status, started_at, pg_approved_at, recorded_paid_at, counted_share_id) "
                        + "VALUES (?, ?, ?, ?, ?, 20000, 'PAID', '2026-11-28 16:21:00', "
                        + "'2026-11-28 16:22:00', '2026-11-28 16:22:01', ?)",
                paymentId, "moion-pay-" + paymentId, reservationId, payerShareId, orderSheetId, countedShareId);
    }

    private void insertEarlyCloseEvent() {
        jdbcTemplate.update(
                "INSERT INTO business_event (id, event_type, dedup_key, gathering_id, reservation_id, recorded_at) "
                        + "VALUES (1, 'EARLY_CLOSED', 'EARLY_CLOSED:1', 1, 1, '2026-11-28 16:30:00')");
    }

    private void insertRefund(Long paymentId, Long amount, String idempotencyKey) {
        jdbcTemplate.update(
                "INSERT INTO refund (business_event_id, payment_id, amount, current_cancellable_amount, reason, "
                        + "idempotency_key, status, received_at) "
                        + "VALUES (1, ?, ?, 20000, '조기 종료', ?, 'RECEIVED', '2026-11-28 16:30:00')",
                paymentId, amount, idempotencyKey);
    }

    private void insertStaff(Long staffId, String status) {
        jdbcTemplate.update(
                "INSERT INTO store_staff (id, member_id, store_id, status, granted_by, granted_at) "
                        + "VALUES (?, 2, 1, ?, 3, '2026-11-28 10:00:00')",
                staffId, status);
    }

    private void insertGrantRequest(String grantRequestId, Long storeStaffId) {
        jdbcTemplate.update(
                "INSERT INTO store_staff_grant_request (grant_request_id, store_staff_id) VALUES (?, ?)",
                grantRequestId, storeStaffId);
    }

    // 모임 2의 예약자 회원 4가 회원 1을 차단
    private void insertBlock(Long blockId) {
        jdbcTemplate.update(
                "INSERT INTO gathering_block (id, gathering_id, member_id, blocked_by, blocked_at) "
                        + "VALUES (?, 2, 1, 4, '2026-11-28 13:00:00')",
                blockId);
    }

    // 모임 2의 초대 링크
    private void insertInviteLink(Long inviteLinkId, int version, String token, String status) {
        jdbcTemplate.update(
                "INSERT INTO invite_link (id, gathering_id, version, token, status, issued_at) "
                        + "VALUES (?, 2, ?, ?, ?, '2026-11-28 12:30:00')",
                inviteLinkId, version, token, status);
    }
}