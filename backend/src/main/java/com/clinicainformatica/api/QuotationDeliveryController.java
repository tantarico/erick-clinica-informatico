package com.clinicainformatica.api;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.time.LocalDateTime;
import java.util.*;

import org.springframework.http.HttpStatus;
import org.springframework.http.*;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;

@RestController
@RequestMapping("/api")
public class QuotationDeliveryController {
    private final JdbcTemplate jdbc;
    private final ClinicRepository repository;

    public QuotationDeliveryController(JdbcTemplate jdbc, ClinicRepository repository) {
        this.jdbc = jdbc;
        this.repository = repository;
    }

    public record QuotationItemDraft(
        @NotBlank @Size(max=300) String description,
        @NotBlank @Pattern(regexp="SERVICIO|REPUESTO") String type,
        @DecimalMin("0.001") BigDecimal quantity,
        @DecimalMin("0") BigDecimal unitPrice
    ) {}

    public record QuotationDraft(
        @NotBlank @Size(max=10000) String description,
        @NotEmpty List<@Valid QuotationItemDraft> items
    ) {}

    public record QuotationDecision(
        @NotBlank @Pattern(regexp="AUTORIZADA|RECHAZADA") String decision,
        @NotNull @Size(max=10000) String observations
    ) {}

    public record DeliveryDraft(
        @NotNull LocalDateTime deliveredAt,
        @NotBlank @Size(max=200) String recipientName,
        @NotNull @Size(max=50) String recipientDocument,
        @NotNull @Size(max=10000) String receptionSignature,
        @NotNull @Size(max=10000) String receptionConstancy,
        @NotNull @Size(max=10000) String observations,
        @NotNull Boolean clientConfirmed
    ) {}

    @SuppressWarnings("unchecked")
    private Map<String,Object> actor(HttpServletRequest request) {
        return (Map<String,Object>) request.getAttribute("currentUser");
    }

    private UUID actorId(HttpServletRequest request) {
        return UUID.fromString((String)actor(request).get("id"));
    }

    private void notFound(boolean exists) {
        if(!exists) throw new ApiException(HttpStatus.NOT_FOUND,"not-found","No se encontró la orden.");
    }

    @GetMapping("/quotations")
    public List<Map<String,Object>> allQuotations() {
        List<Map<String,Object>> quotations=jdbc.queryForList("""
            SELECT q.id::text AS id,q.order_id::text AS "orderId",
              'OS-' || lpad(so.number::text,6,'0') AS "orderCode",
              btrim(c.first_name || ' ' || c.last_name) AS "clientName",
              e.type AS "equipmentType",e.brand,e.model,
              q.description,q.status,q.total::text AS total,
              q.created_by::text AS "createdBy",
              q.decided_by::text AS "decidedBy",
              q.decided_at::text AS "decidedAt",
              q.decision_observations AS "decisionObservations",
              q.created_at::text AS "createdAt"
            FROM quotation q
            JOIN service_orders so ON so.id=q.order_id
            JOIN clients c ON c.id=so.client_id
            JOIN equipment e ON e.id=so.equipment_id
            ORDER BY
              CASE q.status WHEN 'PENDIENTE' THEN 0 ELSE 1 END,
              q.created_at DESC,q.id
            """);
        for(Map<String,Object> quotation:quotations) {
            UUID quotationId=UUID.fromString((String)quotation.get("id"));
            quotation.put("items",jdbc.queryForList("""
                SELECT id::text AS id,item_description AS description,
                  item_type AS type,quantity::text AS quantity,
                  unit_price::text AS "unitPrice",subtotal::text AS subtotal
                FROM quotation_item WHERE quotation_id=? ORDER BY id
                """,quotationId));
        }
        return quotations;
    }

