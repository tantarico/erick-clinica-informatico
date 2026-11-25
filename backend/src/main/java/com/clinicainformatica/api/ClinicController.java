package com.clinicainformatica.api;

import java.util.*;
import java.time.LocalDate;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class ClinicController {
    private final ClinicRepository repo;
    private final BCryptPasswordEncoder passwords = new BCryptPasswordEncoder(12);
    // Used on unknown usernames too, to avoid skipping the expensive password check.
    private final String dummyHash = passwords.encode(UUID.randomUUID().toString());
    public ClinicController(ClinicRepository repo) { this.repo=repo; }
    public record Login(@NotBlank @Size(max=80) String username,@NotBlank @Size(max=72) String password) {}
    public record ClientDraft(@NotBlank @Pattern(regexp="DNI|RUC|CE|Otro") String documentType,
        @NotBlank @Size(max=25) String documentNumber,@NotBlank @Size(max=150) String firstName,
        @NotNull @Size(max=100) String lastName,@NotBlank @Pattern(regexp="[0-9]{9}") String phone,
        @NotBlank @Email @Size(max=254) String email,@NotNull @Size(max=300) String address,@NotNull @Size(max=10000) String observations) {}
    public record EquipmentDraft(@NotNull UUID clientId,@NotBlank @Pattern(regexp="Laptop|PC|Impresora|Monitor|Tablet|Otro") String type,
        @NotBlank @Size(max=100) String brand,@NotBlank @Size(max=100) String model,@NotNull @Size(max=100) String serialNumber,
        @NotNull @Size(max=10000) String characteristics,@NotNull @Size(max=10000) String accessories,@NotNull @Size(max=10000) String observations) {}
    public record UserDraft(@NotBlank @Size(max=100) String firstName,@NotBlank @Size(max=100) String lastName,
        @NotBlank @Size(max=80) String username,@NotNull @Size(max=72) String password,
        @NotBlank @Pattern(regexp="ADMINISTRADOR|PERSONAL DE ATENCIÓN|TÉCNICO|GERENTE") String role,@NotNull Boolean active) {}
    public record Active(@NotNull Boolean active) {}
    public record PermissionChange(@NotBlank String role,@NotBlank String permission,@NotNull Boolean allowed) {}
    public record ServiceOrderDraft(@NotNull UUID clientId,@NotNull UUID equipmentId,
        @NotNull LocalDate receivedDate,@NotBlank @Size(max=10000) String reportedProblem,
        @NotNull @Size(max=10000) String initialObservations,
        @NotBlank @Pattern(regexp="BAJA|MEDIA|ALTA|URGENTE") String priority) {}
    public record TechnicianAssignment(@NotNull UUID technicianId,@NotNull @Size(max=10000) String notes) {}
    public record OrderStatusChange(@NotBlank @Pattern(regexp="PENDIENTE|EN_ATENCION|FINALIZADA") String status,
        @NotNull @Size(max=10000) String reason) {}
    @SuppressWarnings("unchecked")
    private Map<String,Object> actor(HttpServletRequest request) {return (Map<String,Object>) request.getAttribute("currentUser");}
    private UUID actorId(HttpServletRequest request) {return UUID.fromString((String)actor(request).get("id"));}
    private void found(int count) {if(count == 0) throw new ApiException(HttpStatus.NOT_FOUND,"not-found","No se encontró el registro.");}
    private String hash(String password) {
        if(password.length() < 10 || password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 72)
            throw new ApiException(HttpStatus.BAD_REQUEST,"invalid-data","La contraseña debe tener al menos 10 caracteres y como máximo 72 bytes.");
        return passwords.encode(password);
    }
    private void validateClientDocument(ClientDraft d) {
        String number=d.documentNumber().trim();
        boolean valid=switch(d.documentType()) {
            case "DNI" -> number.matches("[0-9]{8}");
            case "RUC" -> number.matches("[0-9]{11}");
            case "CE" -> number.matches("[a-zA-Z0-9-]{5,20}");
            case "Otro" -> number.length() >= 1 && number.length() <= 25;
            default -> false;
        };
        if(!valid) throw new ApiException(HttpStatus.BAD_REQUEST,"invalid-data","El número de documento no corresponde al tipo seleccionado.");
    }
    @PostMapping("/auth/login")
    public Map<String,Object> login(@Valid @RequestBody Login draft,HttpServletRequest request) {
        var rows=repo.jdbc().queryForList("SELECT id,password_hash,active,role_code FROM users WHERE lower(username)=lower(?)",draft.username().trim());
        var row=rows.isEmpty()?null:rows.getFirst();
        boolean valid=passwords.matches(draft.password(),row == null?dummyHash:(String)row.get("password_hash"));
        if(row == null || !valid) {
            repo.audit(null,"LOGIN_FAILED","users",null,"FAILED","Intento de inicio de sesión fallido");
            throw new ApiException(HttpStatus.UNAUTHORIZED,"invalid-credentials","El usuario o la contraseña son incorrectos.");
        }
        if(!Boolean.TRUE.equals(row.get("active"))) {
            repo.audit((UUID)row.get("id"),"LOGIN_FAILED","users",(UUID)row.get("id"),
                "FAILED","Intento de inicio de sesión de una cuenta desactivada");
            throw new ApiException(HttpStatus.FORBIDDEN,"inactive-user","Este usuario está desactivado.");
        }
        var old=request.getSession(false); if(old != null) old.invalidate();
        UUID id=(UUID)row.get("id");
        var session=request.getSession(true);
        session.setAttribute("userId",id);
        session.setAttribute("userRole",row.get("role_code"));
        repo.audit(id,"LOGIN","users",id);
        return repo.user(id);
    }
    @PostMapping("/auth/logout")
    public void logout(HttpServletRequest request) {
        var session=request.getSession(false);
        if(session != null) {
            UUID id=(UUID)session.getAttribute("userId");
            repo.audit(id,"LOGOUT","users",id,"SUCCESS","Cierre de sesión");
            session.invalidate();
        }
    }
    @GetMapping("/bootstrap")
    public Map<String,Object> bootstrap(HttpServletRequest request) {
        var user=actor(request); String role=(String)user.get("role");
        var technicianOrders=repo.can(role,"assigned-orders")
            ? repo.technicianOrders(UUID.fromString((String)user.get("id"))) : List.of();
        return Map.of("user",user,"permissions",repo.permissions(),
            "users",repo.can(role,"users")?repo.users():List.of(),
            "clients",repo.can(role,"clients") || repo.can(role,"equipment")?repo.clients():List.of(),
            "equipment",repo.can(role,"equipment")?repo.equipment():List.of(),
            "technicianOrders",technicianOrders);
    }
    @GetMapping("/clients") public List<Map<String,Object>> clients() {return repo.clients();}
    @PostMapping("/clients") @Transactional
    public Map<String,Object> createClient(@Valid @RequestBody ClientDraft d,HttpServletRequest request) {
        validateClientDocument(d);
        UUID id=UUID.randomUUID();
        repo.jdbc().update("INSERT INTO clients(id,document_type,document_number,first_name,last_name,phone,email,address,observations) VALUES (?,?,?,?,?,?,?,?,?)",
            id,d.documentType(),d.documentNumber().trim(),d.firstName().trim(),d.lastName().trim(),d.phone().trim(),d.email().trim(),d.address().trim(),d.observations().trim());
        repo.audit(actorId(request),"CREATE","clients",id);
        return repo.jdbc().queryForObject("SELECT * FROM clients WHERE id=?",repo::clientRow,id);
    }
    @PutMapping("/clients/{id}") @Transactional
    public Map<String,Object> updateClient(@PathVariable UUID id,@Valid @RequestBody ClientDraft d,HttpServletRequest request) {
        validateClientDocument(d);
        found(repo.jdbc().update("UPDATE clients SET document_type=?,document_number=?,first_name=?,last_name=?,phone=?,email=?,address=?,observations=? WHERE id=?",
            d.documentType(),d.documentNumber().trim(),d.firstName().trim(),d.lastName().trim(),d.phone().trim(),d.email().trim(),d.address().trim(),d.observations().trim(),id));
        repo.audit(actorId(request),"UPDATE","clients",id);
        return repo.jdbc().queryForObject("SELECT * FROM clients WHERE id=?",repo::clientRow,id);
    }
    @GetMapping("/clients/{id}")
    public Map<String,Object> clientDetail(@PathVariable UUID id) {
        Map<String,Object> detail=new LinkedHashMap<>();
        var rows=repo.jdbc().query("SELECT * FROM clients WHERE id=?",repo::clientRow,id);
        if(rows.isEmpty()) found(0);
        detail.put("client",rows.getFirst());
        detail.put("equipment",repo.jdbc().queryForList("""
            SELECT e.id::text AS id,e.client_id::text AS "clientId",e.type,e.brand,e.model,e.serial_number AS "serialNumber",
              e.characteristics,e.accessories,e.observations,e.created_at::text AS "createdAt"
            FROM equipment e WHERE e.client_id=?
            ORDER BY e.created_at DESC,e.id
            """,id));
        detail.put("orders",repo.jdbc().queryForList("""
            SELECT so.id::text AS id,'OS-' || lpad(so.number::text,6,'0') AS code,
              so.received_at::text AS "receivedDate",so.status_code AS status,
              so.reported_problem AS "reportedProblem",e.id::text AS "equipmentId",
              e.type AS "equipmentType",e.brand,e.model
            FROM service_orders so JOIN equipment e ON e.id=so.equipment_id
            WHERE so.client_id=?
            ORDER BY so.received_at DESC,so.number DESC
            """,id));
        return detail;
    }
    @DeleteMapping("/clients/{id}") @Transactional
    public void deleteClient(@PathVariable UUID id,HttpServletRequest request) {
        boolean hasEquipment=Boolean.TRUE.equals(repo.jdbc().queryForObject(
            "SELECT EXISTS(SELECT 1 FROM equipment WHERE client_id=?)",Boolean.class,id));
        boolean hasOrders=Boolean.TRUE.equals(repo.jdbc().queryForObject(
            "SELECT EXISTS(SELECT 1 FROM service_orders WHERE client_id=?)",Boolean.class,id));
        if(hasEquipment || hasOrders)
            throw new ApiException(HttpStatus.CONFLICT,"related-records",
                "No se puede eliminar un cliente con equipos u órdenes; su historial debe conservarse.");
        found(repo.jdbc().update("DELETE FROM clients WHERE id=?",id)); repo.audit(actorId(request),"DELETE","clients",id);
    }
    @GetMapping("/equipment") public List<Map<String,Object>> equipment() {return repo.equipment();}
    private void checkEquipment(EquipmentDraft d) {
        if(!Boolean.TRUE.equals(repo.jdbc().queryForObject("SELECT EXISTS(SELECT 1 FROM clients WHERE id=?)",Boolean.class,d.clientId())))
            throw new ApiException(HttpStatus.BAD_REQUEST,"client-not-found","Selecciona un cliente registrado.");
    }
    @PostMapping("/equipment") @Transactional
    public Map<String,Object> createEquipment(@Valid @RequestBody EquipmentDraft d,HttpServletRequest request) {
        checkEquipment(d); UUID id=UUID.randomUUID();
        repo.jdbc().update("INSERT INTO equipment(id,client_id,type,brand,model,serial_number,characteristics,accessories,observations) VALUES (?,?,?,?,?,?,?,?,?)",
            id,d.clientId(),d.type(),d.brand().trim(),d.model().trim(),d.serialNumber().trim(),d.characteristics().trim(),d.accessories().trim(),d.observations().trim());
        repo.audit(actorId(request),"CREATE","equipment",id);
        return repo.jdbc().queryForObject("SELECT * FROM equipment WHERE id=?",repo::equipmentRow,id);
    }
    @PutMapping("/equipment/{id}") @Transactional
    public Map<String,Object> updateEquipment(@PathVariable UUID id,@Valid @RequestBody EquipmentDraft d,HttpServletRequest request) {
        checkEquipment(d);
        found(repo.jdbc().update("UPDATE equipment SET client_id=?,type=?,brand=?,model=?,serial_number=?,characteristics=?,accessories=?,observations=? WHERE id=?",
            d.clientId(),d.type(),d.brand().trim(),d.model().trim(),d.serialNumber().trim(),d.characteristics().trim(),d.accessories().trim(),d.observations().trim(),id));
        repo.audit(actorId(request),"UPDATE","equipment",id);
        return repo.jdbc().queryForObject("SELECT * FROM equipment WHERE id=?",repo::equipmentRow,id);
    }
    @DeleteMapping("/equipment/{id}") @Transactional
    public void deleteEquipment(@PathVariable UUID id,HttpServletRequest request) {
        found(repo.jdbc().update("DELETE FROM equipment WHERE id=?",id));repo.audit(actorId(request),"DELETE","equipment",id);
    }
    private void checkOrderReferences(ServiceOrderDraft d) {
        if(!Boolean.TRUE.equals(repo.jdbc().queryForObject(
            "SELECT EXISTS(SELECT 1 FROM equipment WHERE id=? AND client_id=?)",Boolean.class,d.equipmentId(),d.clientId())))
            throw new ApiException(HttpStatus.BAD_REQUEST,"equipment-client-mismatch","Selecciona un equipo asociado al cliente.");
        if(d.receivedDate().isAfter(LocalDate.now()))
            throw new ApiException(HttpStatus.BAD_REQUEST,"invalid-data","La fecha de ingreso no puede ser futura.");
    }
    private String databasePriority(String priority) {return "MEDIA".equals(priority) ? "NORMAL" : priority;}
    @GetMapping("/orders")
    public List<Map<String,Object>> orders(@RequestParam(defaultValue="") String q,
        @RequestParam(defaultValue="") String status,HttpServletRequest request) {
        String role=(String)actor(request).get("role");
        UUID assignedTechnician="TÉCNICO".equals(role) || !repo.can(role,"orders") ? actorId(request) : null;
        return repo.serviceOrders(q,status,assignedTechnician);
    }
    @GetMapping("/orders/mine")
    public List<Map<String,Object>> myOrders(HttpServletRequest request) {
        return repo.serviceOrders("","",actorId(request));
    }
    @GetMapping("/orders/technicians")
    public List<Map<String,Object>> technicians() {return repo.activeTechnicians();}
    @GetMapping("/orders/{id}")
    public Map<String,Object> order(@PathVariable UUID id,HttpServletRequest request) {
        String role=(String)actor(request).get("role");
        UUID assignedTechnician = "TÉCNICO".equals(role) || !repo.can(role,"orders") ? actorId(request) : null;
        Map<String,Object> order = repo.serviceOrder(id,assignedTechnician);
        if(order == null) found(0);
        return order;
    }
    @PostMapping("/orders") @Transactional
    public Map<String,Object> createOrder(@Valid @RequestBody ServiceOrderDraft d,HttpServletRequest request) {
        checkOrderReferences(d);
        UUID id=UUID.randomUUID();
        repo.jdbc().update("""
            INSERT INTO service_orders(id,equipment_id,client_id,received_by,reported_problem,
              intake_condition,status_code,priority,received_at)
            VALUES (?,?,?,?,?,?,'PENDIENTE',?,?)
            """,id,d.equipmentId(),d.clientId(),actorId(request),d.reportedProblem().trim(),
            d.initialObservations().trim(),databasePriority(d.priority()),d.receivedDate());
        UUID responsible=actorId(request);
        repo.jdbc().update("""
            INSERT INTO order_status_history(order_id,from_status,to_status,changed_by,reason)
            VALUES (?,NULL,'PENDIENTE',?,'Registro de orden')
            """,id,responsible);
        repo.audit(responsible,"CREATE","service_orders",id);
        return repo.serviceOrder(id,null);
    }
    @PutMapping("/orders/{id}") @Transactional
    public Map<String,Object> updateOrder(@PathVariable UUID id,@Valid @RequestBody ServiceOrderDraft d,
        HttpServletRequest request) {
        checkOrderReferences(d);
        found(repo.jdbc().update("""
            UPDATE service_orders SET client_id=?,equipment_id=?,reported_problem=?,
              intake_condition=?,priority=?,received_at=? WHERE id=?
            """,d.clientId(),d.equipmentId(),d.reportedProblem().trim(),d.initialObservations().trim(),
            databasePriority(d.priority()),d.receivedDate(),id));
        repo.audit(actorId(request),"UPDATE","service_orders",id);
        return repo.serviceOrder(id,null);
    }
    @PostMapping("/orders/{id}/assignment") @Transactional
    public Map<String,Object> assignTechnician(@PathVariable UUID id,@Valid @RequestBody TechnicianAssignment d,
        HttpServletRequest request) {
        var order=repo.jdbc().queryForList("SELECT status_code FROM service_orders WHERE id=? FOR UPDATE",id);
        if(order.isEmpty()) found(0);
        String status=(String)order.getFirst().get("status_code");
        if(List.of("FINALIZADA","CERRADA","CANCELADA").contains(status))
            throw new ApiException(HttpStatus.CONFLICT,"order-closed","No se puede asignar una orden finalizada.");
        boolean activeTechnician=Boolean.TRUE.equals(repo.jdbc().queryForObject(
            "SELECT EXISTS(SELECT 1 FROM users WHERE id=? AND active AND role_code='TÉCNICO')",Boolean.class,d.technicianId()));
        if(!activeTechnician)
            throw new ApiException(HttpStatus.BAD_REQUEST,"invalid-technician","Selecciona un técnico activo registrado.");
        UUID responsible=actorId(request);
        repo.jdbc().update("UPDATE technician_assignments SET ended_at=now() WHERE order_id=? AND ended_at IS NULL",id);
        repo.jdbc().update("""
            INSERT INTO technician_assignments(order_id,technician_id,assigned_by,notes)
            VALUES (?,?,?,?)
            """,id,d.technicianId(),responsible,d.notes().trim());
        repo.audit(responsible,"ASSIGN_TECHNICIAN","service_orders",id);
        return repo.serviceOrder(id,null);
    }
    @PatchMapping("/orders/{id}/status") @Transactional
    public Map<String,Object> changeOrderStatus(@PathVariable UUID id,@Valid @RequestBody OrderStatusChange d,
        HttpServletRequest request) {
        UUID responsible=actorId(request);
        String role=(String)actor(request).get("role");
        var rows=repo.jdbc().queryForList("SELECT status_code FROM service_orders WHERE id=? FOR UPDATE",id);
        if(rows.isEmpty()) found(0);
        String previous=(String)rows.getFirst().get("status_code");
        if("FINALIZADA".equals(previous))
            throw new ApiException(HttpStatus.CONFLICT,"order-finalized",
                "Una orden finalizada solo puede consultarse.");
        if(previous.equals(d.status()))
            throw new ApiException(HttpStatus.CONFLICT,"status-unchanged","La orden ya tiene ese estado.");
        if("FINALIZADA".equals(d.status()))
            throw new ApiException(HttpStatus.CONFLICT,"finalization-required",
                "Finaliza la orden desde el módulo de atención técnica.");
        if("EN_ATENCION".equals(d.status())) {
            boolean assigned=Boolean.TRUE.equals(repo.jdbc().queryForObject("""
                SELECT EXISTS(SELECT 1 FROM technician_assignments
                WHERE order_id=? AND ended_at IS NULL)
                """,Boolean.class,id));
            if(!assigned)
                throw new ApiException(HttpStatus.CONFLICT,"technician-required","Asigna un técnico antes de iniciar la atención.");
            if("TÉCNICO".equals(role) && !Boolean.TRUE.equals(repo.jdbc().queryForObject("""
                SELECT EXISTS(SELECT 1 FROM technician_assignments
                WHERE order_id=? AND technician_id=? AND ended_at IS NULL)
                """,Boolean.class,id,responsible)))
                throw new ApiException(HttpStatus.NOT_FOUND,"not-found","No se encontró la orden asignada.");
        }
        if("FINALIZADA".equals(d.status())) {
            boolean recorded=Boolean.TRUE.equals(repo.jdbc().queryForObject("""
                SELECT EXISTS(SELECT 1 FROM technical_attentions
                WHERE order_id=? AND finished_at IS NOT NULL
                  AND btrim(diagnosis)<>'' AND btrim(actions_performed)<>'')
                """,Boolean.class,id));
            if(!recorded)
                throw new ApiException(HttpStatus.CONFLICT,"diagnostic-required",
                    "La orden requiere diagnóstico y resultado técnico antes de finalizar.");
        }
        boolean allowed=Boolean.TRUE.equals(repo.jdbc().queryForObject(
            "SELECT EXISTS(SELECT 1 FROM order_status_transitions WHERE from_status=? AND to_status=?)",
            Boolean.class,previous,d.status()));
        if(!allowed)
            throw new ApiException(HttpStatus.CONFLICT,"invalid-transition","El cambio de estado solicitado no está permitido.");
        repo.jdbc().update("UPDATE service_orders SET status_code=? WHERE id=?",d.status(),id);
        repo.jdbc().update("""
            INSERT INTO order_status_history(order_id,from_status,to_status,changed_by,reason)
            VALUES (?,?,?,?,?)
            """,id,previous,d.status(),responsible,d.reason().trim());
        repo.audit(responsible,"CHANGE_STATUS","service_orders",id);
        return repo.serviceOrder(id,"TÉCNICO".equals(role) ? responsible : null);
    }
    @GetMapping("/users") public List<Map<String,Object>> users() {return repo.users();}
    @PostMapping("/users") @Transactional
    public Map<String,Object> createUser(@Valid @RequestBody UserDraft d,HttpServletRequest request) {
        UUID id=UUID.randomUUID();
        repo.jdbc().update("INSERT INTO users(id,first_name,last_name,username,password_hash,role_code,active) VALUES (?,?,?,?,?,?,?)",
            id,d.firstName().trim(),d.lastName().trim(),d.username().trim(),hash(d.password()),d.role(),d.active());
        repo.audit(actorId(request),"CREATE","users",id);return repo.user(id);
    }
    private void protectAdmin(UUID id,String nextRole,boolean active,HttpServletRequest request) {
        // Serialize changes to administrators so concurrent requests cannot remove the last one.
        repo.jdbc().execute("LOCK TABLE users IN EXCLUSIVE MODE");
        var user=repo.user(id);if(user == null) found(0);
        if(id.equals(actorId(request)) && (!active || !nextRole.equals(user.get("role"))))
            throw new ApiException(HttpStatus.CONFLICT,"self-change","No puedes desactivar tu usuario ni cambiar tu propio rol.");
        if("ADMINISTRADOR".equals(user.get("role")) && Boolean.TRUE.equals(user.get("active")) && (!active || !nextRole.equals("ADMINISTRADOR"))
            && repo.jdbc().queryForObject("SELECT count(*) FROM users WHERE role_code='ADMINISTRADOR' AND active",Long.class) <= 1)
            throw new ApiException(HttpStatus.CONFLICT,"last-admin","Debe existir al menos un administrador activo.");
    }
    @PutMapping("/users/{id}") @Transactional
    public Map<String,Object> updateUser(@PathVariable UUID id,@Valid @RequestBody UserDraft d,HttpServletRequest request) {
        protectAdmin(id,d.role(),d.active(),request);
        String password=d.password().isEmpty()?repo.jdbc().queryForObject("SELECT password_hash FROM users WHERE id=?",String.class,id):hash(d.password());
        found(repo.jdbc().update("UPDATE users SET first_name=?,last_name=?,username=?,password_hash=?,role_code=?,active=? WHERE id=?",
            d.firstName().trim(),d.lastName().trim(),d.username().trim(),password,d.role(),d.active(),id));
        repo.audit(actorId(request),"UPDATE","users",id);return repo.user(id);
    }
    @PatchMapping("/users/{id}/active") @Transactional
    public Map<String,Object> active(@PathVariable UUID id,@Valid @RequestBody Active d,HttpServletRequest request) {
        var user=repo.user(id);if(user == null) found(0);
        protectAdmin(id,(String)user.get("role"),d.active(),request);
        repo.jdbc().update("UPDATE users SET active=? WHERE id=?",d.active(),id);
        repo.audit(actorId(request),"ACTIVE_CHANGE","users",id);return repo.user(id);
    }
    @GetMapping("/permissions") public Map<String,List<String>> permissions() {return repo.permissions();}
    @PutMapping("/permissions") @Transactional
    public Map<String,List<String>> permissions(@Valid @RequestBody PermissionChange d,HttpServletRequest request) {
        if(!List.of("PERSONAL DE ATENCIÓN","TÉCNICO","GERENTE").contains(d.role()) || d.permission().equals("dashboard") || d.permission().equals("users") || d.permission().equals("settings"))
            throw new ApiException(HttpStatus.BAD_REQUEST,"protected-permission","Este permiso está reservado o es obligatorio.");
        if(!"ADMINISTRADOR".equals(actor(request).get("role")))
            throw new ApiException(HttpStatus.FORBIDDEN,"forbidden","Solo un administrador puede cambiar permisos.");
        if(!Boolean.TRUE.equals(repo.jdbc().queryForObject("SELECT EXISTS(SELECT 1 FROM permissions WHERE code=?)",Boolean.class,d.permission())))
            throw new ApiException(HttpStatus.BAD_REQUEST,"invalid-data","Permiso no válido.");
        if(d.allowed()) repo.jdbc().update("INSERT INTO role_permissions VALUES (?,?) ON CONFLICT DO NOTHING",d.role(),d.permission());
        else repo.jdbc().update("DELETE FROM role_permissions WHERE role_code=? AND permission_code=?",d.role(),d.permission());
        repo.audit(actorId(request),"PERMISSIONS_CHANGE","roles",null);
        return repo.permissions();
    }
}
