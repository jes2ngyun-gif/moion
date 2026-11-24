package com.moion.global.db;

import static org.assertj.core.api.Assertions.assertThat;

import com.moion.TestcontainersConfiguration;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.output.MigrateResult;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;

// 빈 MySQL에 Flyway V1을 적용한 뒤, 확정 ERD(docs/erd.dbml)와 같은 구조인지 확인한다
// 개수뿐 아니라 FK·유일 키가 어떤 컬럼을 어떤 순서로 연결하는지까지 비교한다
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class FlywaySchemaTest {

    private static final String FLYWAY_HISTORY_TABLE = "flyway_schema_history";

    private static final Set<String> BUSINESS_TABLES = Set.of(
            "member", "store", "store_staff", "store_staff_grant_request", "time_slot",
            "menu", "gathering", "invite_link", "participant", "gathering_block",
            "companion", "cart_item", "amount_confirmation", "share_exclusion_consent", "order_sheet",
            "order_sheet_item", "payer_share", "store_request", "reservation", "payment",
            "webhook_event", "business_event", "refund", "notification", "store_inbox");

    // FK 이름: 자식 테이블(자식 컬럼 순서) -> 부모 테이블(부모 컬럼 순서)
    private static final Set<String> FOREIGN_KEYS = Set.of(
            "fk_amount_confirmation_participant: amount_confirmation(gathering_id,member_id) -> participant(gathering_id,member_id)",
            "fk_amount_confirmation_time_slot: amount_confirmation(time_slot_id) -> time_slot(id)",
            "fk_business_event_gathering: business_event(gathering_id) -> gathering(id)",
            "fk_business_event_payment: business_event(payment_id) -> payment(id)",
            "fk_business_event_reservation: business_event(reservation_id) -> reservation(id)",
            "fk_business_event_store_request: business_event(store_request_id) -> store_request(id)",
            "fk_cart_item_gathering: cart_item(gathering_id) -> gathering(id)",
            "fk_cart_item_menu: cart_item(menu_id) -> menu(id)",
            "fk_cart_item_updated_by: cart_item(updated_by) -> member(id)",
            "fk_companion_participant: companion(participant_id) -> participant(id)",
            "fk_gathering_block_blocked_by: gathering_block(blocked_by) -> member(id)",
            "fk_gathering_block_gathering: gathering_block(gathering_id) -> gathering(id)",
            "fk_gathering_block_member: gathering_block(member_id) -> member(id)",
            "fk_gathering_host_member: gathering(host_member_id) -> member(id)",
            "fk_gathering_time_slot: gathering(time_slot_id) -> time_slot(id)",
            "fk_invite_link_gathering: invite_link(gathering_id) -> gathering(id)",
            "fk_menu_store: menu(store_id) -> store(id)",
            "fk_notification_recipient_member: notification(recipient_member_id) -> member(id)",
            "fk_order_sheet_gathering: order_sheet(gathering_id) -> gathering(id)",
            "fk_order_sheet_item_menu: order_sheet_item(menu_id) -> menu(id)",
            "fk_order_sheet_item_order_sheet: order_sheet_item(order_sheet_id) -> order_sheet(id)",
            "fk_order_sheet_time_slot: order_sheet(time_slot_id) -> time_slot(id)",
            "fk_participant_gathering: participant(gathering_id) -> gathering(id)",
            "fk_participant_member: participant(member_id) -> member(id)",
            "fk_participant_time_slot: participant(time_slot_id) -> time_slot(id)",
            "fk_payer_share_amount_confirmation: payer_share(amount_confirmation_id) -> amount_confirmation(id)",
            "fk_payer_share_member: payer_share(member_id) -> member(id)",
            "fk_payer_share_order_sheet: payer_share(order_sheet_id) -> order_sheet(id)",
            "fk_payer_share_share_exclusion_consent: payer_share(share_exclusion_consent_id) -> share_exclusion_consent(id)",
            "fk_payment_payer_share: payment(payer_share_id,order_sheet_id) -> payer_share(id,order_sheet_id)",
            "fk_payment_reservation: payment(reservation_id,order_sheet_id) -> reservation(id,order_sheet_id)",
            "fk_refund_business_event: refund(business_event_id) -> business_event(id)",
            "fk_refund_payment: refund(payment_id) -> payment(id)",
            "fk_reservation_store_request: reservation(store_request_id,order_sheet_id) -> store_request(id,order_sheet_id)",
            "fk_share_exclusion_consent_participant: share_exclusion_consent(gathering_id,member_id) -> participant(gathering_id,member_id)",
            "fk_store_inbox_handled_by: store_inbox(handled_by) -> store_staff(id)",
            "fk_store_inbox_store: store_inbox(store_id) -> store(id)",
            "fk_store_request_order_sheet: store_request(order_sheet_id) -> order_sheet(id)",
            "fk_store_request_responded_by: store_request(responded_by) -> store_staff(id)",
            "fk_store_staff_grant_request_store_staff: store_staff_grant_request(store_staff_id) -> store_staff(id)",
            "fk_store_staff_granted_by: store_staff(granted_by) -> member(id)",
            "fk_store_staff_member: store_staff(member_id) -> member(id)",
            "fk_store_staff_revoked_by: store_staff(revoked_by) -> member(id)",
            "fk_store_staff_store: store_staff(store_id) -> store(id)",
            "fk_time_slot_store: time_slot(store_id) -> store(id)");

    // 테이블.유일 키 이름(컬럼 순서), PK 제외
    private static final Set<String> UNIQUE_KEYS = Set.of(
            "amount_confirmation.amount_confirmation_u1(gathering_id,member_id,draft_revision)",
            "business_event.business_event_u1(dedup_key)",
            "cart_item.cart_item_u1(gathering_id,menu_id)",
            "gathering_block.gathering_block_u1(active_key)",
            "invite_link.invite_link_u1(token)",
            "invite_link.invite_link_u2(gathering_id,version)",
            "invite_link.invite_link_u3(active_gathering_id)",
            "member.member_u1(email)",
            "member.member_u2(di_hash)",
            "notification.notification_u1(source_type,source_id,notification_type,recipient_member_id)",
            "order_sheet.order_sheet_u1(gathering_id,version)",
            "order_sheet_item.order_sheet_item_u1(order_sheet_id,menu_id)",
            "participant.participant_u1(gathering_id,member_id)",
            "participant.participant_u2(member_id,active_slot_id)",
            "payer_share.payer_share_u1(order_sheet_id,member_id)",
            "payer_share.payer_share_u2(id,order_sheet_id)",
            "payment.payment_u1(portone_payment_id)",
            "payment.payment_u2(counted_share_id)",
            "refund.refund_u1(business_event_id,payment_id)",
            "refund.refund_u2(idempotency_key)",
            "refund.refund_u3(pg_cancellation_id)",
            "reservation.reservation_u1(store_request_id)",
            "reservation.reservation_u2(id,order_sheet_id)",
            "share_exclusion_consent.share_exclusion_consent_u1(gathering_id,member_id,draft_revision)",
            "store_inbox.store_inbox_u1(store_id,source_type,source_id,item_type)",
            "store_request.store_request_u1(order_sheet_id)",
            "store_request.store_request_u2(id,order_sheet_id)",
            "store_staff.store_staff_u1(active_key)",
            "webhook_event.webhook_event_u1(portone_webhook_id)");

    private static final Set<String> CHECK_CONSTRAINTS = Set.of(
            "ck_store_party_range", "ck_time_slot_secured_count", "ck_menu_alcohol_not_preorderable",
            "ck_companion_share_units", "ck_cart_item_quantity", "ck_order_sheet_item_line_amount",
            "ck_refund_amount_positive");

    private static final Set<String> GENERATED_COLUMNS = Set.of(
            "store_staff.active_key", "invite_link.active_gathering_id", "gathering_block.active_key");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private Flyway flyway;

    @Test
    @DisplayName("Flyway 이력에 V1이 성공으로 한 번 기록된다")
    void v1MigrationIsRecordedAsSuccess() {
        assertThat(countSuccessfulV1()).isEqualTo(1);
    }

    @Test
    @DisplayName("같은 DB에 다시 migrate해도 추가 적용은 0건이고 V1 성공 이력은 1건이다")
    void secondMigrateAppliesNothing() {
        MigrateResult result = flyway.migrate();

        assertThat(result.migrationsExecuted).isZero();
        assertThat(countSuccessfulV1()).isEqualTo(1);
    }

    @Test
    @DisplayName("Flyway 이력 테이블을 빼면 업무 테이블은 ERD의 25개와 정확히 같다")
    void createsExactly25BusinessTables() {
        List<String> tableNames = jdbcTemplate.queryForList(
                "SELECT TABLE_NAME FROM information_schema.TABLES "
                        + "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'",
                String.class);

        Set<String> businessTables = new HashSet<>();
        boolean hasHistoryTable = false;
        for (String tableName : tableNames) {
            if (tableName.equals(FLYWAY_HISTORY_TABLE)) {
                hasHistoryTable = true;
            } else {
                businessTables.add(tableName);
            }
        }

        assertThat(hasHistoryTable).isTrue();
        assertThat(businessTables).hasSize(25);
        assertThat(businessTables).isEqualTo(BUSINESS_TABLES);
    }

    @Test
    @DisplayName("업무 테이블의 컬럼은 204개다")
    void createsErdColumnCount() {
        Integer columnCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM information_schema.COLUMNS "
                        + "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME <> ?",
                Integer.class, FLYWAY_HISTORY_TABLE);

        assertThat(columnCount).isEqualTo(204);
    }

    @Test
    @DisplayName("FK 45개가 ERD와 같은 자식 컬럼에서 같은 부모 컬럼을 같은 순서로 가리킨다")
    void foreignKeysMatchErd() {
        List<String> foreignKeys = jdbcTemplate.queryForList(
                "SELECT CONCAT(CONSTRAINT_NAME, ': ', TABLE_NAME, "
                        + "'(', GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION), ') -> ', "
                        + "REFERENCED_TABLE_NAME, "
                        + "'(', GROUP_CONCAT(REFERENCED_COLUMN_NAME ORDER BY ORDINAL_POSITION), ')') "
                        + "FROM information_schema.KEY_COLUMN_USAGE "
                        + "WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL "
                        + "GROUP BY CONSTRAINT_NAME, TABLE_NAME, REFERENCED_TABLE_NAME",
                String.class);

        assertThat(foreignKeys).hasSize(45);
        assertThat(new HashSet<>(foreignKeys)).isEqualTo(FOREIGN_KEYS);
    }

    @Test
    @DisplayName("유일 키 29개가 ERD와 같은 테이블·이름·컬럼 순서로 만들어진다")
    void uniqueKeysMatchErd() {
        List<String> uniqueKeys = jdbcTemplate.queryForList(
                "SELECT CONCAT(TABLE_NAME, '.', INDEX_NAME, "
                        + "'(', GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX), ')') "
                        + "FROM information_schema.STATISTICS "
                        + "WHERE TABLE_SCHEMA = DATABASE() AND NON_UNIQUE = 0 "
                        + "AND INDEX_NAME <> 'PRIMARY' AND TABLE_NAME <> ? "
                        + "GROUP BY TABLE_NAME, INDEX_NAME",
                String.class, FLYWAY_HISTORY_TABLE);

        assertThat(uniqueKeys).hasSize(29);
        assertThat(new HashSet<>(uniqueKeys)).isEqualTo(UNIQUE_KEYS);
    }

    @Test
    @DisplayName("CHECK 7개와 생성 열 3개가 만들어진다")
    void createsChecksAndGeneratedColumns() {
        List<String> checkNames = jdbcTemplate.queryForList(
                "SELECT CONSTRAINT_NAME FROM information_schema.CHECK_CONSTRAINTS "
                        + "WHERE CONSTRAINT_SCHEMA = DATABASE()",
                String.class);

        List<String> generatedColumns = jdbcTemplate.queryForList(
                "SELECT CONCAT(TABLE_NAME, '.', COLUMN_NAME) FROM information_schema.COLUMNS "
                        + "WHERE TABLE_SCHEMA = DATABASE() AND EXTRA LIKE '%STORED GENERATED%'",
                String.class);

        assertThat(new HashSet<>(checkNames)).isEqualTo(CHECK_CONSTRAINTS);
        assertThat(new HashSet<>(generatedColumns)).isEqualTo(GENERATED_COLUMNS);
    }

    private Integer countSuccessfulV1() {
        return jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM flyway_schema_history WHERE version = '1' AND success = 1",
                Integer.class);
    }
}