    @GetMapping("/orders/{id}/quotations")
    public List<Map<String,Object>> quotations(@PathVariable UUID id) {
        notFound(Boolean.TRUE.equals(jdbc.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM service_orders WHERE id=?)", Boolean.class, id)));
        List<Map<String,Object>> quotations = jdbc.queryForList("""
            SELECT id::text AS id,order_id::text AS "orderId",description,status,
              total::text AS total,created_by::text AS "createdBy",
              decided_by::text AS "decidedBy",decided_at::text AS "decidedAt",
              decision_observations AS "decisionObservations",
              created_at::text AS "createdAt"
            FROM quotation WHERE order_id=? ORDER BY created_at DESC,id
            """, id);
        for(Map<String,Object> quotation : quotations) {
            UUID quotationId=UUID.fromString((String)quotation.get("id"));
            quotation.put("items", jdbc.queryForList("""
                SELECT id::text AS id, item_description AS description,
                  item_type AS type, quantity::text AS quantity,
                  unit_price::text AS "unitPrice", subtotal::text AS subtotal
                FROM quotation_item WHERE quotation_id=? ORDER BY id
                """, quotationId));
        }
        return quotations;
    }

    @PostMapping("/orders/{id}/quotations")
    @Transactional
    public Map<String,Object> createQuotation(@PathVariable UUID id,
        @Valid @RequestBody QuotationDraft draft, HttpServletRequest request) {
        notFound(Boolean.TRUE.equals(jdbc.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM service_orders WHERE id=?)", Boolean.class, id)));
        String status=jdbc.queryForObject(
            "SELECT status_code FROM service_orders WHERE id=?", String.class, id);
        if(List.of("CERRADA","CANCELADA").contains(status))
            throw new ApiException(HttpStatus.CONFLICT,"order-closed","No se puede cotizar una orden cerrada.");
        boolean hasPending=Boolean.TRUE.equals(jdbc.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM quotation WHERE order_id=? AND status='PENDIENTE')",
            Boolean.class,id));
        if(hasPending)
            throw new ApiException(HttpStatus.CONFLICT,"quotation-pending",
                "La orden ya tiene una cotización pendiente.");

        BigDecimal total=BigDecimal.ZERO;
        List<BigDecimal> subtotals=new ArrayList<>();
        for(QuotationItemDraft item:draft.items()) {
            BigDecimal subtotal=item.quantity().multiply(item.unitPrice()).setScale(2,RoundingMode.HALF_UP);
            if(subtotal.compareTo(BigDecimal.ZERO)<0)
                throw new ApiException(HttpStatus.BAD_REQUEST,"invalid-data","El subtotal no puede ser negativo.");
            subtotals.add(subtotal);
            total=total.add(subtotal);
        }

        UUID quotationId=UUID.randomUUID();
        UUID actorId=actorId(request);
        jdbc.update("""
            INSERT INTO quotation(id,order_id,description,total,created_by)
            VALUES (?,?,?,?,?)
            """,quotationId,id,draft.description().trim(),total.setScale(2,RoundingMode.HALF_UP),actorId);
        for(int i=0;i<draft.items().size();i++) {
            QuotationItemDraft item=draft.items().get(i);
            jdbc.update("""
                INSERT INTO quotation_item(id,quotation_id,item_description,item_type,quantity,unit_price,subtotal)
                VALUES (?,?,?,?,?,?,?)
                """,UUID.randomUUID(),quotationId,item.description().trim(),item.type(),
                item.quantity(),item.unitPrice().setScale(2,RoundingMode.HALF_UP),
                subtotals.get(i));
        }
        repository.audit(actorId,"CREATE_QUOTATION","quotation",quotationId,
            "SUCCESS","Cotización creada para la orden " + id);
        return quotations(id).stream().filter(q->quotationId.toString().equals(q.get("id")))
            .findFirst().orElseThrow();
    }

    @PostMapping("/quotations/{id}/decision")
    @Transactional
    public Map<String,Object> decide(@PathVariable UUID id,
        @Valid @RequestBody QuotationDecision draft, HttpServletRequest request) {
        List<Map<String,Object>> rows=jdbc.queryForList(
            "SELECT order_id::text AS \"orderId\",status FROM quotation WHERE id=?",id);
        if(rows.isEmpty())
            throw new ApiException(HttpStatus.NOT_FOUND,"not-found","No se encontró la cotización.");
        if(!"PENDIENTE".equals(rows.getFirst().get("status")))
            throw new ApiException(HttpStatus.CONFLICT,"quotation-decided",
                "La cotización ya fue autorizada o rechazada.");
        UUID actorId=actorId(request);
        jdbc.update("""
            UPDATE quotation SET status=?,decided_by=?,decided_at=now(),
              decision_observations=?,updated_at=now() WHERE id=?
            """,draft.decision(),actorId,draft.observations().trim(),id);
        UUID orderId=UUID.fromString((String)rows.getFirst().get("orderId"));
        repository.audit(actorId,"DECIDE_QUOTATION","quotation",id,"SUCCESS",
            "Cotización " + draft.decision().toLowerCase(Locale.ROOT)
                + " para la orden " + orderId);
        return quotations(orderId).stream().filter(q->id.toString().equals(q.get("id")))
            .findFirst().orElseThrow();
    }

