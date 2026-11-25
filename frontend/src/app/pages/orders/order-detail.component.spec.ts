import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting, HttpTestingController } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { ApiStore } from '../../core/api.store';
import { OrderDetailComponent } from './order-detail.component';

describe('OrderDetailComponent', () => {
  let fixture: ComponentFixture<OrderDetailComponent>;
  let http: HttpTestingController;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [OrderDetailComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        {
          provide: ActivatedRoute,
          useValue: { paramMap: of(convertToParamMap({ id: 'order-1' })) },
        },
      ],
    }).compileComponents();

    http = TestBed.inject(HttpTestingController);
    const store = TestBed.inject(ApiStore);
    store.user.set({
      id: 'admin-1',
      firstName: 'Ana',
      lastName: 'Admin',
      username: 'admin',
      role: 'ADMINISTRADOR',
      active: true,
    });
    store.permissions.update((permissions) => ({
      ...permissions,
      ADMINISTRADOR: ['orders', 'attend-orders', 'ai-prediagnosis'],
    }));

    fixture = TestBed.createComponent(OrderDetailComponent);
    fixture.detectChanges();
  });

  afterEach(() => http.verify());

  it('shows saved AI prediagnoses with their review status', async () => {
    http.expectOne('/api/orders/order-1').flush({
      id: 'order-1',
      code: 'OS-1',
      orderNumber: 1,
      receivedDate: '2026-11-14',
      createdAt: '2026-11-14T12:00:00Z',
      status: 'EN_ATENCION',
      priority: 'MEDIA',
      reportedProblem: 'No enciende',
      initialObservations: '',
      clientId: 'client-1',
      clientName: 'Cliente',
      clientDocument: '87654321',
      clientPhone: '987123456',
      equipmentId: 'equipment-1',
      equipmentType: 'Laptop',
      brand: 'Marca',
      model: 'Modelo',
      serialNumber: 'serie-1',
      equipmentCharacteristics: '',
      technicianId: 'tech-1',
      technicianName: 'Técnico',
    });
    http.expectOne('/api/orders/order-1/quotations').flush([]);
    http.expectOne('/api/orders/order-1/delivery').flush({});

    await new Promise((resolve) => setTimeout(resolve, 0));
    http.expectOne('/api/orders/order-1/prediagnoses').flush([{
      id: 'prediction-1',
      status: 'GENERADO',
      model: 'gemini-test',
      originalResponse: null,
      result: {
        classification: 'Falla de encendido',
        suggestedPriority: 'MEDIA',
        possibleCauses: ['Fuente de poder'],
        recommendedTests: ['Medir voltaje'],
        recommendations: ['Revisar conexiones'],
        warnings: ['Desconectar antes de intervenir'],
      },
      errorMessage: null,
      requestedAt: '2026-11-14T12:00:00Z',
      completedAt: '2026-11-14T12:01:00Z',
      validationStatus: 'ACEPTADO',
      modifiedResult: null,
      validationObservations: null,
      validatedAt: '2026-11-14T12:02:00Z',
      validatedBy: 'Técnico',
    }]);
    await new Promise((resolve) => setTimeout(resolve, 0));
    fixture.detectChanges();

    const content = (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(content).toContain('Prediagnósticos de IA');
    expect(content).toContain('Falla de encendido');
    expect(content).toContain('Aceptado');
    expect(content).toContain('Medir voltaje');
  });
});
