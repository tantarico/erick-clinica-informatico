import { DatePipe, DecimalPipe } from '@angular/common';
import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Quotation, QuotationDraft } from '../../core/service-order.models';
import { ServiceOrderService } from '../../core/service-order.service';
import { IconComponent } from '../../shared/icon/icon.component';

@Component({
  selector: 'app-quotations',
  standalone: true,
  imports: [DatePipe, DecimalPipe, FormsModule, IconComponent, RouterLink],
  templateUrl: './quotations.component.html',
})
export class QuotationsComponent implements OnInit {
  private readonly service = inject(ServiceOrderService);
  protected readonly quotations = signal<Quotation[]>([]);
  protected readonly loading = signal(false);
  protected readonly feedback = signal('');
  protected readonly error = signal('');
  protected readonly orders = signal<Array<{
    id: string;
    code: string;
    clientName: string;
    equipmentType: string;
    brand: string;
    model: string;
    status: string;
  }>>([]);

  protected search = '';
  protected status = '';
  protected selectedOrderId = '';
  protected builderOpen = false;
  protected decisionObservations = '';
  protected description = '';
  protected itemDescription = '';
  protected itemType: 'SERVICIO' | 'REPUESTO' = 'SERVICIO';
  protected quantity = 1;
  protected unitPrice = 0;

  protected readonly filtered = computed(() => {
    const query = this.search.trim().toLocaleLowerCase();
    return this.quotations().filter((quotation) => {
      const matchesSearch = !query || [
        quotation.orderCode,
        quotation.clientName,
        quotation.description,
        quotation.equipmentType,
        quotation.brand,
        quotation.model,
      ].some(value => value?.toLocaleLowerCase().includes(query));
      return matchesSearch && (!this.status || quotation.status === this.status);
    });
  });

  ngOnInit(): void {
    void this.refresh();
  }

  protected async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set('');
    try {
      await this.service.load();
      this.orders.set(this.service.orders().map(order => ({
        id: order.id,
        code: order.code,
        clientName: order.clientName,
        equipmentType: order.equipmentType,
        brand: order.brand,
        model: order.model,
        status: order.status,
      })));
      this.quotations.set(await this.service.allQuotations());
    } catch {
      this.error.set('No se pudieron cargar las cotizaciones.');
    } finally {
      this.loading.set(false);
    }
  }

  protected openBuilder(orderId = ''): void {
    this.selectedOrderId = orderId;
    this.description = '';
    this.itemDescription = '';
    this.itemType = 'SERVICIO';
    this.quantity = 1;
    this.unitPrice = 0;
    this.builderOpen = true;
  }

  protected closeBuilder(): void {
    this.builderOpen = false;
  }

  protected subtotalPreview(): number {
    return this.quantity * this.unitPrice;
  }

  protected async create(): Promise<void> {
    if (!this.selectedOrderId || !this.description.trim()
      || !this.itemDescription.trim() || this.quantity <= 0 || this.unitPrice < 0) {
      this.error.set('Selecciona una orden y completa la cotización.');
      return;
    }
    const draft: QuotationDraft = {
      description: this.description,
      items: [{
        description: this.itemDescription,
        type: this.itemType,
        quantity: this.quantity,
        unitPrice: this.unitPrice,
      }],
    };
    try {
      await this.service.createQuotation(this.selectedOrderId, draft);
      this.closeBuilder();
      this.feedback.set('Cotización creada correctamente.');
      await this.refresh();
    } catch {
      this.error.set('No se pudo crear la cotización. Verifica que la orden no tenga otra pendiente.');
    }
  }

  protected async decide(quotation: Quotation, decision: 'AUTORIZADA' | 'RECHAZADA'): Promise<void> {
    try {
      await this.service.decideQuotation(
        quotation.id,
        decision,
        this.decisionObservations,
      );
      this.decisionObservations = '';
      this.feedback.set(`Cotización ${decision.toLocaleLowerCase()}.`);
      await this.refresh();
    } catch {
      this.error.set('No se pudo registrar la decisión del cliente.');
    }
  }

  protected statusLabel(status: Quotation['status']): string {
    return {
      PENDIENTE: 'Pendiente',
      AUTORIZADA: 'Autorizada',
      RECHAZADA: 'Rechazada',
    }[status];
  }

  protected downloadQuotation(quotation: Quotation): void {
    if (quotation.status !== 'AUTORIZADA') return;
    this.service.downloadQuotationPdf(quotation.id);
  }
}
