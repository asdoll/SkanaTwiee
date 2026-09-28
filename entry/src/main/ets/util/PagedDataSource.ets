import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'PagedDataSource';

/** Anything a paging data source needs to know about one response page. */
export interface PagedPage<T> {
  items: T[];
  cursor: string;
  hasNextPage: boolean;
}

/** Fetches one page; `after` is '' for the first page. */
export type PagedLoader<T> = (after: string) => Promise<PagedPage<T>>;

/**
 * Paging data source for LazyForEach, shared by every paged list in the app.
 *
 * Replaces Android's Paging 3 PagingSource: the loader is a plain async function
 * and the source notifies LazyForEach about appended items. `PagedPage` is
 * structural, so each model's own *Page class satisfies it without conversion.
 */
export class PagedDataSource<T> implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: T[] = [];
  private cursor: string = '';
  private hasMore: boolean = true;
  private loading: boolean = false;
  private failed: boolean = false;
  private loader: PagedLoader<T>;

  constructor(loader: PagedLoader<T>) {
    this.loader = loader;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  isEmpty(): boolean {
    return this.items.length === 0;
  }

  hasFailed(): boolean {
    return this.failed;
  }

  isLoading(): boolean {
    return this.loading;
  }

  hasMorePages(): boolean {
    return this.hasMore;
  }

  /** Clears everything and loads the first page. */
  async refresh(): Promise<void> {
    this.items = [];
    this.cursor = '';
    this.hasMore = true;
    this.failed = false;
    this.notifyReload();
    await this.loadMore();
  }

  async loadMore(): Promise<void> {
    if (this.loading || !this.hasMore) {
      return;
    }
    this.loading = true;
    const firstPage: boolean = this.items.length === 0;
    try {
      const page: PagedPage<T> = await this.loader(this.cursor);
      this.cursor = page.cursor;
      this.hasMore = page.hasNextPage && page.cursor.length > 0;
      this.failed = false;
      const start: number = this.items.length;
      for (let i = 0; i < page.items.length; i++) {
        this.items.push(page.items[i]);
      }
      if (firstPage) {
        this.notifyReload();
      } else {
        for (let i = start; i < this.items.length; i++) {
          this.notifyAdd(i);
        }
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'page load failed: %{public}s', JSON.stringify(e));
      this.failed = true;
      this.notifyReload();
    } finally {
      this.loading = false;
    }
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  private notifyAdd(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }
}
