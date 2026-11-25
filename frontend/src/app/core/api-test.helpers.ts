import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ApiStore, BootstrapData } from './api.store';

export const admin = { id: 'admin-1', firstName: 'Admin', lastName: 'Sistema', username: 'admin', role: 'ADMINISTRADOR' as const, active: true };
export function configureApi(): HttpTestingController {
  TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
  return TestBed.inject(HttpTestingController);
}
export function snapshot(overrides: Partial<BootstrapData> = {}): BootstrapData {
  return { user: admin, users: [admin], clients: [], equipment: [], technicianOrders: [], permissions: {
    ADMINISTRADOR: ['dashboard', 'users', 'clients', 'equipment'],
    'PERSONAL DE ATENCIÓN': ['dashboard', 'clients', 'equipment'], TÉCNICO: ['dashboard'],
    GERENTE: ['dashboard', 'service-indicators', 'reports-export'],
  }, ...overrides };
}
export async function initialize(http: HttpTestingController, data = snapshot()): Promise<void> {
  const task = TestBed.inject(ApiStore).initialize();
  http.expectOne('/api/bootstrap').flush(data); await task;
}
