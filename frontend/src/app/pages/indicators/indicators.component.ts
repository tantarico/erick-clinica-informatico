import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiStore } from '../../core/api.store';
import { ServiceIndicators, SprintSixService, sprintSixErrorMessage } from '../../core/sprint-six.service';

@Component({
  selector: 'app-indicators',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './indicators.component.html',
})
export class IndicatorsComponent {
  private readonly service = inject(SprintSixService);
  protected readonly store = inject(ApiStore);
  protected readonly loading = signal(false);
  protected readonly error = signal('');
  protected readonly report = signal<ServiceIndicators | null>(null);
  protected from = '';
  protected to = '';
  protected status = '';
  protected technician = '';

  constructor() {
    void this.refresh();
  }

  protected async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set('');
    try {
      this.report.set(await this.service.indicators({
        from: this.from,
        to: this.to,
        status: this.status,
        technician: this.technician,
      }));
    } catch (error) {
      this.error.set(sprintSixErrorMessage(error));
    } finally {
      this.loading.set(false);
    }
  }

  protected percent(value: number): string {
    return `${Number(value).toFixed(2)}%`;
  }

  protected averageHours(value: number | null): string {
    return value === null ? 'Sin datos' : `${Number(value).toFixed(2)} h`;
  }

  protected completionRate(attended: number, finalized: number): number {
    return attended === 0 ? 0 : Math.round((finalized / attended) * 100);
  }

  protected technicianInitials(name: string): string {
    return name.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('').toUpperCase();
  }

  protected exportReport(format: 'csv' | 'excel' | 'pdf'): void {
    this.service.exportIndicators(format, {
      from: this.from,
      to: this.to,
      status: this.status,
      technician: this.technician,
    });
  }
}
