package com.clinicainformatica.api;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ReportExportPdfTest {
    @Test
    void pdfExportPresentsServiceIndicatorsAndTechnicianData() {
        SprintSixService service=mock(SprintSixService.class);
        UUID technicianId=UUID.randomUUID();
        Map<String,Object> technician=Map.of(
            "technicianId",technicianId.toString(),
            "technicianName","Ana Torres",
            "attended",4L,
            "finalized",3L);
        Map<String,Object> comparison=Map.of(
            "variationPercent",25.0,
            "finalized",2L,
            "periodFrom","2026-10-01",
            "periodTo","2026-10-30");
        Map<String,Object> report=Map.of(
            "total",10L,
            "finalized",6L,
            "pending",2L,
            "in_progress",1L,
            "finalized_percentage",60.0,
            "average_attention_hours",2.5,
            "byTechnician",List.of(technician),
            "comparison",comparison);
        when(service.serviceIndicators(null,null,"PENDIENTE",technicianId))
            .thenReturn(report);

        ReportExportController controller=new ReportExportController(service);
        var response=controller.export("pdf",null,null,"PENDIENTE",technicianId);
        String pdf=new String(response.getBody().getByteArray(),StandardCharsets.ISO_8859_1);

        assertEquals("application/pdf",response.getHeaders().getContentType().toString());
        assertTrue(pdf.startsWith("%PDF-1.4"));
        assertTrue(pdf.contains("INDICADORES"));
        assertTrue(pdf.contains("DISTRIBUCION DE SERVICIOS"));
        assertTrue(pdf.contains("Porcentaje finalizado"));
        assertTrue(pdf.contains("2,50 h"));
        assertTrue(pdf.contains("Ana Torres"));
        assertTrue(pdf.contains("+25,00%"));
        assertTrue(pdf.contains("Estado: Pendiente"));
        assertTrue(pdf.contains("FINALIZADOS PERIODO ANTERIOR"));
    }
}
