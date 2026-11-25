package com.clinicainformatica.api;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.util.*;

import org.springframework.core.io.ByteArrayResource;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/reports")
public class ReportExportController {
    private final SprintSixService service;

    public ReportExportController(SprintSixService service) {
        this.service = service;
    }

    @GetMapping("/service-indicators/{format}")
    public ResponseEntity<ByteArrayResource> export(
        @PathVariable String format,
        @RequestParam(required=false) @DateTimeFormat(iso=DateTimeFormat.ISO.DATE) LocalDate from,
        @RequestParam(required=false) @DateTimeFormat(iso=DateTimeFormat.ISO.DATE) LocalDate to,
        @RequestParam(required=false) String status,
        @RequestParam(required=false) UUID technician) {
        if(from != null && to != null && from.isAfter(to))
            throw new ApiException(HttpStatus.BAD_REQUEST,"invalid-date-range",
                "La fecha inicial no puede ser posterior a la fecha final.");
        Map<String,Object> report=service.serviceIndicators(from,to,status,technician);
        return switch(format.toLowerCase(Locale.ROOT)) {
            case "csv" -> download(csv(report), "reportes-servicios.csv", "text/csv");
            case "excel" -> download(excel(report), "reportes-servicios.xls",
                "application/vnd.ms-excel");
            case "pdf" -> download(pdf(report,from,to,status,technician), "reportes-servicios.pdf",
                "application/pdf");
            default -> throw new ApiException(HttpStatus.BAD_REQUEST,"invalid-format",
                "Formato de exportación no válido.");
        };
    }

    private ResponseEntity<ByteArrayResource> download(byte[] content, String filename,
        String mediaType) {
        HttpHeaders headers=new HttpHeaders();
        headers.setContentDisposition(ContentDisposition.attachment()
            .filename(filename, StandardCharsets.UTF_8).build());
        headers.setContentType(MediaType.parseMediaType(mediaType));
        return new ResponseEntity<>(new ByteArrayResource(content),headers,HttpStatus.OK);
    }

    private byte[] csv(Map<String,Object> report) {
        StringBuilder csv=new StringBuilder();
        csv.append("Métrica,Valor\n");
        for(String key:List.of("total","finalized","pending","in_progress",
            "finalized_percentage","average_attention_hours")) {
            csv.append(key).append(',').append(Objects.toString(report.get(key),"")).append('\n');
        }
        csv.append("\nTécnico,Atendidos,Finalizados\n");
        for(Map<String,Object> technician:(List<Map<String,Object>>)report.get("byTechnician")) {
            csv.append("\"").append(String.valueOf(technician.get("technicianName"))
                .replace("\"","\"\"")).append("\",")
                .append(technician.get("attended")).append(',')
                .append(technician.get("finalized")).append('\n');
        }
        return csv.toString().getBytes(StandardCharsets.UTF_8);
    }

    private byte[] excel(Map<String,Object> report) {
        StringBuilder xml=new StringBuilder("""
            <?xml version="1.0"?>
            <?mso-application progid="Excel.Sheet"?>
            <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
              xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
            <Worksheet ss:Name="Indicadores"><Table>
            <Row><Cell><Data ss:Type="String">Métrica</Data></Cell><Cell><Data ss:Type="String">Valor</Data></Cell></Row>
            """);
        for(String key:List.of("total","finalized","pending","in_progress",
            "finalized_percentage","average_attention_hours")) {
            xml.append("<Row><Cell><Data ss:Type=\"String\">").append(key)
                .append("</Data></Cell><Cell><Data ss:Type=\"String\">")
                .append(Objects.toString(report.get(key),"")).append("</Data></Cell></Row>");
        }
        xml.append("</Table></Worksheet></Workbook>");
        return xml.toString().getBytes(StandardCharsets.UTF_8);
    }

