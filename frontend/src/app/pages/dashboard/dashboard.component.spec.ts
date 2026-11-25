import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ApiStore } from '../../core/api.store';
import { DashboardComponent } from './dashboard.component';
import { admin } from '../../core/api-test.helpers';

describe('DashboardComponent', () => {
  let fixture: ComponentFixture<DashboardComponent>;
  let store: ApiStore;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [DashboardComponent],
      providers: [provideRouter([]), provideHttpClient()],
    });
    store = TestBed.inject(ApiStore);
    fixture = TestBed.createComponent(DashboardComponent);
  });

  it('shows database-backed totals and updates them when records change', () => {
    store.user.set(admin);
    store.permissions.set({
      ADMINISTRADOR: ['dashboard', 'users', 'clients', 'equipment'],
      'PERSONAL DE ATENCIÓN': [],
      TÉCNICO: [],
      GERENTE: ['dashboard'],
    });
    store.users.set([admin, { ...admin, id: 'user-2', active: false }]);
    store.clients.set([
      { id: 'client-1', documentType: 'DNI', documentNumber: '1', firstName: 'Ana', lastName: '', phone: '', email: '', address: '', observations: '' },
      { id: 'client-2', documentType: 'DNI', documentNumber: '2', firstName: 'Eva', lastName: '', phone: '', email: '', address: '', observations: '' },
    ]);
    store.equipment.set([
      { id: 'equipment-1', clientId: 'client-1', type: 'Laptop', brand: 'A', model: '1', serialNumber: '1', characteristics: '', accessories: '', observations: '' },
      { id: 'equipment-2', clientId: 'client-1', type: 'PC', brand: 'B', model: '2', serialNumber: '2', characteristics: '', accessories: '', observations: '' },
    ]);
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Clientes registrados');
    expect(fixture.nativeElement.textContent).toContain('Equipos registrados');
    expect(fixture.nativeElement.textContent).toContain('Usuarios activos');
    expect(fixture.nativeElement.textContent).toContain('Clientes con equipos');
    expect(fixture.nativeElement.querySelectorAll('.stat-value')[0].textContent.trim()).toBe('2');
    expect(fixture.nativeElement.querySelectorAll('.stat-value')[1].textContent.trim()).toBe('2');
    expect(fixture.nativeElement.querySelectorAll('.stat-value')[2].textContent.trim()).toBe('1');
    expect(fixture.nativeElement.querySelectorAll('.stat-value')[3].textContent.trim()).toBe('1');

    store.clients.update((clients) => [...clients, {
      id: 'client-3', documentType: 'DNI', documentNumber: '3', firstName: 'Luz', lastName: '', phone: '', email: '', address: '', observations: '',
    }]);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelectorAll('.stat-value')[0].textContent.trim()).toBe('3');
  });

  it('does not present unavailable totals as zero to users without permissions', () => {
    store.user.set({ ...admin, role: 'TÉCNICO' });
    store.permissions.set({
      ADMINISTRADOR: [],
      'PERSONAL DE ATENCIÓN': [],
      TÉCNICO: ['dashboard'],
      GERENTE: [],
    });
    fixture.detectChanges();

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelectorAll('.stat-value').length).toBe(0);
    expect(root.textContent).toContain('No tienes equipos asignados');
  });

  it('shows assigned technician equipment grouped by attention level', () => {
    store.user.set({ ...admin, role: 'TÉCNICO' });
    store.permissions.set({
      ADMINISTRADOR: [],
      'PERSONAL DE ATENCIÓN': [],
      TÉCNICO: ['dashboard', 'assigned-orders'],
      GERENTE: [],
    });
    store.technicianOrders.set([
      {
        id: 'order-1',
        orderNumber: 1,
        priority: 'URGENTE',
        status: 'ASIGNADA',
        reportedProblem: 'No enciende',
        equipmentType: 'Laptop',
        brand: 'Lenovo',
        model: 'E14',
        serialNumber: 'SN-1',
        clientName: 'Elena Vega',
      },
      {
        id: 'order-2',
        orderNumber: 2,
        priority: 'ALTA',
        status: 'EN_ATENCION',
        reportedProblem: 'Falla de pantalla',
        equipmentType: 'PC',
        brand: 'Dell',
        model: 'OptiPlex',
        serialNumber: 'SN-2',
        clientName: 'Ana Ruiz',
      },
      {
        id: 'order-3',
        orderNumber: 3,
        priority: 'NORMAL',
        status: 'ASIGNADA',
        reportedProblem: 'Revisión general',
        equipmentType: 'Laptop',
        brand: 'HP',
        model: 'ProBook',
        serialNumber: 'SN-3',
        clientName: 'Luis Soto',
      },
      {
        id: 'order-4',
        orderNumber: 4,
        priority: 'BAJA',
        status: 'ASIGNADA',
        reportedProblem: 'Limpieza',
        equipmentType: 'PC',
        brand: 'Acer',
        model: 'Veriton',
        serialNumber: 'SN-4',
        clientName: 'Mia León',
      },
    ]);
    fixture.detectChanges();

    const root = fixture.nativeElement as HTMLElement;
    expect(root.textContent).toContain('Panel de trabajo técnico');
    expect(root.textContent).toContain('Niveles de atención');
    expect(root.textContent).toContain('Atención inmediata');
    expect(root.textContent).toContain('Atender primero');
    expect(root.querySelector('.priority-stats-grid')?.textContent).toContain('2');
    expect(root.textContent).toContain('Atención regular');
    expect(root.textContent).toContain('Atención programada');
    expect(root.textContent).toContain('Orden #1');
    expect(root.textContent).toContain('Orden #4');
  });
});
