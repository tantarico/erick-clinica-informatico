package com.clinicainformatica.api;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SprintSixService {
    private final JdbcTemplate jdbc;

    public SprintSixService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Map<String, Object> dashboardIndicators() {
        Map<String, Object> result = jdbc.queryForMap("""
            SELECT count(*) AS total,
              count(*) FILTER (WHERE status_code IN ('PENDIENTE','ASIGNADA')) AS pending,
              count(*) FILTER (WHERE status_code='EN_ATENCION') AS in_progress,
              count(*) FILTER (WHERE status_code IN ('FINALIZADA','CERRADA')) AS finalized
            FROM service_orders
            """);
        result.put("byStatus", jdbc.queryForList("""
            SELECT status_code AS status,count(*) AS total
            FROM service_orders
            GROUP BY status_code
            ORDER BY status_code
            """));
        result.put("byMonth", jdbc.queryForList("""
            SELECT to_char(months.month,'YYYY-MM') AS month,
              count(orders.id) AS total
            FROM generate_series(
              date_trunc('month',CURRENT_DATE) - interval '11 months',
              date_trunc('month',CURRENT_DATE),
              interval '1 month'
            ) AS months(month)
            LEFT JOIN service_orders orders
              ON date_trunc('month',orders.received_at) = months.month
            GROUP BY months.month
            ORDER BY months.month
            """));
        return result;
    }

    public Map<String, Object> serviceIndicators(LocalDate from, LocalDate to, String status,
        UUID technicianId) {
        String selectedStatus = status == null ? "" : status;
        Map<String, Object> totals = jdbc.queryForMap("""
            WITH filtered AS (
              SELECT orders.id,orders.status_code
              FROM service_orders orders
              WHERE (?::date IS NULL OR orders.received_at >= ?::date)
                AND (?::date IS NULL OR orders.received_at <= ?::date)
                AND (? = '' OR orders.status_code = ?)
                AND (?::uuid IS NULL OR EXISTS (
                  SELECT 1 FROM technician_assignments selected
                  WHERE selected.order_id=orders.id AND selected.technician_id=?::uuid
                ))
            )
            SELECT count(*) AS total,
              count(*) FILTER (WHERE filtered.status_code IN ('FINALIZADA','CERRADA')) AS finalized,
              count(*) FILTER (WHERE filtered.status_code IN ('PENDIENTE','ASIGNADA')) AS pending,
              count(*) FILTER (WHERE filtered.status_code='EN_ATENCION') AS in_progress,
              CASE WHEN count(*)=0 THEN 0
                ELSE round(100.0 * count(*) FILTER (
                  WHERE filtered.status_code IN ('FINALIZADA','CERRADA')) / count(*),2)
              END AS finalized_percentage,
              avg(extract(epoch FROM (orders.finalized_at-orders.created_at))/3600.0) FILTER (
                WHERE filtered.status_code IN ('FINALIZADA','CERRADA')
                  AND orders.finalized_at IS NOT NULL) AS average_attention_hours
            FROM filtered
            JOIN service_orders orders ON orders.id=filtered.id
            """, from, from, to, to, selectedStatus, selectedStatus, technicianId, technicianId);
        totals.put("byTechnician", jdbc.queryForList("""
            WITH filtered AS (
              SELECT orders.id,orders.status_code
              FROM service_orders orders
              WHERE (?::date IS NULL OR orders.received_at >= ?::date)
                AND (?::date IS NULL OR orders.received_at <= ?::date)
                AND (? = '' OR orders.status_code = ?)
                AND (?::uuid IS NULL OR EXISTS (
                  SELECT 1 FROM technician_assignments selected
                  WHERE selected.order_id=orders.id AND selected.technician_id=?::uuid
                ))
            )
            SELECT technician.id::text AS "technicianId",
              btrim(technician.first_name || ' ' || technician.last_name) AS "technicianName",
              count(DISTINCT attention.order_id) AS attended,
              count(DISTINCT attention.order_id) FILTER (
                WHERE filtered.status_code IN ('FINALIZADA','CERRADA')) AS finalized
            FROM filtered
            JOIN technician_assignments assignment ON assignment.order_id=filtered.id
            JOIN users technician ON technician.id=assignment.technician_id
            LEFT JOIN technical_attentions attention
              ON attention.order_id=filtered.id AND attention.technician_id=technician.id
            WHERE (?::uuid IS NULL OR technician.id=?::uuid)
            GROUP BY technician.id,technician.first_name,technician.last_name
            ORDER BY technician.first_name,technician.last_name,technician.id
            """, from, from, to, to, selectedStatus, selectedStatus, technicianId, technicianId,
            technicianId, technicianId));
        LocalDate comparisonFrom = from;
        LocalDate comparisonTo = to;
        if (comparisonFrom == null) comparisonFrom = LocalDate.now().minusDays(29);
        if (comparisonTo == null) comparisonTo = LocalDate.now();
        long days = java.time.temporal.ChronoUnit.DAYS.between(comparisonFrom, comparisonTo) + 1;
        LocalDate previousTo = comparisonFrom.minusDays(1);
        LocalDate previousFrom = previousTo.minusDays(days - 1);
        Map<String,Object> previous = jdbc.queryForMap("""
            SELECT count(*) AS total,
              count(*) FILTER (WHERE status_code IN ('FINALIZADA','CERRADA')) AS finalized,
              CASE WHEN count(*)=0 THEN 0
                ELSE round(100.0 * count(*) FILTER (
                  WHERE status_code IN ('FINALIZADA','CERRADA')) / count(*),2)
              END AS finalized_percentage
            FROM service_orders
            WHERE received_at >= ?::date AND received_at <= ?::date
              AND (? = '' OR status_code = ?)
              AND (?::uuid IS NULL OR EXISTS (
                SELECT 1 FROM technician_assignments selected
                WHERE selected.order_id=service_orders.id
                  AND selected.technician_id=?::uuid
              ))
            """, previousFrom, previousTo, selectedStatus, selectedStatus,
            technicianId, technicianId);
        Object currentFinalized = totals.get("finalized");
        Object previousFinalized = previous.get("finalized");
        double currentValue = currentFinalized == null ? 0 : ((Number)currentFinalized).doubleValue();
        double previousValue = previousFinalized == null ? 0 : ((Number)previousFinalized).doubleValue();
        double variation = previousValue == 0
            ? (currentValue == 0 ? 0 : 100)
            : ((currentValue - previousValue) * 100.0 / previousValue);
        Map<String,Object> comparison = new LinkedHashMap<>();
        comparison.put("periodFrom", previousFrom.toString());
        comparison.put("periodTo", previousTo.toString());
        comparison.put("total", previous.get("total"));
        comparison.put("finalized", previousFinalized);
        comparison.put("finalizedPercentage", previous.get("finalized_percentage"));
        comparison.put("variationPercent", Math.round(variation * 100.0) / 100.0);
        totals.put("comparison", comparison);
        return totals;
    }

    public Map<String, Object> auditEvents(int page, int size, String search, UUID userId,
        String module, LocalDate from, LocalDate to, String result) {
        int offset = Math.multiplyExact(page, size);
        String term = "%" + search.trim().toLowerCase() + "%";
        String selectedModule = module == null ? "" : module;
        String selectedResult = result == null ? "" : result;
        Long total = jdbc.queryForObject("""
            SELECT count(*)
            FROM system_events event
            LEFT JOIN users actor ON actor.id=event.actor_id
            WHERE (? = '%%' OR lower(concat_ws(' ',event.description,event.event_type,
                    event.entity_type,actor.first_name,actor.last_name,actor.username)) LIKE ?)
              AND (?::uuid IS NULL OR event.actor_id=?::uuid)
              AND (? = '' OR event.entity_type=?)
              AND (?::date IS NULL OR event.occurred_at::date >= ?::date)
              AND (?::date IS NULL OR event.occurred_at::date <= ?::date)
              AND (? = '' OR event.result=?)
            """, Long.class, term, term, userId, userId, selectedModule, selectedModule,
            from, from, to, to, selectedResult, selectedResult);
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT event.id::text AS id,event.occurred_at AS "occurredAt",
              actor.id::text AS "userId",
              CASE WHEN actor.id IS NULL THEN 'Usuario desconocido'
                ELSE btrim(actor.first_name || ' ' || actor.last_name) END AS "userName",
              actor.username AS username,event.entity_type AS module,event.event_type AS action,
              event.result AS result,event.description AS description,event.entity_id::text AS "entityId"
            FROM system_events event
            LEFT JOIN users actor ON actor.id=event.actor_id
            WHERE (? = '%%' OR lower(concat_ws(' ',event.description,event.event_type,
                    event.entity_type,actor.first_name,actor.last_name,actor.username)) LIKE ?)
              AND (?::uuid IS NULL OR event.actor_id=?::uuid)
              AND (? = '' OR event.entity_type=?)
              AND (?::date IS NULL OR event.occurred_at::date >= ?::date)
              AND (?::date IS NULL OR event.occurred_at::date <= ?::date)
              AND (? = '' OR event.result=?)
            ORDER BY event.occurred_at DESC,event.id DESC
            LIMIT ? OFFSET ?
            """, term, term, userId, userId, selectedModule, selectedModule, from, from, to, to,
            selectedResult, selectedResult, size, offset);
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("items", rows);
        response.put("page", page);
        response.put("size", size);
        response.put("total", total == null ? 0 : total);
        return response;
    }

    public Map<String, Object> monitor(String apiKeyConfigured) {
        long start = System.nanoTime();
        Map<String, Object> database = new LinkedHashMap<>();
        boolean databaseAvailable;
        try {
            jdbc.queryForObject("SELECT 1", Integer.class);
            databaseAvailable = true;
            database.put("status", "OK");
            database.put("message", "PostgreSQL responde correctamente.");
        } catch (DataAccessException e) {
            databaseAvailable = false;
            database.put("status", "ERROR");
            database.put("message", "No se pudo comprobar la conexión a PostgreSQL.");
        }
        long elapsed = (System.nanoTime() - start) / 1_000_000;
        Map<String, Object> backend = Map.of("status", "OK", "message", "La aplicación está respondiendo.");
        boolean configured = apiKeyConfigured != null && !apiKeyConfigured.isBlank();
        Map<String, Object> ai;
        if (!configured) {
            ai = Map.of(
                "status", "ALERTA",
                "configured", false,
                "verified", false,
                "message", "Gemini no está configurado.");
        } else if (databaseAvailable) {
            List<Map<String, Object>> aiChecks = jdbc.queryForList("""
                SELECT status,message,checked_at AS "checkedAt"
                FROM monitoring_checks
                WHERE component='gemini'
                  AND message IN ('Solicitud Gemini completada','Solicitud Gemini fallida')
                ORDER BY checked_at DESC,id DESC
                LIMIT 1
                """);
            if (aiChecks.isEmpty()) {
                ai = Map.of(
                    "status", "ALERTA",
                    "configured", true,
                    "verified", false,
                    "message", "Configurado; aún no se ha verificado con una solicitud real.");
            } else {
                Map<String, Object> latestCheck = aiChecks.getFirst();
                boolean available = "OK".equals(latestCheck.get("status"));
                ai = Map.of(
                    "status", available ? "OK" : "ERROR",
                    "configured", true,
                    "verified", true,
                    "message", available
                        ? "Gemini respondió correctamente en la última solicitud real."
                        : "Gemini no completó correctamente la última solicitud real.",
                    "checkedAt", latestCheck.get("checkedAt"));
            }
        } else {
            ai = Map.of(
                "status", "ALERTA",
                "configured", true,
                "verified", false,
                "message", "La configuración de Gemini existe, pero no se pudo comprobar su estado.");
        }
        List<Map<String, Object>> recentErrors = List.of();
        if (databaseAvailable) {
            try {
                jdbc.update("""
                    INSERT INTO monitoring_checks(component,status,response_time_ms,message)
                    VALUES ('backend','OK',?,'Aplicación disponible'),
                      ('postgresql','OK',?,'Conexión verificada')
                    """, elapsed, elapsed);
                recentErrors = jdbc.queryForList("""
                    SELECT event.occurred_at AS "occurredAt",event.entity_type AS module,
                      event.event_type AS action,event.description AS message
                    FROM system_events event
                    WHERE event.result='FAILED'
                    ORDER BY event.occurred_at DESC,event.id DESC
                    LIMIT 20
                    """);
            } catch (DataAccessException e) {
                database.put("eventsAvailable", false);
                database.put("status", "ALERTA");
                database.put("message", "PostgreSQL responde, pero no se pudo registrar la verificación.");
            }
        }
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("status", databaseAvailable ? "OK" : "ALERTA");
        response.put("backend", backend);
        response.put("database", database);
        response.put("ai", ai);
        response.put("responseTimeMs", elapsed);
        response.put("checkedAt", java.time.OffsetDateTime.now(java.time.ZoneOffset.UTC));
        response.put("recentErrors", recentErrors);
        return response;
    }

    @Transactional
    public void completeBackup(UUID actorId, UUID backupId, String filePath, String checksum) {
        jdbc.update("""
            UPDATE backup_runs
            SET status='COMPLETADO',file_path=?,checksum_sha256=?,finished_at=now()
            WHERE id=?
            """, filePath, checksum, backupId);
        recordBackupEvent(actorId, backupId, "SUCCESS", "Respaldo de PostgreSQL generado correctamente");
    }

    @Transactional
    public void recordBackupEvent(UUID actorId, UUID backupId, String result, String description) {
        jdbc.update("""
            INSERT INTO system_events(actor_id,event_type,entity_type,entity_id,result,description)
            VALUES (?,?,?,?,?,?)
            """, actorId, "BACKUP", "backup_runs", backupId, result, description);
    }

    @Transactional
    public void completeRestoration(UUID actorId, UUID restoredBackupId, UUID safetyBackupId,
        String restoredFile, String restoredChecksum, String safetyBackupFile, String safetyChecksum) {
        UUID persistedActorId = jdbc.queryForList(
            "SELECT id FROM users WHERE id=?", actorId).isEmpty() ? null : actorId;
        upsertCompletedBackup(persistedActorId, restoredBackupId, restoredFile, restoredChecksum);
        upsertCompletedBackup(persistedActorId, safetyBackupId, safetyBackupFile, safetyChecksum);
        recordBackupEvent(persistedActorId, safetyBackupId, "SUCCESS",
            "Copia de seguridad previa a la restauración");
        recordRestoreEvent(persistedActorId, restoredBackupId, "SUCCESS",
            "Restauración autorizada por administrador " + actorId);
    }

    @Transactional
    public void recordRestoreEvent(UUID actorId, UUID backupId, String result, String description) {
        jdbc.update("""
            INSERT INTO system_events(actor_id,event_type,entity_type,entity_id,result,description)
            VALUES (?,'RESTORE_BACKUP','backup_runs',?,?,?)
            """, actorId, backupId, result, description);
    }

    private void upsertCompletedBackup(UUID actorId, UUID backupId, String filePath, String checksum) {
        jdbc.update("""
            INSERT INTO backup_runs(id,requested_by,status,file_path,checksum_sha256,started_at,finished_at)
            VALUES (?,?,'COMPLETADO',?,?,now(),now())
            ON CONFLICT(id) DO UPDATE SET status='COMPLETADO',file_path=EXCLUDED.file_path,
              checksum_sha256=EXCLUDED.checksum_sha256,finished_at=now(),error_message=NULL
            """, backupId, actorId, filePath, checksum);
    }

}