    private byte[] pdf(Map<String,Object> report,LocalDate from,LocalDate to,
        String status,UUID technicianId) {
        PdfDocument pdf=new PdfDocument();
        float accentRed=0.31f,accentGreen=0.38f,accentBlue=0.50f;
        float darkRed=0.07f,darkGreen=0.15f,darkBlue=0.31f;
        float mutedRed=0.42f,mutedGreen=0.38f,mutedBlue=0.44f;
        pdf.fillRectangle(0,782,612,10,accentRed,accentGreen,accentBlue);
        pdf.text(52,754,21,"INDICADORES",darkRed,darkGreen,darkBlue);
        pdf.text(52,729,19,"DE SERVICIOS",darkRed,darkGreen,darkBlue);
        pdf.text(374,757,9,"LA CLINICA DEL INFORMATICO",darkRed,darkGreen,darkBlue);
        pdf.text(374,740,8,"Generado: " + LocalDate.now().format(
            DateTimeFormatter.ofPattern("dd/MM/yyyy")),mutedRed,mutedGreen,mutedBlue);
        pdf.text(330,723,7,"Periodo: " + dateLabel(from) + " - " + dateLabel(to),
            mutedRed,mutedGreen,mutedBlue);
        String filterSummary="Estado: " + statusLabel(status);
        if(technicianId!=null)
            filterSummary+=" | Tecnico: " + selectedTechnicianName(report,technicianId);
        pdf.text(330,710,7,filterSummary,mutedRed,mutedGreen,mutedBlue);
        pdf.line(52,696,560,696,0.7f);

        pdf.text(52,678,12,"Indicadores",accentRed,accentGreen,accentBlue);
        metric(pdf,52,652,"Total de servicios",formatCount(report.get("total")),
            "Ordenes en el filtro seleccionado",darkRed,darkGreen,darkBlue,
            accentRed,accentGreen,accentBlue);
        metric(pdf,52,618,"Servicios finalizados",formatCount(report.get("finalized")),
            "Finalizados o cerrados",darkRed,darkGreen,darkBlue,
            accentRed,accentGreen,accentBlue);
        metric(pdf,52,584,"Porcentaje finalizado",
            formatNumber(report.get("finalized_percentage"),2) + "%",
            "Proporcion sobre el total",darkRed,darkGreen,darkBlue,
            accentRed,accentGreen,accentBlue);
        metric(pdf,52,550,"Promedio de atencion",
            hours(report.get("average_attention_hours")),
            "Solo servicios finalizados",darkRed,darkGreen,darkBlue,
            accentRed,accentGreen,accentBlue);

        pdf.text(330,678,9,"DISTRIBUCION DE SERVICIOS",darkRed,darkGreen,darkBlue);
        long total=count(report.get("total"));
        long finalized=count(report.get("finalized"));
        long pending=count(report.get("pending"));
        long inProgress=count(report.get("in_progress"));
        long cancelled=Math.max(0,total-finalized-pending-inProgress);
        statusBar(pdf,330,648,"Finalizados",finalized,total,
            accentRed,accentGreen,accentBlue);
        statusBar(pdf,330,620,"Pendientes",pending,total,
            accentRed,accentGreen,accentBlue);
        statusBar(pdf,330,592,"En atencion",inProgress,total,
            accentRed,accentGreen,accentBlue);
        statusBar(pdf,330,564,"Cancelados",cancelled,total,
            accentRed,accentGreen,accentBlue);

        pdf.line(52,526,560,526,0.6f);
        pdf.text(52,506,12,"Rendimiento por tecnico",accentRed,accentGreen,accentBlue);
        pdf.text(52,490,7,"Atenciones registradas y servicios finalizados",
            mutedRed,mutedGreen,mutedBlue);

        @SuppressWarnings("unchecked")
        List<Map<String,Object>> technicians=(List<Map<String,Object>>)report.get("byTechnician");
        List<Map<String,Object>> rankedTechnicians=new ArrayList<>(technicians);
        rankedTechnicians.sort(Comparator
            .comparingLong((Map<String,Object> row)->count(row.get("attended"))).reversed()
            .thenComparing(row->Objects.toString(row.get("technicianName"),"")));
        int displayedTechnicians=Math.min(rankedTechnicians.size(),7);
        if(rankedTechnicians.isEmpty())
            pdf.text(52,464,8,"No hay atenciones para los filtros seleccionados.",
                mutedRed,mutedGreen,mutedBlue);
        long maximumAttended=rankedTechnicians.stream()
            .mapToLong(row->count(row.get("attended"))).max().orElse(0);
        for(int i=0;i<displayedTechnicians;i++) {
            Map<String,Object> row=rankedTechnicians.get(i);
            float y=464-i*24;
            long attended=count(row.get("attended"));
            long technicianFinalized=count(row.get("finalized"));
            pdf.text(52,y,8,truncatePdf(Objects.toString(row.get("technicianName"),"Tecnico")),
                darkRed,darkGreen,darkBlue);
            pdf.text(52,y-11,7,"Atendidos " + attended + " | Finalizados "
                + technicianFinalized,mutedRed,mutedGreen,mutedBlue);
            pdf.fillRectangle(204,y-5,118,6,0.90f,0.92f,0.95f);
            if(maximumAttended>0)
                pdf.fillRectangle(204,y-5,118f*attended/maximumAttended,6,
                    accentRed,accentGreen,accentBlue);
        }
        if(rankedTechnicians.size()>displayedTechnicians)
            pdf.text(52,294,7,"Se muestran los 7 tecnicos con mas atenciones de "
                + rankedTechnicians.size() + ".",mutedRed,mutedGreen,mutedBlue);

        Map<?,?> comparison=(Map<?,?>)report.get("comparison");
        metricCard(pdf,374,443,"TECNICOS EN REPORTE",
            Integer.toString(technicians.size()),accentRed,accentGreen,accentBlue,
            darkRed,darkGreen,darkBlue);
        metricCard(pdf,374,372,"VARIACION VS. PERIODO ANTERIOR",
            signedPercent(comparison.get("variationPercent")),accentRed,accentGreen,accentBlue,
            darkRed,darkGreen,darkBlue);
        metricCard(pdf,374,301,"FINALIZADOS PERIODO ANTERIOR",
            formatCount(comparison.get("finalized")),accentRed,accentGreen,accentBlue,
            darkRed,darkGreen,darkBlue);
        pdf.text(374,235,7,"Comparacion: " + Objects.toString(comparison.get("periodFrom"),"")
            + " a " + Objects.toString(comparison.get("periodTo"),""),
            mutedRed,mutedGreen,mutedBlue);

        pdf.fillRectangle(0,0,612,30,darkRed,darkGreen,darkBlue);
        pdf.text(42,12,7,"LA CLINICA DEL INFORMATICO  |  REPORTE DE SERVICIOS",
            1,1,1);
        return pdf.build();
    }

