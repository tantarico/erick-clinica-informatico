package com.clinicainformatica.api;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class QuotationPdfTest {
    @Test
    void downloadedQuotationUsesBrandedLayoutAndShowsActualLineAmounts() {
        JdbcTemplate jdbc=mock(JdbcTemplate.class);
        ClinicRepository repository=mock(ClinicRepository.class);
        UUID quotationId=UUID.randomUUID();
        UUID actorId=UUID.randomUUID();
        when(jdbc.queryForList(anyString(),any(Object[].class))).thenReturn(
            List.of(Map.ofEntries(
                Map.entry("id",quotationId.toString()),
                Map.entry("status","AUTORIZADA"),
                Map.entry("orderCode","OS-000123"),
                Map.entry("clientName","Greta del Valle"),
                Map.entry("documentType","CC"),
                Map.entry("documentNumber","123456"),
                Map.entry("clientPhone","3162123456"),
                Map.entry("equipmentType","Portátil"),
                Map.entry("brand","Lenovo"),
                Map.entry("model","ThinkPad"),
                Map.entry("serialNumber","SN-001"),
                Map.entry("description","Mantenimiento preventivo"),
                Map.entry("total","200000.00"),
                Map.entry("decisionObservations","Aprobada por el cliente"),
                Map.entry("decidedAt","2026-11-25 12:00:00"),
                Map.entry("createdAt","2026-11-24 12:00:00"))),
            List.of(Map.of(
                "type","SERVICIO",
                "description","Mantenimiento",
                "quantity","2.000",
                "unitPrice","100000.00",
                "subtotal","200000.00")));
        HttpServletRequest request=mock(HttpServletRequest.class);
        when(request.getAttribute("currentUser")).thenReturn(Map.of("id",actorId.toString()));

        QuotationDeliveryController controller=new QuotationDeliveryController(jdbc,repository);
        var response=controller.downloadQuotationPdf(quotationId,request);
        String pdf=new String(response.getBody().getByteArray(),StandardCharsets.ISO_8859_1);

        assertEquals("application/pdf",response.getHeaders().getContentType().toString());
        assertTrue(pdf.startsWith("%PDF-1.4"));
        assertTrue(pdf.contains("LA CLINICA DEL INFORMATICO"));
        assertTrue(pdf.contains("Greta del Valle"));
        assertTrue(pdf.contains("SERVICIO: Mantenimiento"));
        assertTrue(pdf.contains("Precio unit."));
        assertTrue(pdf.contains("S/ 100.00"));
        assertTrue(pdf.contains("S/ 200.00"));
        assertTrue(pdf.contains("Aprobada por el cliente"));
    }
}
