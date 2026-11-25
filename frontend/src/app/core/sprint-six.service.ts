import { HttpErrorResponse, HttpParams } from '@angular/common/http';
import { inject, Injectable } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiStore } from './api.store';

export interface DashboardIndicators {
  total: number;
  pending: number;
  in_progress: number;
  finalized: number;
  byStatus: Array<{ status: string; total: number }>;
  byMonth: Array<{ month: string; total: number }>;
}

export interface ServiceIndicators {
  total: number;
  finalized: number;
  pending: number;
  in_progress: number;
  finalized_percentage: number;
  average_attention_hours: number | null;
  byTechnician: Array<{
    technicianId: string;
    technicianName: string;
    attended: number;
    finalized: number;
  }>;
  comparison: {
    periodFrom: string;
    periodTo: string;
    total: number;
    finalized: number;
    finalizedPercentage: number;
    variationPercent: number;
  };
}

export interface AuditPage {
  items: Array<{
    id: string;
    occurredAt: string;
    userId: string | null;
    userName: string;
    username: string | null;
    module: string;
    action: string;
    result: 'SUCCESS' | 'FAILED';
    description: string;
    entityId: string | null;
  }>;
  page: number;
  size: number;
  total: number;
}

export interface BackupRun {
  id: string;
  status: 'EN_PROCESO' | 'COMPLETADO' | 'ERROR';
  startedAt: string;
  finishedAt: string | null;
  fileName: string | null;
  sizeBytes: number | null;
  checksum?: string | null;
  errorMessage: string | null;
}

export interface BackupRestoreResult {
  status: 'COMPLETADO';
  restoredBackupId: string;
  safetyBackupId: string;
  message: string;
}

export interface MonitorStatus {
  status: string;
  backend: { status: string; message: string };
  database: { status: string; message: string };
  ai: { status: string; configured: boolean; verified: boolean; message: string };
  responseTimeMs: number;
  checkedAt: string;
  recentErrors: Array<{
    occurredAt: string;
    module: string;
    action: string;
    message: string;
  }>;
}

@Injectable({ providedIn: 'root' })
export class SprintSixService {
  private readonly api = inject(ApiStore);

  dashboard(): Promise<DashboardIndicators> {
    return firstValueFrom(this.api.http.get<DashboardIndicators>('/api/indicators/dashboard'));
  }

  indicators(filters: {
    from: string;
    to: string;
    status: string;
    technician: string;
  }): Promise<ServiceIndicators> {
    let params = new HttpParams();
    for (const [key, value] of Object.entries(filters)) {
      if (value) params = params.set(key, value);
    }
    return firstValueFrom(
      this.api.http.get<ServiceIndicators>('/api/indicators/services', { params }),
    );
  }

  audit(filters: {
    page: number;
    search: string;
    user: string;
    module: string;
    from: string;
    to: string;
    result: string;
  }): Promise<AuditPage> {
    let params = new HttpParams().set('page', filters.page).set('size', 25);
    for (const [key, value] of Object.entries(filters)) {
      if (key !== 'page' && value) params = params.set(key, value);
    }
    return firstValueFrom(this.api.http.get<AuditPage>('/api/admin/audit', { params }));
  }

  backupHistory(): Promise<BackupRun[]> {
    return firstValueFrom(this.api.http.get<BackupRun[]>('/api/admin/backups'));
  }

  createBackup(): Promise<BackupRun> {
    return this.api.write<BackupRun>('POST', '/admin/backups');
  }

  restoreBackup(id: string): Promise<BackupRestoreResult> {
    return this.api.write<BackupRestoreResult>('POST', `/admin/backups/${id}/restore`);
  }

  monitoring(): Promise<MonitorStatus> {
    return firstValueFrom(this.api.http.get<MonitorStatus>('/api/admin/monitoring'));
  }

  exportIndicators(format: 'csv' | 'excel' | 'pdf', filters: {
    from: string;
    to: string;
    status: string;
    technician: string;
  }): void {
    let params = new HttpParams();
    for (const [key, value] of Object.entries(filters)) {
      if (value) params = params.set(key, value);
    }
    const query = params.toString();
    const link = document.createElement('a');
    link.href = `/api/reports/service-indicators/${format}${query ? `?${query}` : ''}`;
    link.download = '';
    link.click();
  }
}

export function sprintSixErrorMessage(error: unknown): string {
  if (error instanceof HttpErrorResponse) {
    const body = error.error;
    if (typeof body === 'object' && body !== null && 'message' in body
      && typeof body.message === 'string') {
      return body.message;
    }
    if (error.status === 0) {
      return 'No se pudo contactar al backend. Verifica que siga ejecutándose en localhost:8080 y que Angular use el proxy /api.';
    }
    if (error.status === 401) {
      return 'La sesión ya no es válida. Cierra sesión e inicia sesión nuevamente.';
    }
    if (error.status === 403) {
      return 'El usuario no tiene permiso para consultar este módulo.';
    }
    if (error.status === 404) {
      return 'El backend no encontró este endpoint. Reinícialo con el código actualizado.';
    }
    if (error.status >= 500) {
      return `El backend respondió con error HTTP ${error.status}. Revisa la consola donde ejecutas Start-Backend.ps1 para ver el detalle.`;
    }
    return `La solicitud al backend falló (HTTP ${error.status}).`;
  }
  if (typeof error === 'object' && error !== null && 'error' in error) {
    const body = error.error;
    if (typeof body === 'object' && body !== null && 'message' in body
      && typeof body.message === 'string') {
      return body.message;
    }
  }
  return 'No se pudo completar la solicitud. Comprueba la conexión con el servidor.';
}