    private static void metric(PdfDocument pdf,float x,float y,String label,String value,
        String description,float darkRed,float darkGreen,float darkBlue,
        float accentRed,float accentGreen,float accentBlue) {
        pdf.fillRectangle(x,y-9,3,25,accentRed,accentGreen,accentBlue);
        pdf.text(x+11,y+4,9,label,darkRed,darkGreen,darkBlue);
        pdf.text(x+11,y-8,7,description,0.42f,0.38f,0.44f);
        pdf.text(x+211,y-2,12,value,accentRed,accentGreen,accentBlue);
    }

    private static String hours(Object value) {
        if(value==null) return "Sin datos";
        return formatNumber(value,2) + " h";
    }

    private static void statusBar(PdfDocument pdf,float x,float y,String label,long value,
        long total,float red,float green,float blue) {
        pdf.text(x,y,7,label,0.30f,0.27f,0.32f);
        pdf.fillRectangle(x+79,y-4,100,7,0.90f,0.92f,0.95f);
        if(total>0 && value>0)
            pdf.fillRectangle(x+79,y-4,100f*value/total,7,red,green,blue);
        pdf.text(x+185,y-1,8,Long.toString(value),0.25f,0.22f,0.27f);
    }

    private static void metricCard(PdfDocument pdf,float x,float y,String label,String value,
        float accentRed,float accentGreen,float accentBlue,
        float darkRed,float darkGreen,float darkBlue) {
        pdf.fillRectangle(x,y-52,186,55,0.90f,0.92f,0.95f);
        pdf.fillRectangle(x,y-52,4,55,accentRed,accentGreen,accentBlue);
        pdf.text(x+13,y-17,7,label,darkRed,darkGreen,darkBlue);
        pdf.text(x+13,y-41,15,value,accentRed,accentGreen,accentBlue);
    }

    private static long count(Object value) {
        return ((Number)value).longValue();
    }

    private static String formatCount(Object value) {
        return formatNumber(value,0);
    }

    private static String formatNumber(Object value,int fractionDigits) {
        DecimalFormatSymbols symbols=DecimalFormatSymbols.getInstance(new Locale("es","CO"));
        DecimalFormat format=new DecimalFormat("#,##0.##",symbols);
        format.setMaximumFractionDigits(fractionDigits);
        format.setMinimumFractionDigits(fractionDigits);
        return format.format(((Number)value).doubleValue());
    }

    private static String signedPercent(Object value) {
        double variation=((Number)value).doubleValue();
        return (variation>0?"+":"") + formatNumber(value,2) + "%";
    }

    private static String dateLabel(LocalDate date) {
        return date==null?"Sin limite":date.format(DateTimeFormatter.ofPattern("dd/MM/yyyy"));
    }

    private static String statusLabel(String status) {
        if(status==null || status.isBlank()) return "Todos";
        return switch(status) {
            case "PENDIENTE" -> "Pendiente";
            case "ASIGNADA" -> "Asignada";
            case "EN_ATENCION" -> "En atencion";
            case "FINALIZADA" -> "Finalizada";
            case "CERRADA" -> "Cerrada";
            case "CANCELADA" -> "Cancelada";
            default -> status;
        };
    }

    private static String selectedTechnicianName(Map<String,Object> report,UUID technicianId) {
        @SuppressWarnings("unchecked")
        List<Map<String,Object>> technicians=(List<Map<String,Object>>)report.get("byTechnician");
        return technicians.stream()
            .filter(row->technicianId.toString().equals(row.get("technicianId")))
            .map(row->Objects.toString(row.get("technicianName"),""))
            .findFirst().orElse("Seleccionado");
    }

    private static String truncatePdf(String value) {
        return value.length()>28?value.substring(0,25)+"...":value;
    }
}