    @GetMapping("/quotations/{id}/download/pdf")
    public ResponseEntity<ByteArrayResource> downloadQuotationPdf(@PathVariable UUID id,
        HttpServletRequest request) {
        List<Map<String,Object>> quotations=jdbc.queryForList("""
            SELECT q.id::text AS id,q.order_id::text AS "orderId",
              'OS-' || lpad(so.number::text,6,'0') AS "orderCode",
              btrim(c.first_name || ' ' || c.last_name) AS "clientName",
              c.document_type AS "documentType",c.document_number AS "documentNumber",
              c.phone AS "clientPhone",e.type AS "equipmentType",e.brand,e.model,
              e.serial_number AS "serialNumber",q.description,q.status,q.total::text AS total,
              q.decision_observations AS "decisionObservations",
              q.decided_at::text AS "decidedAt",q.created_at::text AS "createdAt"
            FROM quotation q
            JOIN service_orders so ON so.id=q.order_id
            JOIN clients c ON c.id=so.client_id
            JOIN equipment e ON e.id=so.equipment_id
            WHERE q.id=? 
            """,id);
        if(quotations.isEmpty())
            throw new ApiException(HttpStatus.NOT_FOUND,"not-found","No se encontró la cotización.");
        Map<String,Object> quotation=quotations.getFirst();
        if(!"AUTORIZADA".equals(quotation.get("status")))
            throw new ApiException(HttpStatus.CONFLICT,"quotation-not-authorized",
                "La cotización debe estar autorizada antes de descargarla.");

        List<Map<String,Object>> items=jdbc.queryForList("""
            SELECT item_type AS type,item_description AS description,
              quantity::text AS quantity,unit_price::text AS "unitPrice",
              subtotal::text AS subtotal
            FROM quotation_item WHERE quotation_id=? ORDER BY id
            """,id);

        PdfDocument pdf=new PdfDocument();
        float navyRed=0.07f, navyGreen=0.15f, navyBlue=0.31f;
        float slateRed=0.31f, slateGreen=0.38f, slateBlue=0.50f;
        pdf.fillRectangle(0,724,612,68,navyRed,navyGreen,navyBlue);
        pdf.fillRectangle(0,720,612,4,slateRed,slateGreen,slateBlue);
        pdf.fillRectangle(0,0,612,48,navyRed,navyGreen,navyBlue);
        pdf.fillRectangle(0,48,612,3,slateRed,slateGreen,slateBlue);
        pdf.fillRectangle(0,724,7,68,slateRed,slateGreen,slateBlue);
        pdf.text(42,761,17,"LA CLINICA DEL INFORMATICO",1,1,1);
        pdf.text(42,741,9,"COTIZACIÓN DE SERVICIO",0.86f,0.89f,0.94f);
        pdf.text(400,761,10,"Fecha: " + formatDate(quotation.get("createdAt")),1,1,1);
        pdf.text(400,741,9,"Orden: " + quotation.get("orderCode"),0.86f,0.89f,0.94f);

        pdf.text(52,692,11,"DATOS DEL CLIENTE",navyRed,navyGreen,navyBlue);
        pdf.line(52,684,560,684,0.7f);
        pdf.text(52,666,11,Objects.toString(quotation.get("clientName"),"Cliente"));
        String document=String.join(" ",Objects.toString(quotation.get("documentType"),""),
            Objects.toString(quotation.get("documentNumber"),"")).trim();
        pdf.text(52,650,9,"Documento: " + (document.isEmpty()?"No registrado":document));
        pdf.text(52,634,9,"Teléfono: "
            + Objects.toString(quotation.get("clientPhone"),"No registrado"));
        pdf.text(330,666,9,"EQUIPO");
        List<String> equipmentLines=wrapPdf(String.join(" ",Objects.toString(
            quotation.get("equipmentType"),""),Objects.toString(quotation.get("brand"),""),
            Objects.toString(quotation.get("model"),"")).trim(),42);
        for(int i=0;i<equipmentLines.size();i++)
            pdf.text(330,650-i*12,8,equipmentLines.get(i));
        float serialY=646-equipmentLines.size()*12;
        pdf.text(330,serialY,9,"Serie: "
            + Objects.toString(quotation.get("serialNumber"),"No registrada"));

        float detailTitleY=Math.min(604,serialY-18);
        pdf.text(52,detailTitleY,11,"DETALLE DE LA COTIZACIÓN",navyRed,navyGreen,navyBlue);
        pdf.line(52,detailTitleY-8,560,detailTitleY-8,0.7f);
        List<String> descriptionLines=wrapPdf(Objects.toString(quotation.get("description"),""),88);
        float descriptionY=detailTitleY-24;
        float tableTop=detailTitleY-36-(descriptionLines.size()-1)*12;
        for(int i=0;i<descriptionLines.size();i++)
            pdf.text(52,descriptionY-i*12,9,descriptionLines.get(i));

        float headerBottom=tableTop-22;
        pdf.fillRectangle(52,headerBottom,508,24,slateRed,slateGreen,slateBlue);
        pdf.text(64,headerBottom+8,8,"Descripción",1,1,1);
        pdf.text(345,headerBottom+8,8,"Cantidad",1,1,1);
        pdf.text(414,headerBottom+8,8,"Precio unit.",1,1,1);
        pdf.text(506,headerBottom+8,8,"Total",1,1,1);

        float rowY=headerBottom-18;
        BigDecimal subtotal=BigDecimal.ZERO;
        for(int i=0;i<items.size();i++) {
            Map<String,Object> item=items.get(i);
            String itemDescription=Objects.toString(item.get("type"),"") + ": "
                + Objects.toString(item.get("description"),"");
            List<String> itemLines=wrapPdf(itemDescription,39);
            float rowHeight=Math.max(22,itemLines.size()*10+8);
            if(i%2==1)
                pdf.fillRectangle(52,rowY-rowHeight+5,508,rowHeight,0.90f,0.92f,0.95f);
            for(int line=0;line<itemLines.size();line++)
                pdf.text(64,rowY-line*10,8,itemLines.get(line),0.34f,0.36f,0.40f);
            pdf.text(350,rowY,8,formatQuantity(item.get("quantity")),0.34f,0.36f,0.40f);
            pdf.text(414,rowY,8,formatMoney(item.get("unitPrice")),0.34f,0.36f,0.40f);
            pdf.text(500,rowY,8,formatMoney(item.get("subtotal")),0.34f,0.36f,0.40f);
            subtotal=subtotal.add(new BigDecimal(Objects.toString(item.get("subtotal"),"0")));
            rowY-=rowHeight;
        }

        pdf.line(52,rowY+4,560,rowY+4,0.7f);
        pdf.text(370,rowY-16,9,"SUBTOTAL",navyRed,navyGreen,navyBlue);
        pdf.text(493,rowY-16,9,formatMoney(subtotal),navyRed,navyGreen,navyBlue);
        pdf.fillRectangle(360,rowY-54,200,28,slateRed,slateGreen,slateBlue);
        pdf.text(372,rowY-44,10,"TOTAL",1,1,1);
        pdf.text(493,rowY-44,10,formatMoney(quotation.get("total")),1,1,1);

        pdf.text(52,153,10,"Nota",navyRed,navyGreen,navyBlue);
        String observations=Objects.toString(quotation.get("decisionObservations"),"");
        String note=observations.isBlank()
            ?"Cotización asociada a la orden " + quotation.get("orderCode") + "."
            :"Observaciones: " + observations;
        List<String> noteLines=wrapPdf(note,72);
        for(int i=0;i<Math.min(noteLines.size(),2);i++)
            pdf.text(52,137-i*12,8,noteLines.get(i),0.34f,0.36f,0.40f);
        pdf.line(365,116,560,116,0.7f);
        pdf.text(380,99,8,"APROBACIÓN REGISTRADA",navyRed,navyGreen,navyBlue);
        pdf.text(380,84,8,"Fecha: " + formatDate(quotation.get("decidedAt")));
        pdf.text(42,18,8,"LA CLINICA DEL INFORMATICO  |  COTIZACION AUTORIZADA",1,1,1);

        repository.audit(actorId(request),"DOWNLOAD_QUOTATION","quotation",id,"SUCCESS",
            "Descarga PDF de cotización autorizada");
        HttpHeaders headers=new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_PDF);
        headers.setContentDisposition(ContentDisposition.attachment()
            .filename("cotizacion-" + quotation.get("orderCode") + ".pdf")
            .build());
        return new ResponseEntity<>(new ByteArrayResource(pdf.build()),headers,HttpStatus.OK);
    }

    private static String formatDate(Object value) {
        String date=Objects.toString(value,"");
        return date.length()>=10?date.substring(0,10):"No disponible";
    }

    private static String formatMoney(Object value) {
        DecimalFormatSymbols symbols=DecimalFormatSymbols.getInstance(new Locale("es","PE"));
        BigDecimal soles=new BigDecimal(Objects.toString(value,"0"))
            .divide(BigDecimal.valueOf(1000),2,RoundingMode.HALF_UP);
        return "S/ " + new DecimalFormat("#,##0.00",symbols).format(soles);
    }

    private static String formatQuantity(Object value) {
        DecimalFormatSymbols symbols=DecimalFormatSymbols.getInstance(new Locale("es","CO"));
        return new DecimalFormat("#,##0.###",symbols)
            .format(new BigDecimal(Objects.toString(value,"0")));
    }

    private static List<String> wrapPdf(String value,int maxLength) {
        List<String> lines=new ArrayList<>();
        StringBuilder line=new StringBuilder();
        for(String word:value.trim().split("\\s+")) {
            if(word.isEmpty()) continue;
            if(line.length()>0 && line.length()+1+word.length()>maxLength) {
                lines.add(line.toString());
                line.setLength(0);
            }
            if(line.length()>0) line.append(' ');
            line.append(word);
        }
        if(line.length()>0) lines.add(line.toString());
        if(lines.isEmpty()) lines.add("");
        return lines;
    }

    @GetMapping("/orders/{id}/delivery")
    public Map<String,Object> delivery(@PathVariable UUID id) {
        List<Map<String,Object>> rows=jdbc.queryForList("""
            SELECT id::text AS id,order_id::text AS "orderId",
              delivered_at::text AS "deliveredAt",
              responsible_id::text AS "responsibleId",recipient_name AS "recipientName",
              recipient_document AS "recipientDocument",
              reception_signature AS "receptionSignature",
              reception_constancy AS "receptionConstancy",
              client_confirmed AS "clientConfirmed",observations,
              created_at::text AS "createdAt"
            FROM equipment_deliveries WHERE order_id=? 
            """,id);
        return rows.isEmpty()?Map.of():rows.getFirst();
    }

    @PostMapping("/orders/{id}/delivery")
    @Transactional
    public Map<String,Object> deliver(@PathVariable UUID id,
        @Valid @RequestBody DeliveryDraft draft, HttpServletRequest request) {
        Map<String,Object> order=jdbc.queryForMap("""
            SELECT status_code, finalized_at FROM service_orders WHERE id=?
            """,id);
        String status=(String)order.get("status_code");
        if(!"FINALIZADA".equals(status))
            throw new ApiException(HttpStatus.CONFLICT,"delivery-not-finalized",
                "La orden debe estar finalizada antes de registrar la entrega.");
        if(!draft.clientConfirmed())
            throw new ApiException(HttpStatus.BAD_REQUEST,"confirmation-required",
                "El cliente debe confirmar la recepción.");
        if(draft.receptionSignature().isBlank() && draft.receptionConstancy().isBlank())
            throw new ApiException(HttpStatus.BAD_REQUEST,"receipt-required",
                "Debes registrar una firma o una constancia de recepción.");
        if(Boolean.TRUE.equals(jdbc.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM equipment_deliveries WHERE order_id=?)",
            Boolean.class,id)))
            throw new ApiException(HttpStatus.CONFLICT,"delivery-recorded",
                "La entrega de esta orden ya fue registrada.");

        UUID deliveryId=UUID.randomUUID();
        UUID actorId=actorId(request);
        jdbc.update("""
            INSERT INTO equipment_deliveries(id,order_id,delivered_at,responsible_id,
              client_confirmed,recipient_name,recipient_document,reception_signature,
              reception_constancy,observations)
            VALUES (?,?,?,?,?,?,?,?,?,?)
            """,deliveryId,id,draft.deliveredAt(),actorId,draft.clientConfirmed(),
            draft.recipientName().trim(),draft.recipientDocument().trim(),
            draft.receptionSignature().trim(),draft.receptionConstancy().trim(),
            draft.observations().trim());
        jdbc.update("""
            UPDATE service_orders SET status_code='CERRADA',closed_at=now(),
              closure_summary=?,finalized_at=NULL,finalized_by=NULL,updated_at=now() WHERE id=?
            ""","Entrega formal registrada. Equipo recibido por " + draft.recipientName().trim(),id);
        jdbc.update("""
            INSERT INTO order_status_history(order_id,from_status,to_status,changed_by,reason)
            VALUES (?,'FINALIZADA','CERRADA',?,'Entrega formal y recepción confirmada')
            """,id,actorId);
        repository.audit(actorId,"DELIVER_EQUIPMENT","equipment_deliveries",deliveryId,
            "SUCCESS","Entrega registrada y orden cerrada definitivamente");
        return delivery(id);
    }
}
